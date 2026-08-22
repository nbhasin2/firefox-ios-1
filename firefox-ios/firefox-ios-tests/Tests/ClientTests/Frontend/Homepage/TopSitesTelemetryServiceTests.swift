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

    func test_sendSponsoredImpression_withASponsoredTile_records() {
        let unifiedAds = MockUnifiedAdsCallbackTelemetry()
        let subject = createSubject(unifiedAdsTelemetry: unifiedAds)
        let config = TopSiteConfiguration(
            site: Site.createSponsoredSite(fromUnifiedTile: MockSponsoredTileData.defaultSuccessData.first!)
        )

        subject.sendSponsoredImpression(for: config, at: 0)

        XCTAssertEqual(unifiedAds.sendImpressionTelemetryCalled, 1)
    }

    func test_sendTileTapped_forASponsoredTile_recordsTheClickAndThePress() throws {
        let unifiedAds = MockUnifiedAdsCallbackTelemetry()
        let subject = createSubject(unifiedAdsTelemetry: unifiedAds)
        let config = TopSiteConfiguration(
            site: Site.createSponsoredSite(fromUnifiedTile: MockSponsoredTileData.defaultSuccessData.first!)
        )

        subject.sendTileTapped(config, at: 0, isZeroSearch: true)

        try checkTopSitesPressedMetrics(label: "zero-search", position: "0", tileType: "sponsored")
        XCTAssertEqual(mockGleanWrapper.savedEvents.count, 2)
        XCTAssertEqual(mockGleanWrapper.incrementLabeledCounterCalled, 1)
        XCTAssertEqual(mockGleanWrapper.recordEventCalled, 1)
        XCTAssertEqual(unifiedAds.sendClickTelemetryCalled, 1)
    }

    func test_sendTileTapped_forASuggestedTile_recordsThePressOnly() throws {
        let unifiedAds = MockUnifiedAdsCallbackTelemetry()
        let subject = createSubject(unifiedAdsTelemetry: unifiedAds)
        let config = TopSiteConfiguration(
            site: Site.createSuggestedSite(url: "www.mozilla.org", title: "Mozilla Site", trackingId: 0)
        )

        subject.sendTileTapped(config, at: 1, isZeroSearch: false)

        try checkTopSitesPressedMetrics(label: "origin-other", position: "1", tileType: "suggested")
        XCTAssertEqual(mockGleanWrapper.savedEvents.count, 2)
        XCTAssertEqual(mockGleanWrapper.incrementLabeledCounterCalled, 1)
        XCTAssertEqual(mockGleanWrapper.recordEventCalled, 1)
        XCTAssertEqual(unifiedAds.sendImpressionTelemetryCalled, 0)
    }

    func test_sendSponsoredImpression_withAnUnsponsoredTile_recordsNothing() {
        let unifiedAds = MockUnifiedAdsCallbackTelemetry()
        let subject = createSubject(unifiedAdsTelemetry: unifiedAds)
        let config = TopSiteConfiguration(site: Site.createBasicSite(url: "https://mozilla.org", title: "Mozilla"))

        subject.sendSponsoredImpression(for: config, at: 0)

        XCTAssertEqual(unifiedAds.sendImpressionTelemetryCalled, 0)
    }

    private func checkTopSitesPressedMetrics(label: String, position: String, tileType: String) throws {
        let firstMetric = GleanMetrics.TopSites.pressedTileOrigin
        let secondMetric = GleanMetrics.TopSites.tilePressed
        let firstSavedMetric = try XCTUnwrap(
            mockGleanWrapper.savedEvents.first as? LabeledMetricType<CounterMetricType>
        )
        let secondSavedMetric = try XCTUnwrap(
            mockGleanWrapper.savedEvents[safe: 1] as? EventMetricType<GleanMetrics.TopSites.TilePressedExtra>
        )
        let secondSavedExtras = try XCTUnwrap(
            mockGleanWrapper.savedExtras.first as? GleanMetrics.TopSites.TilePressedExtra
        )

        XCTAssert(firstSavedMetric === firstMetric, "Received \(firstSavedMetric) instead of \(firstMetric)")
        XCTAssert(secondSavedMetric === secondMetric, "Received \(secondSavedMetric) instead of \(secondMetric)")

        XCTAssertEqual(mockGleanWrapper.savedLabel as? String, label)
        XCTAssertEqual(secondSavedExtras.position, position)
        XCTAssertEqual(secondSavedExtras.tileType, tileType)
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
