// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Foundation
import Redux
import Shared
import Storage

/// Replaces `JumpBackInSectionState`'s reducer and the homepage halves of `TabManagerMiddleware`
/// and `RemoteTabsPanelMiddleware`.
///
/// `JumpBackInSectionState` stays a plain struct because the diffable data source and the layout
/// provider both take one; only its Redux conformance goes.
///
/// The refresh triggers split three ways, which is the D-017 routing rule in miniature. Homepage
/// lifecycle is a direct call. Account and sync changes are notifications the homepage already
/// observes. Closing a tab, opening one from top tabs, dismissing the tab tray — those are
/// browser-level events with no ownership path to the homepage, so they come off the bus (D-016).
@MainActor
final class JumpBackInSectionViewModel {
    private(set) var state: JumpBackInSectionState {
        didSet {
            guard state != oldValue else { return }
            onChange?()
        }
    }

    var onChange: (() -> Void)?

    private let windowUUID: WindowUUID
    private let recentTabsProvider: RecentTabsProviding
    private let syncedTabProvider: SyncedTabProviding
    /// The store holds observers weakly and sweeps dead ones, so there is nothing to unregister.
    private let bus: (any ActionObserving)?
    private var syncedTabTask: Task<Void, Never>?

    init(windowUUID: WindowUUID,
         userPreferences: UserFeaturePreferring = AppContainer.shared.resolve(),
         recentTabsProvider: RecentTabsProviding? = nil,
         syncedTabProvider: SyncedTabProviding? = nil,
         bus: (any ActionObserving)? = store,
         initialState: JumpBackInSectionState? = nil) {
        self.windowUUID = windowUUID
        self.recentTabsProvider = recentTabsProvider ?? DefaultRecentTabsProvider()
        self.syncedTabProvider = syncedTabProvider ?? DefaultSyncedTabProvider()
        self.bus = bus
        self.state = initialState ?? JumpBackInSectionState(userPreferences: userPreferences)
        observeTabEvents()
    }

    // MARK: - Intents

    /// Homepage `viewWillAppear`, and whenever the tab layer changes underneath it.
    func refresh() {
        refreshLocalTabs()
        refreshSyncedTab()
    }

    func refreshLocalTabs() {
        let tabs = recentTabsProvider.recentTabs(for: windowUUID)
        state = state.copy(jumpBackInTabs: tabs.map(Self.configuration(for:)))
    }

    func refreshSyncedTab() {
        syncedTabTask?.cancel()
        syncedTabTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let remoteTab = await self.syncedTabProvider.mostRecentSyncedTab()
            guard !Task.isCancelled, let remoteTab else { return }
            self.state = self.state.copy(mostRecentSyncedTab: Self.configuration(for: remoteTab))
        }
    }

    func setSectionEnabled(_ isEnabled: Bool) {
        state = state.copy(shouldShowSection: isEnabled)
    }

    // MARK: - Private

    private func observeTabEvents() {
        bus?.addActionObserver(self) { [weak self] action in
            guard let self, action.windowUUID == self.windowUUID || action.windowUUID == .unavailable else { return }
            switch action.actionType {
            case TabTrayActionType.dismissTabTray,
                 TabTrayActionType.modalSwipedToClose,
                 TabTrayActionType.doneButtonTapped,
                 TabPanelViewActionType.addNewTab,
                 TopTabsActionType.didTapNewTab,
                 TopTabsActionType.didTapCloseTab:
                self.refresh()
            default:
                break
            }
        }
    }

    private static func configuration(for tab: Tab) -> JumpBackInTabConfiguration {
        let itemURL = tab.lastKnownUrl?.absoluteString ?? ""
        let site = Site.createBasicSite(url: itemURL, title: tab.displayTitle)
        return JumpBackInTabConfiguration(
            tab: tab,
            titleText: site.title,
            descriptionText: site.tileURL.shortDisplayString.capitalized,
            siteURL: itemURL
        )
    }

    private static func configuration(for remoteTab: RemoteTabConfiguration) -> JumpBackInSyncedTabConfiguration {
        let itemURL = remoteTab.tab.URL.absoluteString
        let site = Site.createBasicSite(url: itemURL, title: remoteTab.tab.title)
        return JumpBackInSyncedTabConfiguration(
            titleText: site.title,
            descriptionText: remoteTab.client.name,
            url: remoteTab.tab.URL
        )
    }
}
