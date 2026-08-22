// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import XCTest
import Common
import TestKit

@testable import Client

final class RemoteTabsPanelTests: XCTestCase, StoreTestUtility {
    private enum Constants {
        static let testUrlString = "https://mozilla.org"
        static let testDeviceId = "testDeviceId"
    }

    private let windowUUID: WindowUUID = .XCTestDefaultUUID
    private var mockStore: MockStoreForMiddleware<AppState>!

    override func setUp() async throws {
        try await super.setUp()
        DependencyHelperMock().bootstrapDependencies()
        setupStore()
    }

    override func tearDown() async throws {
        DependencyHelperMock().reset()
        resetStore()
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
    func testTableViewControllerDidPullToRefresh_dispatchesNothing() {
        let subject = createSubject()

        subject.tableViewControllerDidPullToRefresh()

        XCTAssertFalse(mockStore.dispatchedActions.contains { $0 is RemoteTabsPanelAction })
    }

    // MARK: - RemoteTabsClientAndTabsDataSourceDelegate
    @MainActor
    func testRemoteTabsClientAndTabsDataSourceDidSelectURL_dispatchesCloseSelectedRemoteURLAction() throws {
        let subject = createSubject()
        subject.remoteTabsClientAndTabsDataSourceDidSelectURL(
            URL(string: Constants.testUrlString)!,
            visitType: .link
        )

        let action = try XCTUnwrap(mockStore.dispatchedActions.last)
        let actionType = try XCTUnwrap(action.actionType as? RemoteTabsPanelActionType)

        XCTAssertEqual(actionType, RemoteTabsPanelActionType.openSelectedURL)
    }

    func testRemoteTabsClientAndTabsDataSourceDidCloseURL_dispatchesCloseSelectedRemoteURL() throws {
        let subject = createSubject()
        subject.remoteTabsClientAndTabsDataSourceDidCloseURL(
            deviceId: Constants.testDeviceId,
            url: URL(string: Constants.testUrlString)!
        )

        let action = try XCTUnwrap(mockStore.dispatchedActions.first)
        let actionType = try XCTUnwrap(action.actionType as? RemoteTabsPanelActionType)

        XCTAssertEqual(actionType, RemoteTabsPanelActionType.closeSelectedRemoteURL)
    }

    func testRemoteTabsClientAndTabsDataSourceDidTabCommandsFlush_dispatchesFlushTabCommands() throws {
        let subject = createSubject()
        subject.remoteTabsClientAndTabsDataSourceDidTabCommandsFlush(deviceId: Constants.testDeviceId)

        let action = try XCTUnwrap(mockStore.dispatchedActions.first)
        let actionType = try XCTUnwrap(action.actionType as? RemoteTabsPanelActionType)

        XCTAssertEqual(actionType, RemoteTabsPanelActionType.flushTabCommands)
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
    @MainActor
    func testRemotePanelDidRequestToOpenInNewTab_dispatchesCloseSelectedRemoteURLAction() throws {
        let subject = createSubject()
        subject.remotePanelDidRequestToOpenInNewTab(
            URL(string: Constants.testUrlString)!,
            isPrivate: false
        )

        let action = try XCTUnwrap(mockStore.dispatchedActions.last)
        let actionType = try XCTUnwrap(action.actionType as? RemoteTabsPanelActionType)

        XCTAssertEqual(actionType, RemoteTabsPanelActionType.openSelectedURL)
    }

    // MARK: - StoreTestUtility
    func setupAppState() -> Client.AppState {
        return AppState()
    }

    func setupStore() {
        mockStore = MockStoreForMiddleware(state: setupAppState())
        StoreTestUtilityHelper.setupStore(with: mockStore)
    }

    func resetStore() {
        StoreTestUtilityHelper.resetStore()
    }

    // MARK: - Helpers
    private func createSubject(viewModel: RemoteTabsPanelViewModel? = nil) -> RemoteTabsPanel {
        let subject = RemoteTabsPanel(windowUUID: windowUUID, viewModel: viewModel)
        trackForMemoryLeaks(subject)
        return subject
    }
}
