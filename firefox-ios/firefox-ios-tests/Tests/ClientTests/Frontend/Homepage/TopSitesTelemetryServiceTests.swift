// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Glean
import Storage
import XCTest

@testable import Client

/// Replaces the shortcut-telemetry half of `TopSitesMiddlewareTests`. The app menu, the shortcuts
/// library and the homepage call this directly instead of dispatching an action that carried
/// nothing but the source.
@MainActor
final class TopSitesTelemetryServiceTests: XCTestCase {
    private var mockGleanWrapper: MockGleanWrapper!

    override func setUp() async throws {
        try await super.setUp()
        await DependencyHelperMock().bootstrapDependencies()
        mockGleanWrapper = MockGleanWrapper()
    }

    override func tearDown() async throws {
        mockGleanWrapper = nil
        DependencyHelperMock().reset()
        try await super.tearDown()
    }

    func test_sendShortcutPinned_recordsTheSource() throws {
        let subject = createSubject()

        subject.sendShortcutPinned(source: .homescreenButton)
        subject.sendShortcutPinned(source: .appMenu)
        subject.sendShortcutPinned(source: .contextMenu)

        let savedMetric = try XCTUnwrap(
            mockGleanWrapper.savedEvents.first as? EventMetricType<GleanMetrics.TopSites.ShortcutPinnedExtra>
        )
        let savedExtras = try XCTUnwrap(mockGleanWrapper.savedExtras as? [GleanMetrics.TopSites.ShortcutPinnedExtra])
        let event = GleanMetrics.TopSites.shortcutPinned

        XCTAssertEqual(mockGleanWrapper.recordEventCalled, 3)
        XCTAssert(savedMetric === event, "Received \(savedMetric) instead of \(event)")
        XCTAssertEqual(savedExtras.map(\.source), ["homescreen_button", "app_menu", "context_menu"])
    }

    func test_sendShortcutUnpinned_recordsTheSource() throws {
        let subject = createSubject()

        subject.sendShortcutUnpinned(source: .contextMenu)
        subject.sendShortcutUnpinned(source: .appMenu)

        let savedMetric = try XCTUnwrap(
            mockGleanWrapper.savedEvents.first as? EventMetricType<GleanMetrics.TopSites.ShortcutUnpinnedExtra>
        )
        let savedExtras = try XCTUnwrap(mockGleanWrapper.savedExtras as? [GleanMetrics.TopSites.ShortcutUnpinnedExtra])
        let event = GleanMetrics.TopSites.shortcutUnpinned

        XCTAssertEqual(mockGleanWrapper.recordEventCalled, 2)
        XCTAssert(savedMetric === event, "Received \(savedMetric) instead of \(event)")
        XCTAssertEqual(savedExtras.map(\.source), ["context_menu", "app_menu"])
    }

    func test_sendSponsoredImpression_withAnUnsponsoredTile_recordsNothing() {
        let unifiedAds = MockUnifiedAdsCallbackTelemetry()
        let subject = createSubject(unifiedAdsTelemetry: unifiedAds)
        let config = TopSiteConfiguration(site: Site.createBasicSite(url: "https://mozilla.org", title: "Mozilla"))

        subject.sendSponsoredImpression(for: config, at: 0)

        XCTAssertEqual(unifiedAds.sendImpressionTelemetryCalled, 0)
    }

    private func createSubject(
        unifiedAdsTelemetry: UnifiedAdsCallbackTelemetry? = nil
    ) -> TopSitesTelemetryService {
        let subject = TopSitesTelemetryService(
            homepageTelemetry: HomepageTelemetry(gleanWrapper: mockGleanWrapper),
            bookmarksTelemetry: BookmarksTelemetry(gleanWrapper: mockGleanWrapper),
            unifiedAdsTelemetry: unifiedAdsTelemetry ?? MockUnifiedAdsCallbackTelemetry()
        )
        trackForMemoryLeaks(subject)
        return subject
    }
}
