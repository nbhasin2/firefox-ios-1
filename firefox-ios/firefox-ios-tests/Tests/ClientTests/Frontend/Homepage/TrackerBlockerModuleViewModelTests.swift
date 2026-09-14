// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import XCTest

@testable import Client

/// Replaces `TrackerBlockerModuleMiddlewareTests` and `TrackerBlockerModuleStateTests`.
/// The threshold-crossing rules are unchanged; only the trigger is.
@MainActor
final class TrackerBlockerModuleViewModelTests: XCTestCase {
    private var gleanWrapper: MockGleanWrapper!
    private var statsStore: MockTrackerBlockStatsStore!

    override func setUp() {
        super.setUp()
        DependencyHelperMock().bootstrapDependencies()
        gleanWrapper = MockGleanWrapper()
        statsStore = MockTrackerBlockStatsStore()
    }

    override func tearDown() {
        gleanWrapper = nil
        statsStore = nil
        DependencyHelperMock().reset()
        super.tearDown()
    }

    // MARK: - Blocked count

    func test_refreshBlockedCount_publishesTheLifetimeTotal() {
        let subject = createSubject(lifetimeTotal: 42)
        var changes = 0
        subject.onChange = { changes += 1 }

        subject.refreshBlockedCount()

        XCTAssertEqual(subject.blockedTrackerCount, 42)
        XCTAssertEqual(changes, 1)
    }

    func test_refreshBlockedCount_withUnchangedTotal_doesNotRepublish() {
        let subject = createSubject(lifetimeTotal: 42)
        subject.refreshBlockedCount()
        var changes = 0
        subject.onChange = { changes += 1 }

        subject.refreshBlockedCount()

        XCTAssertEqual(changes, 0)
    }

    // MARK: - Threshold telemetry

    func test_lifetimeBelowFourFigures_doesNotRecordThresholdTelemetry() {
        let subject = createSubject(lifetimeTotal: 40)

        subject.refreshBlockedCount()

        XCTAssertEqual(gleanWrapper.recordEventCalled, 0)
        XCTAssertEqual(statsStore.highestReportedFiguresToReturn, 0)
    }

    func test_lifetimeCrossesFourFigures_recordsThresholdOnce() {
        let subject = createSubject(lifetimeTotal: 1200)

        subject.refreshBlockedCount()

        XCTAssertEqual(gleanWrapper.recordEventCalled, 1)
        XCTAssertEqual(statsStore.highestReportedFiguresToReturn, 4)
    }

    func test_lifetimeAlreadyReported_doesNotReRecordThreshold() {
        statsStore.highestReportedFiguresToReturn = 4
        let subject = createSubject(lifetimeTotal: 1300)

        subject.refreshBlockedCount()

        XCTAssertEqual(gleanWrapper.recordEventCalled, 0)
        XCTAssertEqual(statsStore.highestReportedFiguresToReturn, 4)
    }

    func test_lifetimeCrossesNextBoundary_recordsOnlyNewBoundary() {
        statsStore.highestReportedFiguresToReturn = 4
        let subject = createSubject(lifetimeTotal: 12_000)

        subject.refreshBlockedCount()

        XCTAssertEqual(gleanWrapper.recordEventCalled, 1)
        XCTAssertEqual(statsStore.highestReportedFiguresToReturn, 5)
    }

    func test_lifetimeJumpsMultipleBoundaries_recordsEachOnce() {
        let subject = createSubject(lifetimeTotal: 120_000)

        subject.refreshBlockedCount()

        XCTAssertEqual(gleanWrapper.recordEventCalled, 3)
        XCTAssertEqual(statsStore.highestReportedFiguresToReturn, 6)
    }

    func test_lifetimeAboveEightFigures_capsAtEightFigures() {
        let subject = createSubject(lifetimeTotal: 1_500_000_000)

        subject.refreshBlockedCount()

        XCTAssertEqual(gleanWrapper.recordEventCalled, 5)
        XCTAssertEqual(statsStore.highestReportedFiguresToReturn, 8)
    }

    // MARK: - Section visibility

    /// Turning the setting off always hides the section, whatever the feature flag says.
    func test_setSectionEnabled_false_hidesTheSection() {
        let subject = createSubject(lifetimeTotal: 0)

        subject.setSectionEnabled(false)

        XCTAssertFalse(subject.shouldShowSection)
    }

    /// Ported from HomepageStateTests: the preference alone is not enough.
    func test_init_withFeatureDisabledAndPreferenceEnabled_hidesTheSection() {
        let profile = MockProfile()
        let mockNimbusLayer = MockNimbusFeatureFlagLayer()
        let userPreferences = UserFeaturePreferenceManager(prefs: profile.prefs, backendLayer: mockNimbusLayer)
        userPreferences.setPreferenceFor(.homepageTrackerBlockerModule, to: true)
        let featureFlagsProvider = FeatureFlagsProvider(prefs: profile.prefs, backendLayer: mockNimbusLayer)

        let subject = TrackerBlockerModuleViewModel(
            statsStore: statsStore,
            telemetry: TrackerBlockerTelemetry(gleanWrapper: gleanWrapper),
            userPreferences: userPreferences,
            featureFlagsProvider: featureFlagsProvider
        )

        XCTAssertFalse(subject.shouldShowSection)
    }

    // MARK: - Private Helpers

    private func createSubject(lifetimeTotal: Int) -> TrackerBlockerModuleViewModel {
        statsStore.lifetimeTotalToReturn = lifetimeTotal
        let subject = TrackerBlockerModuleViewModel(
            statsStore: statsStore,
            telemetry: TrackerBlockerTelemetry(gleanWrapper: gleanWrapper)
        )
        trackForMemoryLeaks(subject)
        return subject
    }
}

final class MockTrackerBlockStatsStore: TrackerBlockStatsStore {
    var lifetimeTotalToReturn = 0
    var highestReportedFiguresToReturn = 0

    func record(category: BlocklistCategory, count: Int, date: Date) {}
    func lifetimeTotal() -> Int { return lifetimeTotalToReturn }
    func lifetimeByCategory() -> [BlocklistCategory: Int] { return [:] }
    func currentWeekTotal(for date: Date) -> Int { return 0 }
    func currentWeekByCategory(for date: Date) -> [BlocklistCategory: Int] { return [:] }
    func trackingStartDate() -> Date? { return nil }
    func reset() {}
    func highestReportedFigures() -> Int { return highestReportedFiguresToReturn }
    func setHighestReportedFigures(_ figures: Int) { highestReportedFiguresToReturn = figures }
}
