// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Foundation
import Redux
import Storage

/// Fetching and mutating the top sites, extracted from `TopSitesMiddleware`.
///
/// Two screens show top sites — the homepage and the shortcuts library — and each used to trigger
/// a fetch by dispatching its own `initialize` action. They call `refresh(for:)` here instead.
///
/// The service still dispatches `TopSitesMiddlewareActionType.retrievedUpdatedSites` after a
/// fetch. That is deliberate and temporary: `ShortcutsLibraryState` reduces it and cannot observe
/// a service, being a static function. It goes when the shortcuts library migrates (D-025).
@MainActor
final class TopSitesService {
    static let shared = TopSitesService()

    private(set) var topSites: [TopSiteConfiguration] = []

    /// Fired after every successful fetch, for consumers that own their state.
    var onSitesChange: (([TopSiteConfiguration]) -> Void)?

    private let topSitesManager: TopSitesManagerInterface
    private let featureFlagsProvider: FeatureFlagProviding
    /// One fetch at a time per window, so `initialize`, foregrounding and the top-sites
    /// notification do not fire parallel sponsored requests on launch. Slow networks otherwise
    /// see several in flight at once.
    private var inFlightWindowIDs = Set<WindowUUID>()

    init(
        profile: Profile = AppContainer.shared.resolve(),
        topSitesManager: TopSitesManagerInterface? = nil,
        featureFlagsProvider: FeatureFlagProviding = AppContainer.shared.resolve(),
        searchEnginesManager: SearchEnginesManager = AppContainer.shared.resolve()
    ) {
        self.topSitesManager = topSitesManager ?? TopSitesManager(
            profile: profile,
            googleTopSiteManager: GoogleTopSiteManager(prefs: profile.prefs),
            topSiteHistoryManager: TopSiteHistoryManager(profile: profile),
            searchEnginesManager: searchEnginesManager
        )
        self.featureFlagsProvider = featureFlagsProvider
    }

    // MARK: - Fetching

    /// `coalesce` mirrors the middleware: the launch and foreground triggers coalesce, an explicit
    /// user action (toggling sponsored shortcuts) does not.
    func refresh(for windowUUID: WindowUUID, coalesce: Bool = true) {
        if coalesce {
            guard inFlightWindowIDs.insert(windowUUID).inserted else { return }
        }

        Task { @MainActor in
            defer {
                if coalesce { self.inFlightWindowIDs.remove(windowUUID) }
            }
            async let sponsoredSites = await self.topSitesManager.fetchSponsoredSites()
            async let otherSites = await self.topSitesManager.getOtherSites()
            let sites = await self.topSitesManager.recalculateTopSites(
                otherSites: otherSites,
                sponsoredSites: sponsoredSites
            )
            self.publish(sites, for: windowUUID)
        }
    }

    // MARK: - Mutations

    func pin(_ site: Site) {
        topSitesManager.pinTopSite(site)
    }

    func unpin(_ site: Site) {
        // Capturing the manager rather than self: the mutation does not need the service, and a
        // task holding it would outlive the call.
        let manager = topSitesManager
        Task { @MainActor in
            await manager.unpinTopSite(site)
        }
    }

    func remove(_ site: Site) {
        let manager = topSitesManager
        Task { @MainActor in
            await manager.removeTopSite(site)
        }
    }

    // MARK: - Private

    private func publish(_ sites: [TopSiteConfiguration], for windowUUID: WindowUUID) {
        topSites = sites
        onSitesChange?(sites)
        store.dispatch(
            TopSitesAction(
                topSites: sites,
                shouldShowAddShortcutTile: featureFlagsProvider.isEnabled(.homepageAddShortcutTile),
                windowUUID: windowUUID,
                actionType: TopSitesMiddlewareActionType.retrievedUpdatedSites
            )
        )
    }
}
