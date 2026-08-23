// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import XCTest
import Common
import TestKit

@testable import Client

final class RemoteTabsPanelTests: XCTestCase, BusTestUtility {
    private enum Constants {
        static let testUrlString = "https://mozilla.org"
        static let testDeviceId = "testDeviceId"
    }

    private let windowUUID: WindowUUID = .XCTestDefaultUUID
    private var mockBus: MockBrowserEventBus!

    override func setUp() async throws {
        try await super.setUp()
        DependencyHelperMock().bootstrapDependencies()
        setupBus()
    }

    override func tearDown() async throws {
        DependencyHelperMock().reset()
        resetBus()
        try await  super.tearDown()
    }

    /// Refreshing is state on the view model now rather than a round trip through the store; the
    /// transitions themselves are covered in RemoteTabsPanelViewModelTests.
    @MainActor
    func testViewModelStateChange_reachesTheTableViewController() {
        let viewModel = RemoteTabsPanelViewModel(windowUUID: windowUUID, profile: MockProfile())
        let subject = createSubject(viewModel: viewModel)

        viewModel.syncDidBegin()

        XCTAssertEqual(subject.state.refreshState, .syncingTabs)
        XCTAssertEqual(subject.tabsDisplayViewController.state.refreshState, .syncingTabs)
    }

    // MARK: - Actions

    /// Refreshing, opening, closing and flushing all run through the view model and its
    /// TabsPanelService now; nothing about the synced-tabs panel goes through the store.
    func testPanelActions_dispatchNothing() {
        let subject = createSubject()

        subject.tableViewControllerDidPullToRefresh()
        subject.remoteTabsClientAndTabsDataSourceDidSelectURL(
            URL(string: Constants.testUrlString)!,
            visitType: .link
        )
        subject.remoteTabsClientAndTabsDataSourceDidCloseURL(
            deviceId: Constants.testDeviceId,
            url: URL(string: Constants.testUrlString)!
        )
        subject.remoteTabsClientAndTabsDataSourceDidTabCommandsFlush(deviceId: Constants.testDeviceId)

        // Only the tray dismissal from opening a tab reaches the store.
        XCTAssertTrue(mockBus.dispatchedActions.allSatisfy { $0 is TabTrayAction })
    }

    // MARK: - RemotePanelDelegate
    @MainActor
    func testRemotePanelDidRequestToSignIn_forwardsCallsToDelegate() {
        let mockDelegate = MockRemoteTabsPanelDelegate()
        let subject = createSubject()
        subject.remoteTabsDelegate = mockDelegate

        subject.remotePanelDidRequestToSignIn()

        XCTAssertEqual(mockDelegate.presentFirefoxAccountSignInCallCount, 1)
    }

    @MainActor
    func testPresentFxAccountSettings_forwardsCallsToDelegate() {
        let mockDelegate = MockRemoteTabsPanelDelegate()
        let subject = createSubject()
        subject.remoteTabsDelegate = mockDelegate

        subject.presentFxAccountSettings()

        XCTAssertEqual(mockDelegate.presentFxAccountSettingsCallCount, 1)
    }

    // MARK: - RemoteTabsEmptyViewDelegate
    /// Opening a synced tab adds one through TabsPanelService, which dismisses the tray.
    @MainActor
    func testRemotePanelDidRequestToOpenInNewTab_dismissesTheTray() throws {
        let subject = createSubject()

        subject.remotePanelDidRequestToOpenInNewTab(
            URL(string: Constants.testUrlString)!,
            isPrivate: false
        )

        let action = try XCTUnwrap(mockBus.dispatchedActions.last as? TabTrayAction)
        let actionType = try XCTUnwrap(action.actionType as? TabTrayActionType)
        XCTAssertEqual(actionType, TabTrayActionType.dismissTabTray)
    }

    // MARK: - BusTestUtility

    func setupBus() {
        mockBus = MockBrowserEventBus()
        BusTestUtilityHelper.setupBus(with: mockBus)
    }

    func resetBus() {
        BusTestUtilityHelper.resetBus()
    }

    // MARK: - Helpers
    private func createSubject(viewModel: RemoteTabsPanelViewModel? = nil) -> RemoteTabsPanel {
        let subject = RemoteTabsPanel(windowUUID: windowUUID, viewModel: viewModel)
        trackForMemoryLeaks(subject)
        return subject
    }
}
