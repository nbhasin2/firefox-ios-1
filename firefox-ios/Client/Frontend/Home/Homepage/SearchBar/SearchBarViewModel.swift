// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Foundation
import Redux
import UIKit

/// Replaces `SearchBarState` and the search-bar half of `HomepageMiddleware`.
///
/// The first consumer of the retained browser event bus (D-016/D-019). The search bar is hidden by
/// three events that originate outside the homepage — entering zero-search, the toolbar being
/// unhidden, and the address bar starting to edit — none of which the homepage owns or is owned by.
/// It observes them instead of keeping a `ScreenState` in the store to hang a subscription off.
@MainActor
final class SearchBarViewModel {
    private(set) var shouldShowSearchBar = false

    var onChange: (() -> Void)?

    private let windowUUID: WindowUUID
    private let isFeatureEnabled: () -> Bool
    private let isLandscape: () -> Bool
    private let deviceIdiom: () -> UIUserInterfaceIdiom
    /// The store holds observers weakly and sweeps dead ones before each notification, so there
    /// is nothing to unregister on deinit.
    private let bus: (any ActionObserving)?
    private let visibilityStore: SearchBarVisibilityStore

    init(windowUUID: WindowUUID,
         isFeatureEnabled: @escaping () -> Bool = {
             (AppContainer.shared.resolve() as FeatureFlagProviding).isEnabled(.homepageSearchBar)
         },
         isLandscape: @escaping () -> Bool = { UIWindow.isLandscape },
         deviceIdiom: @escaping () -> UIUserInterfaceIdiom = { UIDevice.current.userInterfaceIdiom },
         bus: (any ActionObserving)? = browserEventBus,
         visibilityStore: SearchBarVisibilityStore = .shared) {
        self.windowUUID = windowUUID
        self.visibilityStore = visibilityStore
        self.isFeatureEnabled = isFeatureEnabled
        self.isLandscape = isLandscape
        self.deviceIdiom = deviceIdiom
        self.bus = bus
        observeHideEvents()
    }

    // MARK: - Intents

    /// Recomputed on the homepage lifecycle events the middleware recomputed on: initialize,
    /// view-will-transition, cancel-edit, navigate-back, and closing a tab from the toolbar.
    func refreshVisibility() {
        let isCompact = deviceIdiom() == .phone && !isLandscape()
        setVisible(isFeatureEnabled() && isCompact)
    }

    // MARK: - Private

    private func observeHideEvents() {
        bus?.addActionObserver(self) { [weak self] action in
            guard let self, action.windowUUID == self.windowUUID || action.windowUUID == .unavailable else { return }
            switch action.actionType {
            case GeneralBrowserActionType.enteredZeroSearchScreen,
                 GeneralBrowserActionType.didUnhideToolbar,
                 ToolbarActionType.didStartEditingUrl:
                self.setVisible(false)

            // The middleware recomputed visibility on these; the observer sees every legacy
            // action, so the toolbar family is reachable here even though it has not migrated.
            case ToolbarActionType.cancelEdit,
                 GeneralBrowserActionType.navigateBack,
                 GeneralBrowserActionType.didCloseTabFromToolbar:
                self.refreshVisibility()

            default:
                break
            }
        }
    }

    private func setVisible(_ isVisible: Bool) {
        guard isVisible != shouldShowSearchBar else { return }
        shouldShowSearchBar = isVisible
        // BrowserViewController and its reducer read this; see SearchBarVisibilityStore.
        visibilityStore.setSearchBarVisible(isVisible, for: windowUUID)
        onChange?()
    }
}
