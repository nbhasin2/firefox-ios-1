// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import MenuKit
import Storage
import UIKit
import XCTest

@testable import Client

/// Replaces `MainMenuStateTests` and `MainMenuMiddlewareTests`, plus the tab-info assembly tests
/// that lived in `TabManagerActionHandlerTests` before that code moved to `MainMenuTabInfoProvider`.
@MainActor
final class MainMenuViewModelTests: XCTestCase {
    private var provider: MockMainMenuTabInfoProvider!
    private var delegate: MockMainMenuViewModelDelegate!
    private var gleanWrapper: MockGleanWrapper!

    override func setUp() async throws {
        try await super.setUp()
        await DependencyHelperMock().bootstrapDependencies()
        provider = MockMainMenuTabInfoProvider()
        delegate = MockMainMenuViewModelDelegate()
        gleanWrapper = MockGleanWrapper()
    }

    override func tearDown() async throws {
        provider = nil
        delegate = nil
        gleanWrapper = nil
        DependencyHelperMock().reset()
        try await super.tearDown()
    }

    // MARK: - Loading

    func test_viewDidLoad_readsBrowserDefaultAndOrientation() {
        let subject = createSubject(isBrowserDefault: true, isPhoneLandscape: true)

        subject.viewDidLoad()

        XCTAssertTrue(subject.state.isBrowserDefault)
        XCTAssertTrue(subject.state.isPhoneLandscape)
    }

    func test_viewDidLoad_appliesTabInfo() async {
        provider.tabInfoToReturn = makeTabInfo()
        let subject = createSubject()

        subject.viewDidLoad()
        await waitForTabInfo(subject)

        XCTAssertEqual(subject.state.currentTabInfo?.tabID, "tab-1")
        XCTAssertEqual(subject.state.accountData?.title, "Signed out")
    }

    func test_viewDidLoad_appliesSiteProtections() {
        provider.siteProtectionsToReturn = SiteProtectionsData(
            title: "mozilla.org", subtitle: "mozilla.org", image: nil, state: .on
        )
        let subject = createSubject()

        subject.viewDidLoad()

        XCTAssertEqual(subject.state.siteProtectionsData?.state, .on)
    }

    func test_viewDidLoad_withNoSelectedTab_leavesStateEmpty() async {
        provider.tabInfoToReturn = nil
        let subject = createSubject()

        subject.viewDidLoad()
        await Task.yield()

        XCTAssertNil(subject.state.currentTabInfo)
    }

    func test_updateMenuAppearance_rereadsOrientation() {
        let subject = createSubject(isPhoneLandscape: true)

        subject.updateMenuAppearance()

        XCTAssertTrue(subject.state.isPhoneLandscape)
    }

    // MARK: - Navigation

    func test_tapNavigateToDestination_forwardsToDelegate() {
        let subject = createSubject()

        subject.tapNavigateToDestination(MenuNavigationDestination(.bookmarks))

        XCTAssertEqual(delegate.navigatedTo.count, 1)
        XCTAssertEqual(delegate.navigatedTo.first?.destination, .bookmarks)
    }

    func test_tapCloseMenu_asksToDismiss() {
        let subject = createSubject()

        subject.tapCloseMenu()

        XCTAssertEqual(delegate.dismissCallCount, 1)
    }

    func test_tapZoom_navigatesToZoom() {
        let subject = createSubject()

        subject.tapZoom()

        XCTAssertEqual(delegate.navigatedTo.first?.destination, .zoom)
    }

    func test_tapEditBookmark_navigatesToEditBookmark() {
        let subject = createSubject()

        subject.tapEditBookmark()

        XCTAssertEqual(delegate.navigatedTo.first?.destination, .editBookmark)
    }

    // MARK: - Operations

    func test_tapAddToShortcuts_pinsTheTab() async {
        provider.tabInfoToReturn = makeTabInfo()
        let subject = createSubject()
        subject.viewDidLoad()
        await waitForTabInfo(subject)

        subject.tapAddToShortcuts()

        XCTAssertEqual(provider.addToShortcutsTabIDs, ["tab-1"])
        XCTAssertEqual(delegate.dismissCallCount, 1)
    }

    func test_tapRemoveFromShortcuts_unpinsTheTab() async {
        provider.tabInfoToReturn = makeTabInfo()
        let subject = createSubject()
        subject.viewDidLoad()
        await waitForTabInfo(subject)

        subject.tapRemoveFromShortcuts()

        XCTAssertEqual(provider.removeFromShortcutsTabIDs, ["tab-1"])
    }

    func test_tapAddToBookmarks_createsTheBookmark() async {
        provider.tabInfoToReturn = makeTabInfo()
        provider.bookmarkURLToReturn = "https://mozilla.org"
        let subject = createSubject()
        subject.viewDidLoad()
        await waitForTabInfo(subject)

        subject.tapAddToBookmarks()

        // The menu used to rely on TabManagerActionHandler for this; the operation must still happen.
        XCTAssertEqual(provider.addToBookmarksTabIDs, ["tab-1"])
    }

    func test_tapToggleUserAgent_togglesAndDismisses() {
        let subject = createSubject()

        subject.tapToggleUserAgent(isDefaultUserAgentDesktop: false, hasChangedUserAgent: false)

        XCTAssertEqual(provider.toggleUserAgentCallCount, 1)
        XCTAssertEqual(delegate.dismissCallCount, 1)
    }

    func test_tapToggleNightMode_togglesAndDismisses() {
        var toggled = 0
        let subject = createSubject(toggleNightMode: { toggled += 1 })

        subject.tapToggleNightMode(isActionOn: true)

        XCTAssertEqual(toggled, 1)
        XCTAssertEqual(delegate.dismissCallCount, 1)
    }

    // MARK: - Telemetry

    func test_tapCloseMenu_recordsCloseButton() {
        let subject = createSubject()

        subject.tapCloseMenu()

        XCTAssertEqual(gleanWrapper.recordEventCalled, 1)
    }

    func test_menuDismissed_recordsDismissal() {
        let subject = createSubject()

        subject.menuDismissed()

        XCTAssertEqual(gleanWrapper.recordEventCalled, 1)
    }

    // MARK: - Private Helpers

    private func makeTabInfo() -> MainMenuTabInfo {
        return MainMenuTabInfo(
            tabID: "tab-1",
            url: URL(string: "https://mozilla.org"),
            canonicalURL: nil,
            isHomepage: false,
            isDefaultUserAgentDesktop: false,
            hasChangedUserAgent: false,
            zoomLevel: 1.0,
            readerModeConfiguration: ReaderModeConfiguration(isAvailable: false, isActive: false),
            summaryIsAvailable: false,
            summarizerConfig: nil,
            isBookmarked: false,
            isInReadingList: false,
            isPinned: false,
            accountData: AccountData(title: "Signed out", subtitle: nil),
            translationConfiguration: nil
        )
    }

    private func waitForTabInfo(_ subject: MainMenuViewModel) async {
        for _ in 0..<20 where subject.state.currentTabInfo == nil {
            await Task.yield()
        }
    }

    private func createSubject(isBrowserDefault: Bool = false,
                               isPhoneLandscape: Bool = false,
                               toggleNightMode: @escaping () -> Void = {}) -> MainMenuViewModel {
        let subject = MainMenuViewModel(
            windowUUID: .XCTestDefaultUUID,
            tabInfoProvider: provider,
            telemetry: MainMenuTelemetry(gleanWrapper: gleanWrapper),
            webCompatTelemetry: WebCompatReporterTelemetry(gleanWrapper: gleanWrapper),
            isBrowserDefault: { isBrowserDefault },
            isPhoneLandscape: { isPhoneLandscape },
            toggleNightMode: toggleNightMode
        )
        subject.delegate = delegate
        trackForMemoryLeaks(subject)
        return subject
    }
}

@MainActor
final class MockMainMenuTabInfoProvider: MainMenuTabInfoProviding {
    var tabInfoToReturn: MainMenuTabInfo?
    var profileImageToReturn: UIImage?
    var siteProtectionsToReturn: SiteProtectionsData?
    var bookmarkURLToReturn: String?

    private(set) var toggleUserAgentCallCount = 0
    private(set) var addToShortcutsTabIDs: [TabUUID?] = []
    private(set) var removeFromShortcutsTabIDs: [TabUUID?] = []
    private(set) var addToBookmarksTabIDs: [TabUUID?] = []

    func tabInfo(for windowUUID: WindowUUID) async -> MainMenuTabInfo? { return tabInfoToReturn }
    func profileImage(for accountData: AccountData) async -> UIImage? { return profileImageToReturn }
    func siteProtectionsData(for windowUUID: WindowUUID) -> SiteProtectionsData? { return siteProtectionsToReturn }

    func toggleUserAgent(for windowUUID: WindowUUID) { toggleUserAgentCallCount += 1 }

    func addToShortcuts(tabID: TabUUID?, windowUUID: WindowUUID) { addToShortcutsTabIDs.append(tabID) }
    func removeFromShortcuts(tabID: TabUUID?, windowUUID: WindowUUID) { removeFromShortcutsTabIDs.append(tabID) }

    func addToBookmarks(tabID: TabUUID?, windowUUID: WindowUUID) -> String? {
        addToBookmarksTabIDs.append(tabID)
        return bookmarkURLToReturn
    }
}

@MainActor
final class MockMainMenuViewModelDelegate: MainMenuViewModelDelegate {
    private(set) var navigatedTo: [MenuNavigationDestination] = []
    private(set) var dismissCallCount = 0

    func mainMenuViewModelDidRequestNavigation(to destination: MenuNavigationDestination) {
        navigatedTo.append(destination)
    }

    func mainMenuViewModelDidRequestDismiss() {
        dismissCallCount += 1
    }
}
