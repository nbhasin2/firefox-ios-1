// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Redux
import XCTest

@testable import Client

/// Replaces `TabsPanelStateTests` and the panel half of `TabManagerActionHandlerTests`.
@MainActor
final class TabsPanelViewModelTests: XCTestCase, StoreTestUtility {
    var mockStore: MockStore!
    private var profile: MockProfile!
    private var tabManager: MockTabManager!
    private var windowManager: MockWindowManager!

    override func setUp() async throws {
        try await super.setUp()
        profile = MockProfile()
        tabManager = MockTabManager()
        await DependencyHelperMock().bootstrapDependencies(injectedTabManager: tabManager)
        windowManager = MockWindowManager(wrappedManager: WindowManagerImplementation(),
                                          tabManager: tabManager)
        setupStore()
    }

    override func tearDown() async throws {
        profile = nil
        tabManager = nil
        windowManager = nil
        DependencyHelperMock().reset()
        resetStore()
        try await super.tearDown()
    }

    // MARK: - Loading

    func test_didLoad_readsTheTabsForItsPanel() {
        tabManager.normalTabs = [makeTab(), makeTab()]
        let subject = createSubject(panelType: .tabs)

        subject.didLoad()

        XCTAssertEqual(subject.state.tabs.count, 2)
        XCTAssertFalse(subject.state.isPrivateMode)
    }

    func test_didLoad_scrollsToTheSelectedTab() {
        let selected = makeTab()
        tabManager.normalTabs = [makeTab(), selected]
        tabManager.selectedTab = selected
        let subject = createSubject(panelType: .tabs)

        subject.didLoad()

        XCTAssertEqual(subject.state.scrollState?.toIndex, 1)
        XCTAssertEqual(subject.state.scrollState?.withAnimation, false)
    }

    func test_didLoad_publishesTheChange() {
        tabManager.normalTabs = [makeTab()]
        let subject = createSubject(panelType: .tabs)
        var changes = 0
        subject.onChange = { _ in changes += 1 }

        subject.didLoad()

        XCTAssertEqual(changes, 1)
    }

    // MARK: - Commands

    func test_closeTab_removesItAndRefreshes() {
        let tab = makeTab()
        tabManager.normalTabs = [tab, makeTab()]
        let subject = createSubject(panelType: .tabs)
        subject.didLoad()

        subject.closeTab(tab.tabUUID)

        XCTAssertEqual(tabManager.removeTabCalledCount, 1)
    }

    func test_selectTab_selectsItAndDismissesTheTray() throws {
        let tab = makeTab()
        tabManager.normalTabs = [tab]
        tabManager.tabForUUID = tab
        let subject = createSubject(panelType: .tabs)

        subject.selectTab(tab.tabUUID, at: 0)

        XCTAssertEqual(tabManager.lastSelectedTabs.count, 1)
        let action = try XCTUnwrap(mockStore.dispatchedActions.last as? TabTrayAction)
        let actionType = try XCTUnwrap(action.actionType as? TabTrayActionType)
        XCTAssertEqual(actionType, TabTrayActionType.dismissTabTray)
    }

    func test_addNewTab_addsAndDismissesTheTray() throws {
        let subject = createSubject(panelType: .tabs)

        subject.addNewTab(with: nil)

        XCTAssertEqual(tabManager.addTabWasCalled, true)
        XCTAssertTrue(mockStore.dispatchedActions.contains { action in
            (action.actionType as? TabTrayActionType) == .dismissTabTray
        })
    }

    func test_prefetchScreenshot_asksTheTabManagerToRestoreIt() {
        let tab = makeTab()
        tabManager.tabsByUUID = [tab.tabUUID: tab]
        let subject = createSubject(panelType: .tabs)

        subject.prefetchScreenshot(for: tab.tabUUID)

        XCTAssertEqual(tabManager.restoreScreenshotCalls.map { $0.tabUUID }, [tab.tabUUID])
    }

    func test_prefetchScreenshot_withAnUnknownTab_doesNothing() {
        tabManager.tabsByUUID = [:]
        let subject = createSubject(panelType: .tabs)

        subject.prefetchScreenshot(for: "not-a-real-uuid")

        XCTAssertTrue(tabManager.restoreScreenshotCalls.isEmpty)
    }

    // MARK: - Bus

    /// A screenshot landing is browser-level, so it arrives on the bus rather than as a refresh
    /// dispatched by a middleware.
    func test_screenshotTaken_refreshesTheTabs() {
        tabManager.normalTabs = [makeTab()]
        let subject = createSubject(panelType: .tabs)

        mockStore.dispatch(
            ScreenshotAction(windowUUID: .XCTestDefaultUUID,
                             tab: tabManager.normalTabs[0],
                             actionType: ScreenshotActionType.screenshotTaken)
        )

        XCTAssertEqual(subject.state.tabs.count, 1)
    }

    // MARK: - Private Helpers

    private func makeTab() -> Tab {
        let tab = Tab(profile: profile, windowUUID: .XCTestDefaultUUID)
        tab.url = URL(string: "https://mozilla.org")
        return tab
    }

    private func createSubject(panelType: TabTrayPanelType) -> TabsPanelViewModel {
        let subject = TabsPanelViewModel(
            windowUUID: .XCTestDefaultUUID,
            panelType: panelType,
            service: TabsPanelService(windowUUID: .XCTestDefaultUUID,
                                      windowManager: windowManager,
                                      telemetry: TabsPanelTelemetry(gleanWrapper: MockGleanWrapper()),
                                      featureFlagsProvider: MockNimbusFeatureFlags()),
            bus: mockStore
        )
        trackForMemoryLeaks(subject)
        return subject
    }

    // MARK: - StoreTestUtility

    func setupStore() {
        mockStore = MockStore()
        StoreTestUtilityHelper.setupStore(with: mockStore)
    }

    func resetStore() {
        StoreTestUtilityHelper.resetStore()
    }
}
