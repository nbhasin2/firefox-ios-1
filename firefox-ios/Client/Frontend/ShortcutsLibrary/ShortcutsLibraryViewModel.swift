// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Foundation

/// Replaces `ShortcutsLibraryState` and `ShortcutsLibraryMiddleware`.
///
/// This is what D-025 was waiting for: the shortcuts library reduced
/// `TopSitesMiddlewareActionType.retrievedUpdatedSites` because a reducer is a static function
/// and cannot observe a service. The view model can, so `TopSitesService` stops dispatching.
@MainActor
final class ShortcutsLibraryViewModel {
    private(set) var shortcuts: [TopSiteConfiguration] = []
    private(set) var shouldShowAddShortcutTile = false

    var onChange: (() -> Void)?

    private let windowUUID: WindowUUID
    private let topSitesService: TopSitesService
    private let featureFlagsProvider: FeatureFlagProviding
    private let telemetry: ShortcutsLibraryTelemetry
    /// The viewed event fires once per presentation, not once per `viewDidAppear` — the library
    /// can be covered and revealed again without being a new visit. The state carried this as
    /// `shouldRecordImpressionTelemetry`.
    private var hasRecordedImpression = false

    init(windowUUID: WindowUUID,
         topSitesService: TopSitesService = .shared,
         featureFlagsProvider: FeatureFlagProviding = AppContainer.shared.resolve(),
         telemetry: ShortcutsLibraryTelemetry = ShortcutsLibraryTelemetry(),
         initialShortcuts: [TopSiteConfiguration] = [],
         initialShouldShowAddShortcutTile: Bool = false) {
        self.windowUUID = windowUUID
        self.topSitesService = topSitesService
        self.featureFlagsProvider = featureFlagsProvider
        self.telemetry = telemetry
        self.shortcuts = initialShortcuts
        self.shouldShowAddShortcutTile = initialShouldShowAddShortcutTile
        topSitesService.addSitesObserver(self) { [weak self] sites in
            self?.updateShortcuts(sites)
        }
    }

    // MARK: - Lifecycle

    func viewDidLoad() {
        topSitesService.refresh(for: windowUUID)
    }

    func viewDidAppear() {
        guard !hasRecordedImpression else { return }
        hasRecordedImpression = true
        telemetry.sendShortcutsLibraryViewedEvent()
    }

    func viewDidDisappear() {
        telemetry.sendShortcutsLibraryClosedEvent()
    }

    // MARK: - Intents

    func shortcutTapped() {
        telemetry.sendShortcutTappedEvent()
    }

    // MARK: - Private

    private func updateShortcuts(_ sites: [TopSiteConfiguration]) {
        shortcuts = sites
        shouldShowAddShortcutTile = featureFlagsProvider.isEnabled(.homepageAddShortcutTile)
        onChange?()
    }
}
