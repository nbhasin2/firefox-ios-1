// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Redux
import XCTest

@testable import Client

/// Replaces `TrackingProtectionStateTests`. The reducer's `navigateTo` / `displayView` flags were
/// consumed immediately by `newState` and never read elsewhere, so those seven reducer tests
/// become delegate assertions.
@MainActor
final class TrackingProtectionViewModelTests: XCTestCase {
    private var delegate: MockTrackingProtectionViewModelDelegate!
    private var mockBus: MockBrowserEventBus!

    override func setUp() async throws {
        try await super.setUp()
        await DependencyHelperMock().bootstrapDependencies()
        delegate = MockTrackingProtectionViewModelDelegate()
        mockBus = MockBrowserEventBus()
    }

    override func tearDown() async throws {
        delegate = nil
        mockBus = nil
        DependencyHelperMock().reset()
        try await super.tearDown()
    }

    // MARK: - Navigation intents

    func test_tappedShowBlockedTrackers_requestsBlockedTrackers() {
        let subject = createSubject()

        subject.tappedShowBlockedTrackers()

        XCTAssertEqual(delegate.requestBlockedTrackersCalled, 1)
    }

    func test_tappedShowTrackingProtectionDetails_requestsDetails() {
        let subject = createSubject()

        subject.tappedShowTrackingProtectionDetails()

        XCTAssertEqual(delegate.requestProtectionDetailsCalled, 1)
    }

    func test_tappedShowClearCookiesAlert_requestsTheAlert() {
        let subject = createSubject()

        subject.tappedShowClearCookiesAlert()

        XCTAssertEqual(delegate.requestClearCookiesAlertCalled, 1)
    }

    func test_tappedShowSettings_requestsSettings() {
        let subject = createSubject()

        subject.tappedShowSettings()

        XCTAssertEqual(delegate.requestSettingsCalled, 1)
    }

    func test_didClearCookiesAndSiteData_requestsDismiss() {
        let subject = createSubject()

        subject.didClearCookiesAndSiteData()

        XCTAssertEqual(delegate.requestDismissCalled, 1)
    }

    // MARK: - Refresh signals

    func test_blockedTrackersAction_forThisWindow_refreshesTheCount() {
        let subject = createSubject()

        dispatch(.blockedTrackersDidChange, windowUUID: .XCTestDefaultUUID)

        XCTAssertEqual(delegate.updateBlockedTrackersCalled, 1)
        XCTAssertNotNil(subject)
    }

    func test_connectionStatusAction_forThisWindow_refreshesTheStatus() {
        let subject = createSubject()

        dispatch(.connectionStatusDidChange, windowUUID: .XCTestDefaultUUID)

        XCTAssertEqual(delegate.updateConnectionStatusCalled, 1)
        XCTAssertNotNil(subject)
    }

    func test_actionForAnotherWindow_isIgnored() {
        let subject = createSubject()
        let otherWindow = WindowUUID(uuidString: "44BA0B7D-097A-484D-8358-91A6E374451D")!

        dispatch(.blockedTrackersDidChange, windowUUID: otherWindow)

        // This is the reducer's windowUUID guard, kept where it still matters.
        XCTAssertEqual(delegate.updateBlockedTrackersCalled, 0)
        XCTAssertNotNil(subject)
    }

    func test_unrelatedBrowserAction_isIgnored() {
        let subject = createSubject()

        dispatch(.showToast, windowUUID: .XCTestDefaultUUID)

        XCTAssertEqual(delegate.updateBlockedTrackersCalled, 0)
        XCTAssertEqual(delegate.updateConnectionStatusCalled, 0)
        XCTAssertNotNil(subject)
    }

    // MARK: - Private Helpers

    private func dispatch(_ actionType: GeneralBrowserActionType, windowUUID: WindowUUID) {
        mockBus.dispatch(GeneralBrowserAction(windowUUID: windowUUID, actionType: actionType))
    }

    private func createSubject() -> TrackingProtectionViewModel {
        let subject = TrackingProtectionViewModel(
            windowUUID: .XCTestDefaultUUID,
            bus: mockBus
        )
        subject.delegate = delegate
        trackForMemoryLeaks(subject)
        return subject
    }
}

@MainActor
final class MockTrackingProtectionViewModelDelegate: TrackingProtectionViewModelDelegate {
    var requestBlockedTrackersCalled = 0
    var requestProtectionDetailsCalled = 0
    var requestClearCookiesAlertCalled = 0
    var requestSettingsCalled = 0
    var requestDismissCalled = 0
    var updateBlockedTrackersCalled = 0
    var updateConnectionStatusCalled = 0

    func trackingProtectionViewModelDidRequestBlockedTrackers() { requestBlockedTrackersCalled += 1 }
    func trackingProtectionViewModelDidRequestProtectionDetails() { requestProtectionDetailsCalled += 1 }
    func trackingProtectionViewModelDidRequestClearCookiesAlert() { requestClearCookiesAlertCalled += 1 }
    func trackingProtectionViewModelDidRequestSettings() { requestSettingsCalled += 1 }
    func trackingProtectionViewModelDidRequestDismiss() { requestDismissCalled += 1 }
    func trackingProtectionViewModelDidUpdateBlockedTrackers() { updateBlockedTrackersCalled += 1 }
    func trackingProtectionViewModelDidUpdateConnectionStatus() { updateConnectionStatusCalled += 1 }
}
