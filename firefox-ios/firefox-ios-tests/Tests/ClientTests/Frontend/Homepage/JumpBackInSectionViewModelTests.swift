// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Redux
import Storage
import XCTest

@testable import Client

/// Replaces `JumpBackInSectionStateTests` and the jump-back-in halves of
/// `TabManagerMiddlewareTests` and `RemoteTabsMiddlewareTests`.
@MainActor
final class JumpBackInSectionViewModelTests: XCTestCase, StoreTestUtility {
    var mockStore: MockStoreForMiddleware<AppState>!
    private var recentTabsProvider: MockRecentTabsProvider!
    private var syncedTabProvider: MockSyncedTabProvider!

    override func setUp() async throws {
        try await super.setUp()
        await DependencyHelperMock().bootstrapDependencies()
        recentTabsProvider = MockRecentTabsProvider()
        syncedTabProvider = MockSyncedTabProvider()
        setupStore()
    }

    override func tearDown() async throws {
        recentTabsProvider = nil
        syncedTabProvider = nil
        DependencyHelperMock().reset()
        resetStore()
        try await super.tearDown()
    }

    // MARK: - Local tabs

    func test_refreshLocalTabs_mapsTheRecentTabs() {
        recentTabsProvider.tabs = [makeTab(url: "https://mozilla.org", title: "Mozilla")]
        let subject = createSubject()

        subject.refreshLocalTabs()

        XCTAssertEqual(subject.state.jumpBackInTabs.count, 1)
        XCTAssertEqual(subject.state.jumpBackInTabs.first?.titleText, "Mozilla")
    }

    func test_refreshLocalTabs_asksForThisWindowsTabs() {
        let subject = createSubject()

        subject.refreshLocalTabs()

        XCTAssertEqual(recentTabsProvider.requestedWindowUUIDs, [.XCTestDefaultUUID])
    }

    func test_refreshLocalTabs_publishesTheChange() {
        recentTabsProvider.tabs = [makeTab(url: "https://mozilla.org", title: "Mozilla")]
        let subject = createSubject()
        var changes = 0
        subject.onChange = { changes += 1 }

        subject.refreshLocalTabs()

        XCTAssertEqual(changes, 1)
    }

    // MARK: - Synced tab

    func test_refreshSyncedTab_mapsTheMostRecentTab() async {
        syncedTabProvider.remoteTab = makeRemoteTab()
        let subject = createSubject()

        subject.refreshSyncedTab()
        await waitForSyncedTab(subject)

        XCTAssertEqual(subject.state.mostRecentSyncedTab?.titleText, "Remote Title")
        XCTAssertEqual(subject.state.mostRecentSyncedTab?.descriptionText, "Desktop Client")
    }

    func test_refreshSyncedTab_withoutATab_leavesTheStateAlone() async {
        syncedTabProvider.remoteTab = nil
        let subject = createSubject()

        subject.refreshSyncedTab()
        for _ in 0..<20 { await Task.yield() }

        XCTAssertNil(subject.state.mostRecentSyncedTab)
    }

    // MARK: - Bus

    /// These arrive as dispatched actions because closing a tab or dismissing the tab tray is a
    /// browser-level event with no ownership path to the homepage (D-016).
    func test_dismissTabTray_refreshesTheLocalTabs() {
        recentTabsProvider.tabs = [makeTab(url: "https://mozilla.org", title: "Mozilla")]
        let subject = createSubject()

        mockStore.dispatch(
            TabTrayAction(windowUUID: .XCTestDefaultUUID, actionType: TabTrayActionType.dismissTabTray)
        )

        XCTAssertEqual(subject.state.jumpBackInTabs.count, 1)
    }

    func test_didTapCloseTab_refreshesTheLocalTabs() {
        recentTabsProvider.tabs = [makeTab(url: "https://mozilla.org", title: "Mozilla")]
        let subject = createSubject()

        mockStore.dispatch(
            TopTabsAction(windowUUID: .XCTestDefaultUUID, actionType: TopTabsActionType.didTapCloseTab)
        )

        XCTAssertEqual(subject.state.jumpBackInTabs.count, 1)
    }

    func test_actionForAnotherWindow_isIgnored() {
        recentTabsProvider.tabs = [makeTab(url: "https://mozilla.org", title: "Mozilla")]
        let subject = createSubject()
        let otherWindow = WindowUUID(uuidString: "44BA0B7D-097A-484D-8358-91A6E374451D")!

        mockStore.dispatch(
            TabTrayAction(windowUUID: otherWindow, actionType: TabTrayActionType.dismissTabTray)
        )

        XCTAssertTrue(subject.state.jumpBackInTabs.isEmpty)
    }

    // MARK: - Section setting

    func test_setSectionEnabled_false_hidesTheSection() {
        let subject = createSubject()

        subject.setSectionEnabled(false)

        XCTAssertFalse(subject.state.shouldShowSection)
    }

    // MARK: - Private Helpers

    private func makeTab(url: String, title: String) -> Tab {
        let tab = MockTab(profile: MockProfile(), windowUUID: .XCTestDefaultUUID)
        tab.url = URL(string: url)
        tab.lastTitle = title
        return tab
    }

    private func makeRemoteTab() -> RemoteTabConfiguration {
        let client = RemoteClient(guid: "guid",
                                  name: "Desktop Client",
                                  modified: 0,
                                  type: "desktop",
                                  formfactor: nil,
                                  os: nil,
                                  version: nil,
                                  fxaDeviceId: nil)
        let tab = RemoteTab(clientGUID: "guid",
                            URL: URL(string: "https://mozilla.org")!,
                            title: "Remote Title",
                            history: [],
                            lastUsed: 0,
                            icon: nil)
        return RemoteTabConfiguration(client: client, tab: tab)
    }

    private func waitForSyncedTab(_ subject: JumpBackInSectionViewModel) async {
        for _ in 0..<40 where subject.state.mostRecentSyncedTab == nil {
            await Task.yield()
        }
    }

    private func createSubject() -> JumpBackInSectionViewModel {
        let subject = JumpBackInSectionViewModel(
            windowUUID: .XCTestDefaultUUID,
            recentTabsProvider: recentTabsProvider,
            syncedTabProvider: syncedTabProvider,
            bus: mockStore,
            initialState: JumpBackInSectionState(
                jumpBackInTabs: [],
                mostRecentSyncedTab: nil,
                shouldShowSection: true
            )
        )
        trackForMemoryLeaks(subject)
        return subject
    }

    // MARK: - StoreTestUtility

    func setupAppState() -> AppState {
        return AppState()
    }

    func setupStore() {
        mockStore = MockStoreForMiddleware(state: setupAppState())
        StoreTestUtilityHelper.setupStore(with: mockStore)
    }

    func resetStore() {
        StoreTestUtilityHelper.resetStore()
    }
}

@MainActor
final class MockRecentTabsProvider: RecentTabsProviding {
    var tabs: [Tab] = []
    private(set) var requestedWindowUUIDs: [WindowUUID] = []

    func recentTabs(for windowUUID: WindowUUID) -> [Tab] {
        requestedWindowUUIDs.append(windowUUID)
        return tabs
    }
}

@MainActor
final class MockSyncedTabProvider: SyncedTabProviding {
    var remoteTab: RemoteTabConfiguration?

    func mostRecentSyncedTab() async -> RemoteTabConfiguration? {
        return remoteTab
    }
}
