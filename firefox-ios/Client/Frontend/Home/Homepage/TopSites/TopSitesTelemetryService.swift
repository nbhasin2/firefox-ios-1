// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Foundation
import Storage

/// The telemetry half of `TopSitesMiddleware`, which its own doc comment said should be split out.
///
/// Three of its callers - the app menu, the shortcuts library and the homepage's own pin action -
/// dispatched `TopSitesActionType.shortcutPinned`/`shortcutUnpinned` purely to reach it. They had
/// already done the pinning themselves; the action carried nothing but a telemetry source. Those
/// call the service directly now and the two action types are gone.
@MainActor
final class TopSitesTelemetryService {
    static let shared = TopSitesTelemetryService()

    private let homepageTelemetry: HomepageTelemetry
    private let bookmarksTelemetry: BookmarksTelemetry
    private let unifiedAdsTelemetry: UnifiedAdsCallbackTelemetry
    private let profile: Profile

    init(
        profile: Profile = AppContainer.shared.resolve(),
        homepageTelemetry: HomepageTelemetry = HomepageTelemetry(),
        bookmarksTelemetry: BookmarksTelemetry = BookmarksTelemetry(),
        unifiedAdsTelemetry: UnifiedAdsCallbackTelemetry = DefaultUnifiedAdsCallbackTelemetry()
    ) {
        self.profile = profile
        self.homepageTelemetry = homepageTelemetry
        self.bookmarksTelemetry = bookmarksTelemetry
        self.unifiedAdsTelemetry = unifiedAdsTelemetry
    }

    // MARK: - Shortcuts

    func sendShortcutPinned(source: HomepageTelemetry.TopSitesShortcutPinnedSource) {
        homepageTelemetry.sendTopSitesShortcutPinnedEvent(source: source)
    }

    func sendShortcutUnpinned(source: HomepageTelemetry.TopSitesShortcutUnpinnedSource) {
        homepageTelemetry.sendTopSitesShortcutUnpinnedEvent(source: source)
    }

    // MARK: - Tiles

    func sendSponsoredImpression(for config: TopSiteConfiguration, at position: Int) {
        guard config.site.isSponsoredSite else { return }
        unifiedAdsTelemetry.sendImpressionTelemetry(tileSite: config.site, position: position)
    }

    func sendTileTapped(_ config: TopSiteConfiguration, at position: Int, isZeroSearch: Bool) {
        if config.site.isSponsoredSite {
            unifiedAdsTelemetry.sendClickTelemetry(tileSite: config.site, position: position)
        }
        homepageTelemetry.sendTopSitesPressedEvent(
            position: position,
            tileType: config.getTelemetrySiteType,
            isZeroSearch: isZeroSearch
        )
        sendBookmarkOpenTelemetry(with: config.site.url)
    }

    // MARK: - Context menu

    func sendContextMenuOpened(for type: HomepageTelemetry.ContextMenuTelemetryActionType) {
        homepageTelemetry.sendContextMenuOpenedEventForTopSites(for: type)
    }

    func sendOpenInPrivateTab() {
        homepageTelemetry.sendOpenInPrivateTabEventForTopSites()
    }

    // MARK: - Private

    private func sendBookmarkOpenTelemetry(with urlString: String) {
        // Resolve the bookmark lookup off the main thread to avoid blocking it on a contended
        // Places DB query (this runs on the homepage tap path).
        profile.places.isBookmarked(url: urlString) { [weak self] result in
            guard case .success(true) = result else { return }
            Task { @MainActor in
                self?.bookmarksTelemetry.openBookmarksSite(eventLabel: .topSites)
            }
        }
    }
}
