// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import WebCompatReporterKit
import XCTest

@testable import Client

@MainActor
final class WebCompatReportViewControllerTests: XCTestCase {
    let windowUUID: WindowUUID = .XCTestDefaultUUID
    private var viewModel: WebCompatReporterViewModel!

    override func setUp() async throws {
        try await super.setUp()
        DependencyHelperMock().bootstrapDependencies()
        viewModel = WebCompatReporterViewModel(windowUUID: windowUUID)
    }

    override func tearDown() async throws {
        viewModel = nil
        DependencyHelperMock().reset()
        try await super.tearDown()
    }

    func testViewDidLoad_hostsSheetAsSingleRootViewController() {
        let subject = createSubject(reportedURL: URL(string: "https://example.com"))

        subject.loadViewIfNeeded()

        XCTAssertEqual(subject.viewControllers.count, 1)
        XCTAssertTrue(subject.viewControllers.first is WebCompatReportSheetViewController)
    }

    func testDidTapClose_notifiesCoordinatorToDismiss() {
        let coordinator = MockWebCompatReportCoordinatorDelegate()
        let subject = createSubject(reportedURL: nil)
        subject.reportCoordinator = coordinator
        subject.loadViewIfNeeded()

        subject.webCompatReportSheetDidTapClose()

        XCTAssertEqual(coordinator.didFinishCallCount, 1)
    }

    // MARK: - Delegate intents → view model

    func testDidTapLearnMore_forwardsURLToCoordinator() throws {
        let learnMoreURL = try XCTUnwrap(URL(string: "https://example.com/learn-more"))
        let coordinator = MockWebCompatReportCoordinatorDelegate()
        let subject = createSubject(reportedURL: nil)
        subject.reportCoordinator = coordinator
        subject.loadViewIfNeeded()

        subject.webCompatReportSheetDidTapLearnMore(url: learnMoreURL)

        XCTAssertEqual(coordinator.didTapLearnMoreURLs, [learnMoreURL])
    }

    func testDidToggle_onScreenshotRow_updatesTheDraft() {
        let subject = createSubject(reportedURL: nil)

        subject.webCompatReportSheetDidToggleCheckbox(id: "includeScreenshot", isChecked: false)

        XCTAssertFalse(viewModel.state.includeScreenshot)
    }

    func testDidToggle_onBlockedListRow_updatesTheDraft() {
        let subject = createSubject(reportedURL: nil)
        viewModel.toggleBlockedList(false)

        subject.webCompatReportSheetDidToggleCheckbox(id: "includeBlockedList", isChecked: true)

        XCTAssertTrue(viewModel.state.includeBlockedList)
    }

    func testDidToggle_onSendRow_changesNothing() {
        let subject = createSubject(reportedURL: nil)
        let before = viewModel.state

        subject.webCompatReportSheetDidToggleCheckbox(id: "send", isChecked: true)

        XCTAssertEqual(viewModel.state, before)
    }

    func testDidToggle_onUnhandledRow_changesNothing() {
        let subject = createSubject(reportedURL: nil)
        let before = viewModel.state

        subject.webCompatReportSheetDidToggleCheckbox(id: "unknown", isChecked: true)

        XCTAssertEqual(viewModel.state, before)
    }

    func testDidEditText_onURLRow_updatesTheDraft() {
        let subject = createSubject(reportedURL: nil)

        subject.webCompatReportSheetDidEditText(id: "url", text: "https://changed.example.com")

        XCTAssertEqual(viewModel.state.url, "https://changed.example.com")
    }

    func testDidEditText_onDetailsRow_updatesTheDraft() {
        let subject = createSubject(reportedURL: nil)

        subject.webCompatReportSheetDidEditText(id: "additionalDetails", text: "Images never load")

        XCTAssertEqual(viewModel.state.additionalDetails, "Images never load")
    }

    func testDidEditText_onNonTextRow_changesNothing() {
        let subject = createSubject(reportedURL: nil)
        let before = viewModel.state

        subject.webCompatReportSheetDidEditText(id: "send", text: "ignored")

        XCTAssertEqual(viewModel.state, before)
    }

    func testDidTapPreview_handsThePayloadToTheCoordinator() throws {
        let coordinator = MockWebCompatReportCoordinatorDelegate()
        let subject = createSubject(reportedURL: nil)
        subject.reportCoordinator = coordinator
        subject.loadViewIfNeeded()
        viewModel.editURL("https://example.com")
        viewModel.selectCategory(.videoOrAudio)

        subject.webCompatReportSheetDidTapPreview()

        // Assembling the report stays in the view model, so preview and submit can't drift.
        XCTAssertEqual(coordinator.didTapPreviewPayloads.map(\.url), ["https://example.com"])
    }

    func testDidTapPreview_withAnUnreportableURL_leavesTheCoordinatorAlone() {
        let coordinator = MockWebCompatReportCoordinatorDelegate()
        let subject = createSubject(reportedURL: nil)
        subject.reportCoordinator = coordinator
        subject.loadViewIfNeeded()
        viewModel.editURL(".com")

        subject.webCompatReportSheetDidTapPreview()

        XCTAssertTrue(coordinator.didTapPreviewPayloads.isEmpty)
    }

    func testSubmit_notifiesTheCoordinator() {
        let coordinator = MockWebCompatReportCoordinatorDelegate()
        let subject = createSubject(reportedURL: nil)
        subject.reportCoordinator = coordinator
        subject.loadViewIfNeeded()
        viewModel.editURL("https://example.com")

        subject.webCompatReportSheetDidTapButton(id: "send")

        XCTAssertEqual(coordinator.didSubmitCallCount, 1)
    }

    func testDidTapButton_onUnhandledRow_doesNotSubmit() {
        let coordinator = MockWebCompatReportCoordinatorDelegate()
        let subject = createSubject(reportedURL: nil)
        subject.reportCoordinator = coordinator
        subject.loadViewIfNeeded()
        viewModel.editURL("https://example.com")

        subject.webCompatReportSheetDidTapButton(id: "unknown")

        XCTAssertEqual(coordinator.didSubmitCallCount, 0)
    }

    func testStateChange_reconfiguresTheSheet() {
        let subject = createSubject(reportedURL: nil)
        subject.loadViewIfNeeded()

        viewModel.editURL("https://example.com")
        viewModel.selectCategory(.other)

        let sheet = subject.viewControllers.first as? WebCompatReportSheetViewController
        XCTAssertNotNil(sheet)
    }

    func testSimpleCreation_hasNoLeaks() {
        let subject = createSubject(reportedURL: nil)
        subject.loadViewIfNeeded()
        trackForMemoryLeaks(subject)
    }

    // MARK: - makeIssueSections

    func testMakeIssueSections_withoutCategory_showsPlaceholderAndNoSubOptions() {
        let state = WebCompatReporterState().copy(url: "https://example.com")

        let sections = WebCompatReportViewController.makeIssueSections(from: state)

        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections.first?.title, .WebCompatReporter.IssueSection.Title)
        XCTAssertEqual(sections.first?.rows.first?.title, .WebCompatReporter.IssueSection.CategoryPlaceholder)
        guard case let .categoryMenu(isPlaceholder, options) = sections.first?.rows.first?.kind else {
            return XCTFail("Expected a category menu row")
        }
        XCTAssertTrue(isPlaceholder)
        XCTAssertEqual(options.count, WebCompatIssueCategory.allCases.count)
        XCTAssertTrue(options.allSatisfy { !$0.isSelected })
    }

    func testMakeIssueSections_withCategory_addsSubOptionsWithCheckmarkOnSelected() {
        let state = WebCompatReporterState()
            .copy(url: "https://example.com")
            .copy(selectedCategory: .siteNotUsable)
            .copy(selectedSubOptionID: WebCompatSubOption.pageNotLoading.rawValue)

        let sections = WebCompatReportViewController.makeIssueSections(from: state)

        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections[0].rows.first?.title, .WebCompatReporter.Category.SiteNotUsable)
        guard case let .categoryMenu(isPlaceholder, options) = sections[0].rows.first?.kind else {
            return XCTFail("Expected a category menu row")
        }
        XCTAssertFalse(isPlaceholder)
        XCTAssertEqual(options.first { $0.isSelected }?.id, WebCompatIssueCategory.siteNotUsable.id)

        let subOptionRows = sections[1].rows
        XCTAssertEqual(subOptionRows.map(\.id), WebCompatIssueCategory.siteNotUsable.subOptions.map(\.rawValue))
        let selectedRows = subOptionRows.filter { $0.kind == .subOption(isSelected: true) }
        XCTAssertEqual(selectedRows.map(\.id), [WebCompatSubOption.pageNotLoading.rawValue])
    }

    func testMakeIssueSections_withOtherCategory_hasNoSubOptionSection() {
        let state = WebCompatReporterState()
            .copy(url: "https://example.com")
            .copy(selectedCategory: .other)

        let sections = WebCompatReportViewController.makeIssueSections(from: state)

        XCTAssertEqual(sections.count, 1)
    }

    // MARK: - makeSections

    func testMakeSections_withoutCategory_showsURLCategoryAdvancedAndDisabledSend() {
        let state = WebCompatReporterState().copy(url: "https://example.com")

        let sections = WebCompatReportViewController.makeSections(from: state)

        // No sub-options and no details until a category is picked.
        XCTAssertEqual(sections.map(\.id), ["url", "issueCategory", "advancedOptions", "send"])

        let advanced = sections.first { $0.id == "advancedOptions" }
        XCTAssertEqual(advanced?.rows.map(\.kind), [.checkbox(isChecked: true)])
        XCTAssertEqual(sections.last?.rows.map(\.kind), [.sendButton(isEnabled: false)])

        guard case let .urlField(text, errorMessage) = sections.first?.rows.first?.kind else {
            return XCTFail("Expected a URL field row")
        }
        XCTAssertEqual(text, "https://example.com")
        XCTAssertNil(errorMessage)
    }

    func testMakeSections_withAnUnreportableURL_carriesTheErrorAndDisablesSend() throws {
        let state = WebCompatReporterState()
            .copy(url: ".com")
            .copy(selectedCategory: .other)

        let sections = WebCompatReportViewController.makeSections(from: state)

        guard case let .urlField(text, errorMessage) = sections.first?.rows.first?.kind else {
            return XCTFail("Expected a URL field row")
        }
        XCTAssertEqual(text, ".com")
        XCTAssertEqual(errorMessage, .WebCompatReporter.Fields.URLError)
        XCTAssertEqual(sections.last?.rows.map(\.kind), [.sendButton(isEnabled: false)])

        let cleared = WebCompatReportViewController.makeSections(
            from: WebCompatReporterState()
                .copy(url: "")
                .copy(selectedCategory: .other)
        )
        guard case let .urlField(_, clearedError) = cleared.first?.rows.first?.kind else {
            return XCTFail("Expected a URL field row")
        }
        XCTAssertNil(clearedError)
    }

    func testMakeSections_withCategory_addsSubOptionsDetailsAndAdvancedWithSendLast() {
        let state = WebCompatReporterState()
            .copy(url: "https://example.com")
            .copy(selectedCategory: .siteNotUsable)
            .copy(selectedSubOptionID: WebCompatSubOption.pageNotLoading.rawValue)
            .copy(additionalDetails: "Broken images")
            .copy(includeScreenshot: false)
            .copy(includeBlockedList: true)

        let sections = WebCompatReportViewController.makeSections(from: state)

        XCTAssertEqual(
            sections.map(\.id),
            ["url", "issueCategory", "issueSubOptions", "additionalDetails", "advancedOptions", "send"]
        )

        let advanced = sections.first { $0.id == "advancedOptions" }
        XCTAssertEqual(advanced?.rows.map(\.kind), [.checkbox(isChecked: true)])
        XCTAssertEqual(sections.last?.rows.map(\.kind), [.sendButton(isEnabled: true)])

        let details = sections.first { $0.id == "additionalDetails" }
        guard case let .detailsField(text, _) = details?.rows.first?.kind else {
            return XCTFail("Expected a details field row")
        }
        XCTAssertEqual(text, "Broken images")
    }

    func testMakeSections_attachesLearnMoreFooterWithATappableLink() throws {
        let state = WebCompatReporterState().copy(url: "https://example.com")

        let sections = WebCompatReportViewController.makeSections(from: state)

        XCTAssertEqual(sections.filter { $0.footer != nil }.map(\.id), ["advancedOptions"])

        // The footer view locates the link by searching `text` for `linkText`; if the
        // format string and the link string drift apart the link silently stops rendering.
        let footer = try XCTUnwrap(sections.first { $0.id == "advancedOptions" }?.footer)
        XCTAssertTrue(footer.text.contains(footer.linkText))
        XCTAssertNotNil(footer.linkURL)
    }

    private func createSubject(reportedURL: URL?) -> WebCompatReportViewController {
        return WebCompatReportViewController(
            windowUUID: windowUUID,
            reportedURL: reportedURL,
            viewModel: viewModel
        )
    }
}

private final class MockWebCompatReportCoordinatorDelegate: WebCompatReportCoordinatorDelegate {
    var didFinishCallCount = 0
    var didSubmitCallCount = 0
    var didTapLearnMoreURLs: [URL] = []
    var didTapPreviewPayloads: [WebCompatReportPayload] = []

    func webCompatReportViewControllerDidFinish() {
        didFinishCallCount += 1
    }

    func webCompatReportViewControllerDidSubmit() {
        didSubmitCallCount += 1
    }

    func webCompatReportViewControllerDidTapLearnMore(url: URL) {
        didTapLearnMoreURLs.append(url)
    }

    func webCompatReportViewControllerDidTapPreview(payload: WebCompatReportPayload) {
        didTapPreviewPayloads.append(payload)
    }
}
