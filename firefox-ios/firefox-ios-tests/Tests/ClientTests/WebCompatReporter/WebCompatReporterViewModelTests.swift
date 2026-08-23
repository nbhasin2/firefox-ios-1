// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Glean
import XCTest

@testable import Client

/// Replaces `WebCompatReporterMiddlewareTests` and the reducer half of
/// `WebCompatReporterStateTests`: the intents below are the same transitions and effects,
/// now driven directly instead of through dispatched actions.
@MainActor
final class WebCompatReporterViewModelTests: XCTestCase {
    private var gleanWrapper: MockGleanWrapper!

    override func setUp() {
        super.setUp()
        DependencyHelperMock().bootstrapDependencies()
        gleanWrapper = MockGleanWrapper()
    }

    override func tearDown() {
        gleanWrapper = nil
        DependencyHelperMock().reset()
        super.tearDown()
    }

    // MARK: - Draft transitions

    func test_viewDidLoad_seedsURL() {
        let subject = createSubject()

        subject.viewDidLoad(url: "https://example.com")

        XCTAssertEqual(subject.state.url, "https://example.com")
    }

    func test_viewDidLoad_withNilURL_preservesExistingURL() {
        let subject = createSubject()
        subject.editURL("https://mozilla.org")

        subject.viewDidLoad(url: nil)

        XCTAssertEqual(subject.state.url, "https://mozilla.org")
    }

    func test_editURL_updatesURL() {
        let subject = createSubject()

        subject.editURL("https://example.com")

        XCTAssertEqual(subject.state.url, "https://example.com")
    }

    func test_selectCategory_setsCategory() {
        let subject = createSubject()

        subject.selectCategory(.designBroken)

        XCTAssertEqual(subject.state.selectedCategory, .designBroken)
    }

    func test_selectCategory_clearsPreviousSubOption() {
        let subject = createSubject()
        subject.selectCategory(.siteNotUsable)
        subject.selectSubOption(id: WebCompatSubOption.pageNotLoading.rawValue)

        subject.selectCategory(.videoOrAudio)

        XCTAssertEqual(subject.state.selectedCategory, .videoOrAudio)
        XCTAssertNil(subject.state.selectedSubOptionID)
    }

    func test_selectCategory_sameCategory_keepsSubOption() {
        let subject = createSubject()
        subject.selectCategory(.siteNotUsable)
        subject.selectSubOption(id: WebCompatSubOption.pageNotLoading.rawValue)

        subject.selectCategory(.siteNotUsable)

        XCTAssertEqual(subject.state.selectedSubOptionID, WebCompatSubOption.pageNotLoading.rawValue)
    }

    func test_selectSubOption_setsSubOption() {
        let subject = createSubject()

        subject.selectSubOption(id: WebCompatSubOption.noAudio.rawValue)

        XCTAssertEqual(subject.state.selectedSubOptionID, WebCompatSubOption.noAudio.rawValue)
    }

    func test_setAdditionalDetails_updatesDetails() {
        let subject = createSubject()

        subject.setAdditionalDetails("the video never starts")

        XCTAssertEqual(subject.state.additionalDetails, "the video never starts")
    }

    func test_toggleScreenshot_withoutValue_flipsCurrent() {
        let subject = createSubject()
        XCTAssertTrue(subject.state.includeScreenshot)

        subject.toggleScreenshot()

        XCTAssertFalse(subject.state.includeScreenshot)
    }

    func test_toggleScreenshot_withExplicitValue_setsValue() {
        let subject = createSubject()

        subject.toggleScreenshot(false)

        XCTAssertFalse(subject.state.includeScreenshot)
    }

    func test_toggleBlockedList_withoutValue_flipsCurrent() {
        let subject = createSubject()
        XCTAssertTrue(subject.state.includeBlockedList)

        subject.toggleBlockedList()

        XCTAssertFalse(subject.state.includeBlockedList)
    }

    // MARK: - State publishing

    func test_onStateChange_firesForEachDistinctChange() {
        let subject = createSubject()
        var received: [WebCompatReporterState] = []
        subject.onStateChange = { received.append($0) }

        subject.editURL("https://example.com")
        subject.selectCategory(.other)

        XCTAssertEqual(received.count, 2)
        XCTAssertEqual(received.last?.url, "https://example.com")
        XCTAssertEqual(received.last?.selectedCategory, .other)
    }

    func test_onStateChange_doesNotFireWhenNothingChanged() {
        let subject = createSubject()
        subject.editURL("https://example.com")
        var callCount = 0
        subject.onStateChange = { _ in callCount += 1 }

        subject.editURL("https://example.com")

        XCTAssertEqual(callCount, 0)
    }

    // MARK: - Submit

    func test_submit_submitsThePingAndReportsCompletion() {
        let subject = createSubject()
        subject.editURL("https://example.com")
        var didSubmit = false
        subject.onSubmitted = { didSubmit = true }

        subject.submit()

        XCTAssertTrue(didSubmit)
        XCTAssertEqual(gleanWrapper.submitPingCalled, 1)
    }

    func test_submit_withAnUnreportableURL_sendsNothing() {
        let subject = createSubject()
        subject.editURL(".com")
        var didSubmit = false
        subject.onSubmitted = { didSubmit = true }

        subject.submit()

        XCTAssertFalse(didSubmit)
        XCTAssertEqual(gleanWrapper.submitPingCalled, 0)
    }

    func test_submit_whenURLStillMatchesTheTab_includesTabFields() {
        let tab = makeTab(url: "https://example.com/path")
        let subject = createSubject(selectedTab: tab)
        subject.editURL("https://example.com/path")

        subject.submit()

        XCTAssertEqual(gleanWrapper.submitPingCalled, 1)
        XCTAssertTrue(gleanWrapper.recordTextCalled > 0, "Expected tab-specific fields to be recorded")
    }

    func test_submit_whenURLNoLongerMatchesTheTab_dropsTabFields() {
        let tab = makeTab(url: "https://example.com/path")
        let subject = createSubject(selectedTab: tab)
        subject.editURL("https://mozilla.org/other")

        subject.submit()

        XCTAssertEqual(gleanWrapper.submitPingCalled, 1)
    }

    // MARK: - Preview

    func test_preview_reportsThePayload() throws {
        let subject = createSubject()
        subject.editURL("https://example.com")
        subject.selectCategory(.other)
        var payload: WebCompatReportPayload?
        subject.onPreviewReady = { payload = $0 }

        subject.preview()

        let received = try XCTUnwrap(payload)
        XCTAssertEqual(received.url, "https://example.com")
        XCTAssertEqual(received.breakageCategory, WebCompatIssueCategory.other.rawValue)
    }

    func test_preview_withAnUnreportableURL_buildsNothing() {
        let subject = createSubject()
        subject.editURL(".com")
        var payload: WebCompatReportPayload?
        subject.onPreviewReady = { payload = $0 }

        subject.preview()

        XCTAssertNil(payload)
    }

    func test_preview_carriesTheSubOptionOverTheCategory() throws {
        let subject = createSubject()
        subject.editURL("https://example.com")
        subject.selectCategory(.videoOrAudio)
        subject.selectSubOption(id: WebCompatSubOption.noAudio.rawValue)
        var payload: WebCompatReportPayload?
        subject.onPreviewReady = { payload = $0 }

        subject.preview()

        let received = try XCTUnwrap(payload)
        XCTAssertEqual(received.breakageCategory, WebCompatSubOption.noAudio.rawValue)
    }

    // MARK: - Telemetry

    func test_selectCategory_recordsReasonSelectedWithTheCategory() throws {
        let subject = createSubject()

        subject.selectCategory(.videoOrAudio)

        let event = GleanMetrics.BrokenSiteReportInteractions.reasonSelected
        let savedExtras = try XCTUnwrap(
            gleanWrapper.savedExtras.first as? GleanMetrics.BrokenSiteReportInteractions.ReasonSelectedExtra
        )
        let savedMetric = try XCTUnwrap(
            gleanWrapper.savedEvents.first
                as? EventMetricType<GleanMetrics.BrokenSiteReportInteractions.ReasonSelectedExtra>
        )

        XCTAssertEqual(gleanWrapper.recordEventCalled, 1)
        XCTAssertEqual(savedExtras.reason, WebCompatIssueCategory.videoOrAudio.rawValue)
        XCTAssert(savedMetric === event, "Received \(savedMetric) instead of \(event)")
    }

    func test_selectCategory_sameCategory_doesNotRecordAgain() {
        let subject = createSubject()
        subject.selectCategory(.videoOrAudio)

        subject.selectCategory(.videoOrAudio)

        XCTAssertEqual(gleanWrapper.recordEventCalled, 1)
    }

    func test_preview_recordsPreviewed() throws {
        let subject = createSubject()
        subject.editURL("https://example.com")

        subject.preview()

        try assertRecordedNoExtraEvent(GleanMetrics.BrokenSiteReportInteractions.previewed)
    }

    func test_cancel_recordsCancelled() throws {
        let subject = createSubject()

        subject.cancel()

        try assertRecordedNoExtraEvent(GleanMetrics.BrokenSiteReportInteractions.cancelled)
    }

    func test_learnMore_recordsLearnMoreTapped() throws {
        let subject = createSubject()

        subject.learnMoreTapped()

        try assertRecordedNoExtraEvent(GleanMetrics.BrokenSiteReportInteractions.learnMoreTapped)
    }

    func test_submit_recordsCreatedCarryingTheBlockedListChoice() throws {
        let subject = createSubject()
        subject.editURL("https://example.com")
        subject.toggleBlockedList(false)

        subject.submit()

        let savedExtras = try XCTUnwrap(
            gleanWrapper.savedExtras.first as? GleanMetrics.BrokenSiteReportInteractions.CreatedExtra
        )
        XCTAssertEqual(savedExtras.hasBlockedTrackersList, false)
        // The screenshot option is parked (FXIOS-16450), so a report never claims to carry one.
        XCTAssertEqual(savedExtras.hasScreenshot, false)
        XCTAssertEqual(gleanWrapper.submitPingCalled, 1)
    }

    // MARK: - Private Helpers

    private func assertRecordedNoExtraEvent<T: EventExtras>(
        _ event: EventMetricType<T>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let savedMetric = try XCTUnwrap(gleanWrapper.savedEvents.first as? EventMetricType<T>, file: file, line: line)
        XCTAssertEqual(gleanWrapper.recordEventNoExtraCalled, 1, file: file, line: line)
        XCTAssert(savedMetric === event, "Received \(savedMetric) instead of \(event)", file: file, line: line)
    }

    private func makeTab(url: String) -> Tab {
        let tab = Tab(profile: MockProfile(), windowUUID: .XCTestDefaultUUID)
        tab.url = URL(string: url)
        return tab
    }

    private func createSubject(selectedTab: Tab? = nil) -> WebCompatReporterViewModel {
        let tabManager = MockTabManager()
        tabManager.selectedTab = selectedTab
        let subject = WebCompatReporterViewModel(
            windowUUID: .XCTestDefaultUUID,
            windowManager: MockWindowManager(
                wrappedManager: WindowManagerImplementation(),
                tabManager: tabManager
            ),
            recorder: WebCompatReportRecorder(gleanWrapper: gleanWrapper),
            telemetry: WebCompatReporterTelemetry(gleanWrapper: gleanWrapper)
        )
        trackForMemoryLeaks(subject)
        return subject
    }
}
