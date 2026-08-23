// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Redux
import XCTest

@testable import Client

/// Replaces `TabPeekStateTests` and the tab-peek half of `TabManagerActionHandlerTests`.
@MainActor
final class TabPeekViewModelTests: XCTestCase, StoreTestUtility {
    var mockStore: MockStore<AppState>!
    private var profile: MockProfile!
    private var tabManager: MockTabManager!
    private var windowManager: MockWindowManager!
    private var bookmarksHandler: MockBookmarksHandler!

    override func setUp() async throws {
        try await super.setUp()
        profile = MockProfile()
        tabManager = MockTabManager()
        bookmarksHandler = MockBookmarksHandler()
        bookmarksHandler.isBookmarkedResult = false
        await DependencyHelperMock().bootstrapDependencies(injectedTabManager: tabManager)
        windowManager = MockWindowManager(
            wrappedManager: WindowManagerImplementation(),
            tabManager: tabManager
        )
        setupStore()
    }

    override func tearDown() async throws {
        profile = nil
        tabManager = nil
        windowManager = nil
        bookmarksHandler = nil
        DependencyHelperMock().reset()
        resetStore()
        try await super.tearDown()
    }

    // MARK: - Loading

    func test_viewDidLoad_withABookmarkableTab_offersAddToBookmarks() async {
        let tab = makeTab()
        tabManager.tabForUUID = tab
        let subject = createSubject(tabUUID: tab.tabUUID)

        subject.viewDidLoad()
        await waitForLoad(subject)

        XCTAssertTrue(subject.state.showAddToBookmarks)
        XCTAssertFalse(subject.state.showRemoveBookmark)
    }

    func test_viewDidLoad_withoutATab_offersNothingBookmarkRelated() async {
        let tab = makeTab()
        tabManager.tabForUUID = nil
        let subject = createSubject(tabUUID: tab.tabUUID)

        subject.viewDidLoad()
        await waitForLoad(subject)

        XCTAssertFalse(subject.state.showAddToBookmarks)
        XCTAssertFalse(subject.state.showRemoveBookmark)
        XCTAssertFalse(subject.state.showCopyURL)
    }

    func test_viewDidLoad_withAnAlreadyBookmarkedTab_offersRemoveBookmark() async {
        let tab = makeTab()
        tabManager.tabForUUID = tab
        bookmarksHandler.isBookmarkedResult = true
        let subject = createSubject(tabUUID: tab.tabUUID)

        subject.viewDidLoad()
        await waitForLoad(subject)

        XCTAssertTrue(subject.state.showRemoveBookmark)
        XCTAssertFalse(subject.state.showAddToBookmarks)
    }

    func test_viewDidLoad_publishesTheChange() async {
        let tab = makeTab()
        tabManager.tabForUUID = tab
        let subject = createSubject(tabUUID: tab.tabUUID)
        var changes = 0
        subject.onChange = { _ in changes += 1 }

        subject.viewDidLoad()
        await waitForLoad(subject)

        XCTAssertEqual(changes, 1)
    }

    // MARK: - Actions

    func test_copyURL_putsTheCanonicalURLOnThePasteboard() {
        let tab = makeTab()
        tabManager.tabForUUID = tab
        let subject = createSubject(tabUUID: tab.tabUUID)

        subject.copyURL()

        XCTAssertEqual(UIPasteboard.general.url, tab.canonicalURL)
    }

    /// Closing goes through the tab tray's service, which is what makes the panel refresh.
    func test_closeTab_removesTheTab() {
        let tab = makeTab()
        tabManager.tabForUUID = tab
        let service = TabsPanelService(windowUUID: .XCTestDefaultUUID,
                                       windowManager: windowManager,
                                       telemetry: TabsPanelTelemetry(gleanWrapper: MockGleanWrapper()),
                                       featureFlagsProvider: MockNimbusFeatureFlags())
        let subject = createSubject(tabUUID: tab.tabUUID, tabsService: service)
        var notifiedPrivate: Bool?
        service.addObserver(self) { notifiedPrivate = $0 }

        subject.closeTab()

        XCTAssertEqual(notifiedPrivate, false)
    }

    func test_loadingActions_dispatchNothing() async {
        let tab = makeTab()
        tabManager.tabForUUID = tab
        let subject = createSubject(tabUUID: tab.tabUUID)

        subject.viewDidLoad()
        await waitForLoad(subject)
        subject.copyURL()

        XCTAssertTrue(mockStore.dispatchedActions.isEmpty)
    }

    // MARK: - Private Helpers

    private func makeTab() -> Tab {
        let tab = Tab(profile: profile, windowUUID: .XCTestDefaultUUID)
        tab.url = URL(string: "https://mozilla.org")
        return tab
    }

    private func waitForLoad(_ subject: TabPeekViewModel) async {
        for _ in 0..<40 where subject.state.previewAccessibilityLabel.isEmpty
            && !subject.state.showAddToBookmarks && !subject.state.showRemoveBookmark {
            await Task.yield()
        }
    }

    private func createSubject(tabUUID: TabUUID,
                               tabsService: TabsPanelService? = nil) -> TabPeekViewModel {
        let subject = TabPeekViewModel(
            tabUUID: tabUUID,
            windowUUID: .XCTestDefaultUUID,
            profile: profile,
            windowManager: windowManager,
            bookmarksSaver: MockBookmarksSaver(),
            bookmarksHandler: bookmarksHandler,
            tabsService: tabsService
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
