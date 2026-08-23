// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Redux
import XCTest
import SummarizeKit
import QuickAnswersKit

@testable import Client

final class BrowserViewControllerStateTests: XCTestCase, StoreTestUtility {
    let storeUtilityHelper = StoreTestUtilityHelper()

    override func setUp() async throws {
        try await super.setUp()
        DependencyHelperMock().bootstrapDependencies()
        setupStore()
    }

    override func tearDown() async throws {
        // The visibility store is a singleton; leaving a window marked visible leaks into the
        // next test.
        SearchBarVisibilityStore.shared.setSearchBarVisible(false, for: .XCTestDefaultUUID)
        DependencyHelperMock().reset()
        resetStore()
        try await super.tearDown()
    }

    func testAddNewTabAction() {
        let initialState = createSubject()

        XCTAssertNil(initialState.navigateTo)

        let action = getAction(for: .addNewTab)
        let newState = BrowserViewControllerState.reduce(initialState, with: action)

        XCTAssertEqual(newState.navigateTo, .newTab)
    }

    func testShowNewTabLongpPressActions() {
        let initialState = createSubject()

        XCTAssertNil(initialState.displayView)

        let action = getAction(for: .showNewTabLongPressActions)
        let newState = BrowserViewControllerState.reduce(initialState, with: action)

        XCTAssertEqual(newState.displayView, .newTabLongPressActions)
    }

    func testShowGoogleLensPhotoPickerAction() {
        let initialState = createSubject()

        XCTAssertNil(initialState.displayView)

        let action = getAction(for: .showGoogleLensPhotoPicker)
        let newState = BrowserViewControllerState.reduce(initialState, with: action)

        XCTAssertEqual(newState.displayView, .googleLensPhotoPicker)
    }

    func testShowGoogleLensCameraAction() {
        let initialState = createSubject()

        XCTAssertNil(initialState.displayView)

        let action = getAction(for: .showGoogleLensCamera)
        let newState = BrowserViewControllerState.reduce(initialState, with: action)

        XCTAssertEqual(newState.displayView, .googleLensCamera)
    }

    func testShowPasswordGeneratorAction() {
        let initialState = createSubject()
        let mockEvaluator = MockPasswordGeneratorScriptEvaluator()
        let frameContext = PasswordGeneratorFrameContext(origin: "https://foo.com",
                                                         host: "foo.com",
                                                         scriptEvaluator: mockEvaluator,
                                                         frameInfo: nil)

        XCTAssertNil(initialState.displayView)

        let action = GeneralBrowserAction(frameContext: frameContext,
                                          windowUUID: .XCTestDefaultUUID,
                                          actionType: GeneralBrowserActionType.showPasswordGenerator)
        let newState = BrowserViewControllerState.reduce(initialState, with: action)
        let displayView = newState.displayView!
        let desiredDisplayView =
        BrowserViewControllerState.DisplayType.passwordGenerator

        XCTAssertEqual(displayView, desiredDisplayView)
        XCTAssertNotNil(newState.frameContext)
    }

    func testReloadWebsiteAction() {
        let initialState = createSubject()

        XCTAssertNil(initialState.navigateTo)

        let action = getAction(for: .reloadWebsite)
        let newState = BrowserViewControllerState.reduce(initialState, with: action)

        XCTAssertEqual(newState.navigateTo, .reload)
    }

    func testLoadWaybackURLAction() {
        let initialState = createSubject()

        XCTAssertNil(initialState.navigateTo)

        let archivedURL = URL(string: "https://web.archive.org/web/20130919044612/http://example.com/")!
        let action = getGeneralBrowserAction(destinationURL: archivedURL, for: .loadWaybackURL)
        let newState = BrowserViewControllerState.reduce(initialState, with: action)

        XCTAssertEqual(newState.navigateTo, .loadURL(archivedURL))
    }

    func test_loadWaybackURLAction_withNilURL_doesNotNavigate() {
        let initialState = createSubject()

        let action = getGeneralBrowserAction(destinationURL: nil, for: .loadWaybackURL)
        let newState = BrowserViewControllerState.reduce(initialState, with: action)

        XCTAssertNil(newState.navigateTo)
    }

    func testShowSummarizerAction() {
        let initialState = createSubject()

        let summarizerConfig = SummarizerConfig(instructions: "Test instructions", options: [:])
        let action = GeneralBrowserAction(
            summarizerConfig: summarizerConfig,
            summarizerTrigger: .toolbarIcon,
            windowUUID: .XCTestDefaultUUID,
            actionType: GeneralBrowserActionType.showSummarizer
        )
        let newState = BrowserViewControllerState.reduce(initialState, with: action)

        guard case .summarizer(let config, let trigger) = newState.navigationDestination?.destination else {
            return XCTFail("Expected .summarizer")
        }
        XCTAssertEqual(config, summarizerConfig)
        XCTAssertEqual(trigger, .toolbarIcon)
    }

    func test_showSummarizerAction_withNilConfig_doesNotNavigate() {
        let initialState = createSubject()

        let action = getAction(for: .showSummarizer)
        let newState = BrowserViewControllerState.reduce(initialState, with: action)

        XCTAssertNil(newState.navigationDestination)
    }

    // MARK: - Summarizer middleware actions
    func test_showReaderModeBarSummarizerButton_setsReaderModeBarSummarizerButtonVisible() {
        let initialState = createSubject()

        let action = SummarizeAction(
            windowUUID: .XCTestDefaultUUID,
            actionType: SummarizeMiddlewareActionType.showReaderModeBarSummarizerButton,
        )
        let newState = BrowserViewControllerState.reduce(initialState, with: action)

        XCTAssertTrue(newState.shouldShowReaderModeBarSummarizerButton)
    }

    func test_summarizerNotAvailable_setsReaderModeBarSummarizerButtonHidden() {
        var initialState = createSubject()
        initialState.shouldShowReaderModeBarSummarizerButton = true

        let action = SummarizeAction(
            windowUUID: .XCTestDefaultUUID,
            actionType: SummarizeMiddlewareActionType.summaryNotAvailable,
        )
        let newState = BrowserViewControllerState.reduce(initialState, with: action)

        XCTAssertFalse(newState.shouldShowReaderModeBarSummarizerButton)
    }

    // MARK: - Navigation Browser Action
    func test_tapOnCell_navigationBrowserAction_returnsExpectedState() throws {
        let initialState = createSubject()

        XCTAssertNil(initialState.navigationDestination)

        let url = try XCTUnwrap(URL(string: "www.example.com"))
        let action = getNavigationBrowserAction(for: .tapOnCell, destination: .link, url: url)
        let newState = BrowserViewControllerState.reduce(initialState, with: action)

        let destination = newState.navigationDestination?.destination
        switch destination {
        case .link:
            break
        default:
            XCTFail("destination is not the right type")
        }

        XCTAssertEqual(newState.navigationDestination?.url?.absoluteString, "www.example.com")
    }

    func test_tapOnLink_navigationBrowserAction_returnsExpectedState() throws {
        let initialState = createSubject()

        XCTAssertNil(initialState.navigationDestination)

        let url = try XCTUnwrap(URL(string: "www.example.com"))
        let action = getNavigationBrowserAction(for: .tapOnLink, destination: .link, url: url)
        let newState = BrowserViewControllerState.reduce(initialState, with: action)

        let destination = newState.navigationDestination?.destination
        switch destination {
        case .link:
            break
        default:
            XCTFail("destination is not the right type")
        }

        XCTAssertEqual(newState.navigationDestination?.url?.absoluteString, "www.example.com")
    }

    func test_tapOnShareSheet_navigationBrowserAction_returnsExpectedState() throws {
        let initialState = createSubject()

        XCTAssertNil(initialState.navigationDestination)

        let url = try XCTUnwrap(URL(string: "www.example.com"))
        let shareSheetConfiguration = ShareSheetConfiguration(
            shareType: .site(url: url),
            shareMessage: nil,
            sourceView: UIView(),
            sourceRect: nil,
            toastContainer: UIView(),
            popoverArrowDirection: [.up]
        )
        let action = getNavigationBrowserAction(
            for: .tapOnShareSheet,
            destination: .shareSheet(shareSheetConfiguration)
        )
        let newState = BrowserViewControllerState.reduce(initialState, with: action)

        let destination = newState.navigationDestination?.destination
        switch destination {
        case .shareSheet(let configuration):
            switch configuration.shareType {
            case .site(let url):
                XCTAssertEqual(url, try XCTUnwrap(URL(string: "www.example.com")))
            default:
                XCTFail("shareType is not the right type")
            }
        default:
            XCTFail("destination is not the right type")
        }

        XCTAssertEqual(newState.navigationDestination?.url, nil)
    }

    func test_longPressOnCell_navigationBrowserAction_returnsExpectedState() throws {
        let initialState = createSubject()

        XCTAssertNil(initialState.navigationDestination)

        let url = try XCTUnwrap(URL(string: "www.example.com"))
        let action = getNavigationBrowserAction(for: .longPressOnCell, destination: .link, url: url)
        let newState = BrowserViewControllerState.reduce(initialState, with: action)

        let destination = newState.navigationDestination?.destination
        switch destination {
        case .link:
            break
        default:
            XCTFail("destination is not the right type")
        }

        XCTAssertEqual(newState.navigationDestination?.url?.absoluteString, "www.example.com")
    }

    func test_tapOnOpenInNewTab_navigationBrowserAction_returnsExpectedState() throws {
        let initialState = createSubject()

        XCTAssertNil(initialState.navigationDestination)

        let url = try XCTUnwrap(URL(string: "www.example.com"))
        let action = NavigationBrowserAction(
            navigationDestination: NavigationDestination(.newTab, url: url, isPrivate: false, selectNewTab: false),
            windowUUID: .XCTestDefaultUUID,
            actionType: NavigationBrowserActionType.tapOnOpenInNewTab
        )
        let newState = BrowserViewControllerState.reduce(initialState, with: action)

        let navigationDestination = try XCTUnwrap(newState.navigationDestination)
        switch navigationDestination.destination {
        case .newTab:
            break
        default:
            XCTFail("destination is not the right type")
        }

        XCTAssertEqual(navigationDestination.url?.absoluteString, "www.example.com")
        XCTAssertFalse(navigationDestination.isPrivate ?? true)
        XCTAssertFalse(navigationDestination.selectNewTab ?? true)
    }

    func test_tapOnOpenInNewTab_forPrivateTab_navigationBrowserAction_returnsExpectedState() throws {
        let initialState = createSubject()

        XCTAssertNil(initialState.navigationDestination)

        let url = try XCTUnwrap(URL(string: "www.example.com"))
        let action = NavigationBrowserAction(
            navigationDestination: NavigationDestination(.newTab, url: url, isPrivate: true, selectNewTab: true),
            windowUUID: .XCTestDefaultUUID,
            actionType: NavigationBrowserActionType.tapOnOpenInNewTab
        )
        let newState = BrowserViewControllerState.reduce(initialState, with: action)

        let navigationDestination = try XCTUnwrap(newState.navigationDestination)
        switch navigationDestination.destination {
        case .newTab:
            break
        default:
            XCTFail("destination is not the right type")
        }

        XCTAssertEqual(navigationDestination.url?.absoluteString, "www.example.com")
        XCTAssertTrue(navigationDestination.isPrivate ?? false)
        XCTAssertTrue(navigationDestination.selectNewTab ?? false)
    }

    func test_searchQuery_navigationBrowserAction_returnsExpectedState() throws {
        let initialState = createSubject()

        XCTAssertNil(initialState.navigationDestination)

        let action = NavigationBrowserAction(
            navigationDestination: NavigationDestination(.searchQuery("Test")),
            windowUUID: .XCTestDefaultUUID,
            actionType: NavigationBrowserActionType.tapOnCell
        )
        let newState = BrowserViewControllerState.reduce(initialState, with: action)

        let navigationDestination = try XCTUnwrap(newState.navigationDestination)
        switch navigationDestination.destination {
        case .searchQuery(let query):
            XCTAssertEqual(query, "Test")
        default:
            XCTFail("destination is not the right type")
        }

        XCTAssertNil(navigationDestination.url)
    }

    func test_tapOnSettingsSection_navigationBrowserAction_returnsExpectedState() {
        let initialState = createSubject()

        XCTAssertNil(initialState.navigationDestination)

        let action = getNavigationBrowserAction(for: .tapOnSettingsSection, destination: .settings(.topSites))
        let newState = BrowserViewControllerState.reduce(initialState, with: action)

        let destination = newState.navigationDestination?.destination
        switch destination {
        case .settings(let section):
            XCTAssertEqual(section, .topSites)
        default:
            XCTFail("destination is not the right type")
        }

        XCTAssertEqual(newState.navigationDestination?.url, nil)
    }

    // MARK: StartAtHomeAction

    func test_shouldStartAtHome_withStartAtHomeAction_returnsTrue() {
        let initialState = createSubject()

        XCTAssertFalse(initialState.shouldStartAtHome)

        let action = StartAtHomeAction(
            shouldStartAtHome: true,
            windowUUID: .XCTestDefaultUUID,
            actionType: StartAtHomeMiddlewareActionType.startAtHomeCheckCompleted
        )
        let newState = BrowserViewControllerState.reduce(initialState, with: action)

        XCTAssertTrue(newState.shouldStartAtHome)
    }

    func test_shouldStartAtHome_withStartAtHomeAction_returnsFalse() {
        let initialState = createSubject()

        XCTAssertFalse(initialState.shouldStartAtHome)

        let action = StartAtHomeAction(
            windowUUID: .XCTestDefaultUUID,
            actionType: StartAtHomeMiddlewareActionType.startAtHomeCheckCompleted
        )
        let newState = BrowserViewControllerState.reduce(initialState, with: action)

        XCTAssertFalse(newState.shouldStartAtHome)
    }

    // MARK: - Zero Search State

    func test_tapOnHomepageSearchBar_navigationBrowserAction_returnsExpectedState() {
        let initialState = createSubject()

        XCTAssertNil(initialState.navigationDestination)

        let action = getNavigationBrowserAction(for: .tapOnHomepageSearchBar, destination: .homepageZeroSearch)
        let newState = BrowserViewControllerState.reduce(initialState, with: action)
        let destination = newState.navigationDestination?.destination
        switch destination {
        case .homepageZeroSearch:
            break
        default:
            XCTFail("destination is not the right type")
        }

        XCTAssertEqual(newState.navigationDestination?.url, nil)
    }

    func test_didTapButtonToolbarAction_withHomepageSearch_andSearchButtonType_navigateToZeroSearch() {
        setupStoreForSearchBar()
        let initialState = createSubject()

        XCTAssertNil(initialState.navigationDestination)

        let action = ToolbarMiddlewareAction(
            buttonType: .search,
            windowUUID: .XCTestDefaultUUID,
            actionType: ToolbarMiddlewareActionType.didTapButton
        )
        let newState = BrowserViewControllerState.reduce(initialState, with: action)
        let destination = newState.navigationDestination?.destination
        switch destination {
        case .homepageZeroSearch:
            break
        default:
            XCTFail("destination is not the right type")
        }

        XCTAssertEqual(newState.navigationDestination?.url, nil)
    }

    func test_didTapButtonToolbarAction_withHomepageSearch_andNoButtonType_navigateToZeroSearch() {
        setupStoreForSearchBar()
        let initialState = createSubject()

        XCTAssertNil(initialState.navigationDestination)

        let action = ToolbarMiddlewareAction(
            windowUUID: .XCTestDefaultUUID,
            actionType: ToolbarMiddlewareActionType.didTapButton
        )
        let newState = BrowserViewControllerState.reduce(initialState, with: action)

        XCTAssertNil(newState.navigationDestination)
    }

    func test_didTapButtonToolbarAction_withoutHomepageSearch_andSearchButtonType_doesNotNavigateToZeroSearch() {
        let initialState = createSubject()

        XCTAssertNil(initialState.navigationDestination)

        let action = ToolbarMiddlewareAction(
            buttonType: .search,
            windowUUID: .XCTestDefaultUUID,
            actionType: ToolbarMiddlewareActionType.didTapButton
        )
        let newState = BrowserViewControllerState.reduce(initialState, with: action)

        XCTAssertNil(newState.navigationDestination)
    }

    func test_didTapButtonToolbarAction_withoutHomepageSearch_andNoButtonType_doesNotNavigateToZeroSearch() {
        let initialState = createSubject()

        XCTAssertNil(initialState.navigationDestination)

        let action = ToolbarMiddlewareAction(
            windowUUID: .XCTestDefaultUUID,
            actionType: ToolbarMiddlewareActionType.didTapButton
        )
        let newState = BrowserViewControllerState.reduce(initialState, with: action)

        XCTAssertNil(newState.navigationDestination)
    }

    // MARK: - Shortcuts Library

    func test_tapOnShortcutsShowAllButton_navigationBrowserAction_returnsExpectedState() {
        let initialState = createSubject()

        XCTAssertNil(initialState.navigationDestination)

        let action = getNavigationBrowserAction(for: .tapOnShortcutsShowAllButton, destination: .shortcutsLibrary)
        let newState = BrowserViewControllerState.reduce(initialState, with: action)

        let destination = newState.navigationDestination?.destination
        switch destination {
        case .shortcutsLibrary:
            break
        default:
            XCTFail("destination is not the right type")
        }
    }

    // MARK: - Privacy Notice Link

    func test_tapOnPrivacyNoticeLink_navigationBrowserAction_returnsExpectedState() {
        let initialState = createSubject()

        XCTAssertNil(initialState.navigationDestination)

        guard let url = URL(string: "https://www.mozilla.com") else { return }

        let action = getNavigationBrowserAction(for: .tapOnPrivacyNoticeLink, destination: .privacyNoticeLink(url))
        let newState = BrowserViewControllerState.reduce(initialState, with: action)

        let destination = newState.navigationDestination?.destination
        switch destination {
        case .privacyNoticeLink:
            break
        default:
            XCTFail("destination is not the right type")
        }
    }

    // MARK: - Quick Answers
    func test_tapOnQuickAnswersButton_navigationBrowserAction_returnsExpectedState() throws {
        let initialState = createSubject()

        let action = getNavigationBrowserAction(
            for: .tapOnQuickAnswersButton,
            destination: .quickAnswers(transitionType: .crossDissolve(sourceRect: .zero))
        )
        let newState = BrowserViewControllerState.reduce(initialState, with: action)

        XCTAssertEqual(
            newState.navigationDestination?.destination,
            .quickAnswers(transitionType: .crossDissolve(sourceRect: .zero))
        )
    }

    // MARK: - Reader Mode

    func test_tapOnReaderMode_navigationBrowserAction_returnsExpectedState() {
        let initialState = createSubject()

        XCTAssertNil(initialState.navigationDestination)

        let action = getNavigationBrowserAction(for: .tapOnReaderMode, destination: .readerMode)
        let newState = BrowserViewControllerState.reduce(initialState, with: action)

        XCTAssertEqual(newState.navigationDestination?.destination, .readerMode)
    }

    func test_navigationDestinationHandled_clearsNavigationDestination() {
        let initialState = createSubject()

        let navigateAction = getNavigationBrowserAction(
            for: .tapOnQuickAnswersButton,
            destination: .quickAnswers(transitionType: .crossDissolve(sourceRect: .zero))
        )
        let navigatedState = BrowserViewControllerState.reduce(initialState, with: navigateAction)

        let handledAction = getNavigationBrowserAction(
            for: .navigationDestinationHandled,
            destination: .quickAnswers(transitionType: .crossDissolve(sourceRect: .zero))
        )
        let handledState = BrowserViewControllerState.reduce(navigatedState, with: handledAction)

        XCTAssertNotNil(navigatedState.navigationDestination)
        XCTAssertNil(handledState.navigationDestination)
    }

    // MARK: - Private
    private func createSubject() -> BrowserViewControllerState {
        return BrowserViewControllerState(windowUUID: .XCTestDefaultUUID)
    }

    private func getAction(for actionType: GeneralBrowserActionType) -> GeneralBrowserAction {
        return GeneralBrowserAction(windowUUID: .XCTestDefaultUUID, actionType: actionType)
    }

    private func getNavigationBrowserAction(
        for actionType: NavigationBrowserActionType,
        destination: BrowserNavigationDestination,
        url: URL? = nil
    ) -> NavigationBrowserAction {
        return NavigationBrowserAction(
            navigationDestination: NavigationDestination(destination, url: url),
            windowUUID: .XCTestDefaultUUID,
            actionType: actionType
        )
    }

    func getGeneralBrowserAction(selectedTabURL: URL? = nil,
                                 destinationURL: URL? = nil,
                                 isNativeErrorPage: Bool? = nil,
                                 for actionType: GeneralBrowserActionType) -> GeneralBrowserAction {
        return  GeneralBrowserAction(selectedTabURL: selectedTabURL,
                                     destinationURL: destinationURL,
                                     isNativeErrorPage: isNativeErrorPage,
                                     windowUUID: .XCTestDefaultUUID,
                                     actionType: actionType)
        }

    /// The reducer reads the search bar's visibility from `SearchBarVisibilityStore` now rather
    /// than from `HomepageState`, so this only has to set that.
    func setupStoreForSearchBar() {
        SearchBarVisibilityStore.shared.setSearchBarVisible(true, for: .XCTestDefaultUUID)
    }

    // MARK: StoreTestUtility
    func setupAppState() -> AppState {
        return AppState()
    }

    func setupStore() {
        StoreTestUtilityHelper.setupStore(
            with: setupAppState(),
            middlewares: []
        )
    }

    // In order to avoid flaky tests, we should reset the store
    // similar to production
    func resetStore() {
        StoreTestUtilityHelper.resetStore()
    }
}
