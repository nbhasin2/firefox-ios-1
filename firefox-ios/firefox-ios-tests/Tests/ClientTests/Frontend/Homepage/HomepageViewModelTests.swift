// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Glean
import XCTest

@testable import Client

/// Replaces `HomepageMiddlewareTests`, `HomepageStateTests` and `HomepageTelemetryStateTests`.
@MainActor
final class HomepageViewModelTests: XCTestCase {
    private var mockGleanWrapper: MockGleanWrapper!
    private var privacyNoticeHelper: MockPrivacyNoticeHelper!
    private var notificationCenter: MockNotificationCenter!

    override func setUp() async throws {
        try await super.setUp()
        await DependencyHelperMock().bootstrapDependencies()
        mockGleanWrapper = MockGleanWrapper()
        privacyNoticeHelper = MockPrivacyNoticeHelper()
        notificationCenter = MockNotificationCenter()
    }

    override func tearDown() async throws {
        mockGleanWrapper = nil
        privacyNoticeHelper = nil
        notificationCenter = nil
        DependencyHelperMock().reset()
        try await super.tearDown()
    }

    // MARK: - Zero search

    /// Replaces `HomepageTelemetryStateTests`. BrowserCoordinator sets this when it embeds the
    /// homepage; it used to dispatch `HomepageActionType.embeddedHomepage` to say the same thing.
    func test_setZeroSearch_isReadBack() {
        let subject = createSubject()
        XCTAssertFalse(subject.isZeroSearch)

        subject.setZeroSearch(true)

        XCTAssertTrue(subject.isZeroSearch)
    }

    // MARK: - Impressions

    /// FXIOS-11523 - the `shouldTriggerImpression` flag the telemetry state carried.
    func test_didSelectTabChangeToHomepage_resetsImpressions() {
        let subject = createSubject()
        var resets = 0
        subject.onImpressionReset = { resets += 1 }

        subject.didSelectTabChangeToHomepage()

        XCTAssertEqual(resets, 1)
    }

    func test_recordHomepageImpression_recordsTheEvent() throws {
        let subject = createSubject()

        subject.recordHomepageImpression()

        // The homepage impression is the no-extras variant.
        XCTAssertEqual(mockGleanWrapper.recordEventNoExtraCalled, 1)
    }

    // MARK: - Item telemetry

    func test_recordItemTapped_recordsTheItemType() throws {
        let subject = createSubject()

        subject.recordItemTapped(.topSite)

        XCTAssertEqual(mockGleanWrapper.recordEventCalled, 1)
    }

    func test_recordSectionSeen_forQuickAnswers_recordsTheButtonViewedEvent() throws {
        let subject = createSubject()

        subject.recordSectionSeen(.quickAnswersEntryPoint)

        let savedMetric = try XCTUnwrap(
            mockGleanWrapper.savedEvents.first as? EventMetricType<NoExtras>
        )
        let event = GleanMetrics.AiQuickAnswers.buttonViewed
        XCTAssert(savedMetric === event, "Received \(savedMetric) instead of \(event)")
    }

    func test_recordSectionSeen_forAnySection_incrementsTheLabeledCounter() {
        let subject = createSubject()

        subject.recordSectionSeen(.topSite)

        XCTAssertEqual(mockGleanWrapper.incrementLabeledCounterCalled, 1)
    }

    // MARK: - Privacy notice

    func test_configurePrivacyNoticeIfNeeded_whenAvailable_showsIt() {
        privacyNoticeHelper.shouldShowResult = true
        let subject = createSubject()

        subject.configurePrivacyNoticeIfNeeded()

        XCTAssertTrue(subject.shouldShowPrivacyNotice)
    }

    func test_configurePrivacyNoticeIfNeeded_whenNotAvailable_doesNothing() {
        privacyNoticeHelper.shouldShowResult = false
        let subject = createSubject()

        subject.configurePrivacyNoticeIfNeeded()

        XCTAssertFalse(subject.shouldShowPrivacyNotice)
    }

    func test_configurePrivacyNoticeIfNeeded_recordsTheTermsOfUseImpression() {
        privacyNoticeHelper.shouldShowResult = true
        let subject = createSubject()

        subject.configurePrivacyNoticeIfNeeded()

        // The privacy notice is a Terms of Use surface.
        XCTAssertEqual(mockGleanWrapper.recordEventCalled, 1)
    }

    func test_privacyNoticeDismissed_hidesItAndRecords() {
        privacyNoticeHelper.shouldShowResult = true
        let subject = createSubject()
        subject.configurePrivacyNoticeIfNeeded()

        subject.privacyNoticeDismissed()

        XCTAssertFalse(subject.shouldShowPrivacyNotice)
        XCTAssertEqual(mockGleanWrapper.recordEventCalled, 2)
    }

    func test_privacyNoticeChange_publishesToTheViewController() {
        privacyNoticeHelper.shouldShowResult = true
        let subject = createSubject()
        var changes = 0
        subject.onSectionChange = { changes += 1 }

        subject.configurePrivacyNoticeIfNeeded()

        XCTAssertEqual(changes, 1)
    }

    // MARK: - Private Helpers

    private func createSubject() -> HomepageViewModel {
        let subject = HomepageViewModel(
            windowUUID: .XCTestDefaultUUID,
            messageCard: MessageCardViewModel(windowUUID: .XCTestDefaultUUID,
                                              messagingManager: MockGleanPlumbMessageManagerProtocol()),
            bookmarks: BookmarksSectionViewModel(bookmarksHandler: MockBookmarksHandler()),
            merino: MerinoSectionViewModel(merinoManager: MockMerinoManager()),
            header: HeaderViewModel(windowUUID: .XCTestDefaultUUID,
                                    quickAnswersStore: MockQuickAnswersStore()),
            wallpaper: WallpaperViewModel(wallpaperManager: WallpaperManagerMock(),
                                          initialState: WallpaperState()),
            topSites: TopSitesSectionViewModel(windowUUID: .XCTestDefaultUUID,
                                               profile: MockProfile(),
                                               topSitesService: makeTopSitesService(),
                                               featureFlagsProvider: MockNimbusFeatureFlags()),
            jumpBackIn: JumpBackInSectionViewModel(windowUUID: .XCTestDefaultUUID,
                                                   recentTabsProvider: MockRecentTabsProvider(),
                                                   syncedTabProvider: MockSyncedTabProvider(),
                                                   bus: nil),
            topSitesService: makeTopSitesService(),
            privacyNoticeHelper: privacyNoticeHelper,
            telemetry: HomepageTelemetry(gleanWrapper: mockGleanWrapper),
            termsOfUseTelemetry: TermsOfUseTelemetry(gleanWrapper: mockGleanWrapper),
            profile: MockProfile(),
            bus: nil,
            notificationCenter: notificationCenter
        )
        trackForMemoryLeaks(subject)
        return subject
    }

    private func makeTopSitesService() -> TopSitesService {
        return TopSitesService(topSitesManager: MockTopSitesManager(),
                               featureFlagsProvider: MockNimbusFeatureFlags())
    }
}
