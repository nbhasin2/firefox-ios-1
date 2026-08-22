// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Shared
import XCTest

@testable import Client

/// Replaces `TermsOfUseMiddlewareTests` and `TermsOfUseStateTests`. The prefs writes and telemetry
/// are unchanged; only the way they are invoked is. The state's two booleans are gone — nothing
/// read them except a `newState` that called the coordinator, which the view controller already
/// did directly.
@MainActor
final class TermsOfUseViewModelTests: XCTestCase {
    private var profile: MockProfile!
    private var gleanWrapper: MockGleanWrapper!

    override func setUp() async throws {
        try await super.setUp()
        await DependencyHelperMock().bootstrapDependencies()
        profile = MockProfile()
        gleanWrapper = MockGleanWrapper()
    }

    override func tearDown() async throws {
        profile = nil
        gleanWrapper = nil
        DependencyHelperMock().reset()
        try await super.tearDown()
    }

    // MARK: - Impression

    func test_termsShown_firstTime_marksShownAndRecords() {
        let subject = createSubject()

        subject.termsShown()

        XCTAssertEqual(profile.prefs.boolForKey(PrefsKeys.TermsOfUseFirstShown), true)
        XCTAssertEqual(profile.prefs.boolForKey(PrefsKeys.TermsOfUseShownRecorded), true)
        XCTAssertEqual(gleanWrapper.recordEventCalled, 1)
    }

    func test_termsShown_secondTimeWithoutDismissal_recordsNothing() {
        profile.prefs.setBool(true, forKey: PrefsKeys.TermsOfUseFirstShown)
        profile.prefs.setBool(true, forKey: PrefsKeys.TermsOfUseShownRecorded)
        let subject = createSubject()

        subject.termsShown()

        XCTAssertEqual(gleanWrapper.recordEventCalled, 0)
    }

    func test_termsShown_afterDismissal_recordsAgain() {
        profile.prefs.setBool(true, forKey: PrefsKeys.TermsOfUseFirstShown)
        profile.prefs.setBool(false, forKey: PrefsKeys.TermsOfUseShownRecorded)
        profile.prefs.setTimestamp(Date.now(), forKey: PrefsKeys.TermsOfUseDismissedDate)
        let subject = createSubject()

        subject.termsShown()

        XCTAssertEqual(profile.prefs.boolForKey(PrefsKeys.TermsOfUseShownRecorded), true)
        XCTAssertEqual(gleanWrapper.recordEventCalled, 1)
    }

    // MARK: - Acceptance

    func test_termsAccepted_storesAcceptanceAndDate() {
        let subject = createSubject()

        subject.termsAccepted()

        XCTAssertEqual(profile.prefs.boolForKey(PrefsKeys.TermsOfUseAccepted), true)
        XCTAssertNotNil(profile.prefs.timestampForKey(PrefsKeys.TermsOfUseAcceptedDate))
        XCTAssertEqual(gleanWrapper.recordEventCalled, 1)
    }

    // MARK: - Dismissal

    func test_gestureDismiss_clearsShownRecordedAndStampsDismissedDate() {
        let subject = createSubject()

        subject.gestureDismiss()

        XCTAssertEqual(profile.prefs.boolForKey(PrefsKeys.TermsOfUseShownRecorded), false)
        XCTAssertNotNil(profile.prefs.timestampForKey(PrefsKeys.TermsOfUseDismissedDate))
    }

    func test_remindMeLaterTapped_alsoStampsTheRemindDate() {
        let subject = createSubject()

        subject.remindMeLaterTapped()

        XCTAssertEqual(profile.prefs.boolForKey(PrefsKeys.TermsOfUseShownRecorded), false)
        XCTAssertNotNil(profile.prefs.timestampForKey(PrefsKeys.TermsOfUseDismissedDate))
        XCTAssertNotNil(profile.prefs.timestampForKey(PrefsKeys.TermsOfUseRemindMeLaterTapDate))
    }

    func test_firstDismissal_doesNotIncrementRemindersCount() {
        let subject = createSubject()

        subject.gestureDismiss()

        // The count is for reminders, so it only starts after the first dismissal.
        XCTAssertNil(profile.prefs.intForKey(PrefsKeys.TermsOfUseRemindersCount))
    }

    func test_secondDismissal_incrementsRemindersCount() {
        profile.prefs.setTimestamp(Date.now(), forKey: PrefsKeys.TermsOfUseDismissedDate)
        let subject = createSubject()

        subject.gestureDismiss()

        XCTAssertEqual(profile.prefs.intForKey(PrefsKeys.TermsOfUseRemindersCount), 1)
    }

    // MARK: - Links

    func test_linkTapped_terms_stampsTermsDate() {
        let subject = createSubject()

        subject.linkTapped(.termsOfUse)

        XCTAssertNotNil(profile.prefs.timestampForKey(PrefsKeys.TermsOfUseTermsLinkTapDate))
        XCTAssertEqual(gleanWrapper.recordEventCalled, 1)
    }

    func test_linkTapped_privacyNotice_stampsPrivacyDate() {
        let subject = createSubject()

        subject.linkTapped(.privacyNotice)

        XCTAssertNotNil(profile.prefs.timestampForKey(PrefsKeys.TermsOfUsePrivacyNoticeTapDate))
        XCTAssertEqual(gleanWrapper.recordEventCalled, 1)
    }

    func test_linkTapped_learnMore_stampsLearnMoreDate() {
        let subject = createSubject()

        subject.linkTapped(.learnMore)

        XCTAssertNotNil(profile.prefs.timestampForKey(PrefsKeys.TermsOfUseLearnMoreTapDate))
        XCTAssertEqual(gleanWrapper.recordEventCalled, 1)
    }

    func test_linkTapped_here_isTreatedAsLearnMore() {
        let subject = createSubject()

        subject.linkTapped(.here)

        // `.here` shared the learn-more URL and action type before the migration.
        XCTAssertNotNil(profile.prefs.timestampForKey(PrefsKeys.TermsOfUseLearnMoreTapDate))
        XCTAssertNil(profile.prefs.timestampForKey(PrefsKeys.TermsOfUsePrivacyNoticeTapDate))
    }

    // MARK: - Private Helpers

    private func createSubject() -> TermsOfUseViewModel {
        let subject = TermsOfUseViewModel(
            profile: profile,
            telemetry: TermsOfUseTelemetry(gleanWrapper: gleanWrapper)
        )
        trackForMemoryLeaks(subject)
        return subject
    }
}
