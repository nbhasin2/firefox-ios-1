// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Redux
import XCTest

@testable import Client

final class TabManagerActionHandlerTests: XCTestCase, StoreTestUtility {
    private var mockProfile: MockProfile!
    private var mockWindowManager: MockWindowManager!
    private var mockStore: MockStore!
    private var mockTabManager: MockTabManager!
    private var summarizerConfigFactory: MockSummarizerConfigFactory!
    private let homepageURLString = "internal://local/about/home"

    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        DependencyHelperMock().bootstrapDependencies()
        setIsHostedSummaryEnabled(false)
        mockProfile = MockProfile()
        summarizerConfigFactory = MockSummarizerConfigFactory()
        mockTabManager = MockTabManager()
        mockTabManager.recentlyAccessedNormalTabs = [createTab(profile: mockProfile)]
        mockWindowManager = MockWindowManager(
            wrappedManager: WindowManagerImplementation(),
            tabManager: mockTabManager
        )
        DependencyHelperMock().bootstrapDependencies(injectedWindowManager: mockWindowManager)
        setupStore()
    }

    override func tearDown() async throws {
        mockProfile = nil
        mockWindowManager = nil
        mockTabManager = nil
        summarizerConfigFactory = nil
        DependencyHelperMock().reset()
        resetStore()
        try await super.tearDown()
    }

    /// The middleware writes the screenshot to disk; the tray's refresh moved onto the bus, so
    /// see TabsPanelViewModelTests for that half.
    func test_screenshotTakenAction_savesTheScreenshot() {
        let subject = createSubject()
        let action = ScreenshotAction(
            windowUUID: .XCTestDefaultUUID,
            tab: Tab(profile: mockProfile, windowUUID: .XCTestDefaultUUID),
            actionType: ScreenshotActionType.screenshotTaken
        )
        mockWindowManager.overrideWindows = true

        subject.handle(action)

        XCTAssertEqual(mockTabManager.tabDidSetScreenshotCalls, 1)
    }

    func test_screenshotAction_returnsEarlyIfTabManagerDoesNotExistForWindow() {
        let subject = createSubject()
        let action = ScreenshotAction(
            windowUUID: .XCTestDefaultUUID,
            tab: Tab(profile: mockProfile, windowUUID: .XCTestDefaultUUID),
            actionType: ScreenshotActionType.screenshotTaken
        )

        subject.handle(action)

        XCTAssertTrue(mockWindowManager.windowsWereAccessed)
        XCTAssertEqual(mockTabManager.tabDidSetScreenshotCalls, 0)
    }

    func test_screenshotRestoredAction_doesNotWriteBackToDisk() {
        let subject = createSubject()
        let action = ScreenshotAction(
            windowUUID: .XCTestDefaultUUID,
            tab: Tab(profile: mockProfile, windowUUID: .XCTestDefaultUUID),
            actionType: ScreenshotActionType.screenshotRestored
        )
        mockWindowManager.overrideWindows = true

        subject.handle(action)

        XCTAssertEqual(
            mockTabManager.tabDidSetScreenshotCalls,
            0,
            "screenshotRestored should not write the loaded image back to disk."
        )
    }

    // The two prefetch tests moved with the action: prefetching is a TabsPanelService call from
    // the display view now - see TabsPanelViewModelTests.

    // MARK: - Recent Tabs
    // The seven recent-tabs tests that were here drove the middleware's homepage half through
    // seven different actions and asserted the same fetch each time. The fetch moved to
    // DefaultRecentTabsProvider and the triggers to JumpBackInSectionViewModel, which observes
    // the browser-level ones off the bus - see JumpBackInSectionViewModelTests.

    func test_tapOnCell_fromJumpBackInAction_selectsCorrectTabs() {
        let subject = createSubject()
        let action = JumpBackInAction(
            tab: createTab(profile: mockProfile),
            windowUUID: .XCTestDefaultUUID,
            actionType: JumpBackInActionType.tapOnCell
        )

        let expectation = XCTestExpectation(description: "Recent tabs should be returned")

        let mockTabManager = mockWindowManager.tabManager(for: .XCTestDefaultUUID) as? MockTabManager
        mockTabManager?.selectTabExpectation = expectation

        subject.handle(action)

        wait(for: [expectation])

        let selectedTab = mockWindowManager.tabManager(for: .XCTestDefaultUUID)!.selectedTab
        XCTAssertEqual(selectedTab?.displayTitle, "www.mozilla.org")
        XCTAssertEqual(selectedTab?.url?.absoluteString, "www.mozilla.org")
    }

    func test_shortcutsLibraryAction_switchTabToastButtonPressed_selectsTab() throws {
        let subject = createSubject()
        let tab = Tab(profile: mockProfile, windowUUID: .XCTestDefaultUUID)
        let action = ShortcutsLibraryAction(
            tab: tab,
            windowUUID: .XCTestDefaultUUID,
            actionType: ShortcutsLibraryActionType.switchTabToastButtonTapped
        )

        subject.handle(action)
        let selectedTab = mockWindowManager.tabManager(for: .XCTestDefaultUUID)!.selectedTab

        XCTAssertEqual(selectedTab, tab)
    }

    func test_shortcutsLibraryAction_withNonSwitchTabActionType_doesNotSelectTab() throws {
        let subject = createSubject()
        let tab = Tab(profile: mockProfile, windowUUID: .XCTestDefaultUUID)
        let action = ShortcutsLibraryAction(
            tab: tab,
            windowUUID: .XCTestDefaultUUID,
            // switchTabToastButtonTapped is the only case left, so any other action type has to
            // come from a different family.
            actionType: TabPanelViewActionType.addNewTab
        )

        subject.handle(action)
        let selectedTab = mockWindowManager.tabManager(for: .XCTestDefaultUUID)!.selectedTab

        XCTAssertNotEqual(selectedTab, tab)
    }

    // The eight tab-peek tests that were here drove the middleware's load path. That path is
    // TabPeekViewModel now - see TabPeekViewModelTests. Only closeTab still reaches the
    // middleware, because it needs the tabs panel's private-mode flag.

    // MARK: - Helpers
    private func createSubject() -> TabManagerActionHandler {
        return TabManagerActionHandler(
            profile: mockProfile,
            windowManager: mockWindowManager,
            summarizerConfigFactory: summarizerConfigFactory
        )
    }

    private func createTab(
        profile: MockProfile,
        urlString: String? = "www.mozilla.org"
    ) -> Tab {
        let tab = Tab(profile: profile, windowUUID: .XCTestDefaultUUID)

        if let urlString = urlString, !urlString.isEmpty {
            tab.url = URL(string: urlString)!
        }
        return tab
    }

    private func setIsHostedSummaryEnabled(_ isEnabled: Bool) {
        return FxNimbus.shared.features.hostedSummarizerFeature.with { _, _ in
            return HostedSummarizerFeature(enabled: isEnabled)
        }
    }

    // MARK: StoreTestUtility

    func setupStore() {
        mockStore = MockStore()
        StoreTestUtilityHelper.setupStore(with: mockStore)
    }

    func resetStore() {
        StoreTestUtilityHelper.resetStore()
    }
}
