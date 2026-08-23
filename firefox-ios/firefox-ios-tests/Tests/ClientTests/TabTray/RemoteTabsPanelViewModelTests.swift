// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Redux
import Shared
import XCTest

import struct Storage.ClientAndTabs

@testable import Client

/// Replaces `RemoteTabPanelStateTests` and `DefaultSyncedTabProviderTests`' sync-state half.
@MainActor
final class RemoteTabsPanelViewModelTests: XCTestCase, StoreTestUtility {
    var mockStore: MockStore<AppState>!
    private var profile: MockProfile!
    private var notificationCenter: MockNotificationCenter!

    override func setUp() async throws {
        try await super.setUp()
        await DependencyHelperMock().bootstrapDependencies()
        profile = MockProfile()
        notificationCenter = MockNotificationCenter()
        setupStore()
    }

    override func tearDown() async throws {
        profile = nil
        notificationCenter = nil
        DependencyHelperMock().reset()
        resetStore()
        try await super.tearDown()
    }

    // MARK: - Initial state

    func test_initialState_showsNoTabs() {
        let subject = createSubject()

        XCTAssertEqual(subject.state.refreshState, .idle)
        XCTAssertEqual(subject.state.showingEmptyState, .noTabs)
        XCTAssertTrue(subject.state.clientAndTabs.isEmpty)
    }

    // MARK: - Refresh

    func test_refresh_withoutASyncableAccount_failsWithNotLoggedIn() {
        profile.hasSyncableAccountMock = false
        let subject = createSubject()

        subject.refresh()

        XCTAssertEqual(subject.state.showingEmptyState, .notLoggedIn)
        XCTAssertEqual(subject.state.refreshState, .idle)
        // notLoggedIn is one of the two reasons that does not allow a retry.
        XCTAssertFalse(subject.state.allowsRefresh)
    }

    func test_refresh_withSyncDisabled_failsWithSyncDisabled() {
        profile.hasSyncableAccountMock = true
        profile.prefs.setBool(false, forKey: PrefsKeys.TabSyncEnabled)
        let subject = createSubject()

        subject.refresh()

        XCTAssertEqual(subject.state.showingEmptyState, .syncDisabledByUser)
        XCTAssertFalse(subject.state.allowsRefresh)
    }

    /// Pull-to-refresh must not start a second fetch while one is in flight.
    func test_refresh_whileAlreadyRefreshing_isIgnored() {
        profile.hasSyncableAccountMock = true
        profile.prefs.setBool(true, forKey: PrefsKeys.TabSyncEnabled)
        let subject = createSubject(refreshState: .refreshing)
        var changes = 0
        subject.onChange = { _ in changes += 1 }

        subject.refresh()

        XCTAssertEqual(subject.state.refreshState, .refreshing)
        XCTAssertEqual(changes, 0)
    }

    func test_refresh_withASyncableAccount_endsIdleWithTheClients() {
        profile.hasSyncableAccountMock = true
        profile.prefs.setBool(true, forKey: PrefsKeys.TabSyncEnabled)
        let subject = createSubject()

        subject.refresh()

        XCTAssertEqual(subject.state.refreshState, .idle)
        XCTAssertTrue(subject.state.allowsRefresh)
        XCTAssertNil(subject.state.showingEmptyState)
    }

    func test_refresh_publishesTheChange() {
        profile.hasSyncableAccountMock = false
        let subject = createSubject()
        var published: RemoteTabsPanelState?
        subject.onChange = { published = $0 }

        subject.refresh()

        XCTAssertEqual(published?.showingEmptyState, .notLoggedIn)
    }

    // MARK: - Sync

    func test_syncDidBegin_fromIdle_entersSyncingAndBlocksRefresh() {
        let subject = createSubject()

        subject.syncDidBegin()

        XCTAssertEqual(subject.state.refreshState, .syncingTabs)
        XCTAssertFalse(subject.state.allowsRefresh)
    }

    func test_syncDidBegin_whileRefreshing_isIgnored() {
        let subject = createSubject(refreshState: .refreshing)

        subject.syncDidBegin()

        XCTAssertEqual(subject.state.refreshState, .refreshing)
    }

    // MARK: - Account announcement

    /// Leaves the screen: `TabTrayState` reduces it and the tab tray has not migrated.
    func test_panelDidAppear_announcesTheAccountState() throws {
        profile.hasSyncableAccountMock = false
        let subject = createSubject()

        subject.panelDidAppear()

        let actionCalled = try XCTUnwrap(
            mockStore.dispatchedActions.last(where: { $0 is TabTrayAction }) as? TabTrayAction
        )
        let actionType = try XCTUnwrap(actionCalled.actionType as? TabTrayActionType)
        XCTAssertEqual(actionType, TabTrayActionType.firefoxAccountChanged)
        XCTAssertEqual(actionCalled.hasSyncableAccount, false)
    }

    // MARK: - Private Helpers

    private func createSubject(
        refreshState: RemoteTabsPanelRefreshState? = nil
    ) -> RemoteTabsPanelViewModel {
        let initialState = refreshState.map {
            RemoteTabsPanelState(windowUUID: .XCTestDefaultUUID,
                                 refreshState: $0,
                                 allowsRefresh: false,
                                 clientAndTabs: [],
                                 showingEmptyState: nil,
                                 devices: [])
        }
        let subject = RemoteTabsPanelViewModel(
            windowUUID: .XCTestDefaultUUID,
            profile: profile,
            notificationCenter: notificationCenter,
            initialState: initialState
        )
        trackForMemoryLeaks(subject)
        return subject
    }

    // MARK: - StoreTestUtility

    func setupAppState() -> AppState {
        return AppState()
    }

    func setupStore() {
        mockStore = MockStore(state: setupAppState())
        StoreTestUtilityHelper.setupStore(with: mockStore)
    }

    func resetStore() {
        StoreTestUtilityHelper.resetStore()
    }
}
