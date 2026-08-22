// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import XCTest

@testable import Client

/// Replaces `TrackingProtectionStateTests`. The reducer's `navigateTo` / `displayView` flags were
/// consumed immediately by `newState` and never read elsewhere, so those seven reducer tests
/// become delegate assertions.
@MainActor
final class TrackingProtectionViewModelTests: XCTestCase {
    private var delegate: MockTrackingProtectionViewModelDelegate!
    private var notificationCenter: MockNotificationCenter!

    override func setUp() async throws {
        try await super.setUp()
        await DependencyHelperMock().bootstrapDependencies()
        delegate = MockTrackingProtectionViewModelDelegate()
        notificationCenter = MockNotificationCenter()
    }

    override func tearDown() async throws {
        delegate = nil
        notificationCenter = nil
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

    func test_blockedTrackersNotification_forThisWindow_refreshesTheCount() async {
        let subject = createSubject()

        post(.trackingProtectionBlockedTrackersDidChange, windowUUID: .XCTestDefaultUUID, to: subject)
        await Task.yield()

        XCTAssertEqual(delegate.updateBlockedTrackersCalled, 1)
    }

    func test_connectionStatusNotification_forThisWindow_refreshesTheStatus() async {
        let subject = createSubject()

        post(.trackingProtectionConnectionStatusDidChange, windowUUID: .XCTestDefaultUUID, to: subject)
        await Task.yield()

        XCTAssertEqual(delegate.updateConnectionStatusCalled, 1)
    }

    func test_notificationForAnotherWindow_isIgnored() async {
        let subject = createSubject()
        let otherWindow = WindowUUID(uuidString: "44BA0B7D-097A-484D-8358-91A6E374451D")!

        post(.trackingProtectionBlockedTrackersDidChange, windowUUID: otherWindow, to: subject)
        await Task.yield()

        // This is the reducer's windowUUID guard, kept where it still matters.
        XCTAssertEqual(delegate.updateBlockedTrackersCalled, 0)
    }

    func test_notificationWithoutAWindowUUID_isIgnored() async {
        let subject = createSubject()

        subject.handleNotifications(
            Notification(name: .trackingProtectionBlockedTrackersDidChange, object: nil, userInfo: nil)
        )
        await Task.yield()

        XCTAssertEqual(delegate.updateBlockedTrackersCalled, 0)
    }

    // MARK: - Private Helpers

    private func post(_ name: Notification.Name, windowUUID: WindowUUID, to subject: TrackingProtectionViewModel) {
        subject.handleNotifications(
            Notification(
                name: name,
                object: nil,
                userInfo: [TrackingProtectionNotification.windowUUIDKey: windowUUID]
            )
        )
    }

    private func createSubject() -> TrackingProtectionViewModel {
        let subject = TrackingProtectionViewModel(
            windowUUID: .XCTestDefaultUUID,
            notificationCenter: notificationCenter
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
