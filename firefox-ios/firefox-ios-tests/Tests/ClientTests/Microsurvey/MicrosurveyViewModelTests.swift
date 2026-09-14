// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import XCTest

@testable import Client

/// Replaces `MicrosurveyStateTests` and `MicrosurveyMiddlewareIntegrationTests`. The state was two
/// write-only navigation flags, so the reducer tests become coordinator assertions here.
@MainActor
final class MicrosurveyViewModelTests: XCTestCase {
    private var telemetry: MockMicrosurveyTelemetry!
    private var coordinator: MockMicrosurveyCoordinatorDelegate!
    private var closedPromptWindows: [WindowUUID]!

    override func setUp() async throws {
        try await super.setUp()
        await DependencyHelperMock().bootstrapDependencies()
        telemetry = MockMicrosurveyTelemetry()
        coordinator = MockMicrosurveyCoordinatorDelegate()
        closedPromptWindows = []
    }

    override func tearDown() async throws {
        telemetry = nil
        coordinator = nil
        closedPromptWindows = nil
        DependencyHelperMock().reset()
        try await super.tearDown()
    }

    // MARK: - Close

    func test_closeSurvey_dismissesTheFlow() {
        let subject = createSubject()

        subject.closeSurvey()

        XCTAssertEqual(coordinator.dismissFlowCalled, 1)
    }

    func test_closeSurvey_recordsDismissAndClosesThePrompt() {
        let subject = createSubject()

        subject.closeSurvey()

        XCTAssertEqual(telemetry.dismissButtonTappedCalledCount, 1)
        XCTAssertEqual(telemetry.lastSurveyId, MicrosurveyMock.model.id)
        // Closing the prompt also clears the toolbar border, so it must not be dropped.
        XCTAssertEqual(closedPromptWindows, [.XCTestDefaultUUID])
    }

    // MARK: - Privacy notice

    func test_tapPrivacyNotice_showsPrivacyWithTheSurveysUTMContent() {
        let subject = createSubject()

        subject.tapPrivacyNotice()

        XCTAssertEqual(telemetry.privacyNoticeTappedCalledCount, 1)
        XCTAssertEqual(coordinator.showPrivacyUTMContent, [MicrosurveyMock.model.utmContent])
    }

    // MARK: - Submit

    func test_submitSurvey_withASelection_recordsItAndClosesThePrompt() {
        let subject = createSubject()

        subject.submitSurvey(userSelection: "Very satisfied")

        XCTAssertEqual(telemetry.userResponseSubmittedCalledCount, 1)
        XCTAssertEqual(telemetry.lastUserSelection, "Very satisfied")
        XCTAssertEqual(closedPromptWindows, [.XCTestDefaultUUID])
    }

    func test_submitSurvey_withoutASelection_stillClosesThePromptButRecordsNoResponse() {
        let subject = createSubject()

        subject.submitSurvey(userSelection: nil)

        XCTAssertEqual(telemetry.userResponseSubmittedCalledCount, 0)
        XCTAssertEqual(closedPromptWindows, [.XCTestDefaultUUID])
    }

    func test_submitSurvey_doesNotDismissTheFlow() {
        let subject = createSubject()

        subject.submitSurvey(userSelection: "Very satisfied")

        // Submitting shows the confirmation page; only close dismisses.
        XCTAssertEqual(coordinator.dismissFlowCalled, 0)
    }

    // MARK: - Appearance telemetry

    func test_surveyDidAppear_recordsSurveyViewed() {
        let subject = createSubject()

        subject.surveyDidAppear()

        XCTAssertEqual(telemetry.surveyViewedCalledCount, 1)
    }

    func test_confirmationViewed_recordsConfirmationShown() {
        let subject = createSubject()

        subject.confirmationViewed()

        XCTAssertEqual(telemetry.confirmationShownCalledCount, 1)
    }

    // MARK: - Private Helpers

    private func createSubject() -> MicrosurveyViewModel {
        let subject = MicrosurveyViewModel(
            model: MicrosurveyMock.model,
            windowUUID: .XCTestDefaultUUID,
            telemetry: telemetry,
            closePrompt: { [weak self] windowUUID in self?.closedPromptWindows.append(windowUUID) }
        )
        subject.coordinator = coordinator
        trackForMemoryLeaks(subject)
        return subject
    }
}

@MainActor
final class MockMicrosurveyCoordinatorDelegate: MicrosurveyCoordinatorDelegate {
    var dismissFlowCalled = 0
    var showPrivacyUTMContent: [String?] = []

    func dismissFlow() {
        dismissFlowCalled += 1
    }

    func showPrivacy(with content: String?) {
        showPrivacyUTMContent.append(content)
    }
}
