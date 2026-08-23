// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Redux
import XCTest
import Common

@testable import Client

final class ToolbarStateTests: XCTestCase, BusTestUtility {
    let storeUtilityHelper = BusTestUtilityHelper()
    let windowUUID: WindowUUID = .XCTestDefaultUUID
    var mockBus: MockBrowserEventBus!
    var mockProfile: MockProfile!

    override func setUp() async throws {
        try await super.setUp()
        mockProfile = MockProfile()
        DependencyHelperMock().bootstrapDependencies()

        // We must reset the global mock store prior to each test
        setupBus()
    }

    override func tearDown() async throws {
        DependencyHelperMock().reset()
        resetBus()
        mockProfile = nil
        try await super.tearDown()
    }

    func tests_initialState_returnsExpectedState() {
        let initialState = createSubject()

        XCTAssertEqual(initialState.windowUUID, windowUUID)
        XCTAssertEqual(initialState.toolbarPosition, .top)
        XCTAssertFalse(initialState.isPrivateMode)
        XCTAssertEqual(initialState.addressToolbar, AddressBarState(windowUUID: windowUUID))
        XCTAssertEqual(initialState.navigationToolbar, NavigationBarState(windowUUID: windowUUID))
        XCTAssertTrue(initialState.isShowingNavigationToolbar)
        XCTAssertFalse(initialState.isShowingTopTabs)
        XCTAssertFalse(initialState.canGoBack)
        XCTAssertFalse(initialState.canGoForward)
        XCTAssertEqual(initialState.numberOfTabs, 1)
        XCTAssertFalse(initialState.showMenuWarningBadge)
        XCTAssertFalse(initialState.canShowNavigationHint)
        XCTAssertTrue(initialState.shouldAnimate)
    }

    func test_didLoadToolbarsAction_returnsExpectedState() {
        let initialState = createSubject()

        let newState = ToolbarState.reduce(
            initialState,
            with: ToolbarAction(
                toolbarPosition: .top,
                addressBorderPosition: .bottom,
                displayNavBorder: true,
                translationConfiguration: TranslationConfiguration(prefs: mockProfile.prefs),
                windowUUID: windowUUID,
                actionType: ToolbarActionType.didLoadToolbars)
        )

        XCTAssertEqual(newState.windowUUID, windowUUID)
        XCTAssertEqual(newState.toolbarPosition, .top)
        XCTAssertFalse(newState.isPrivateMode)
        XCTAssertTrue(newState.isShowingNavigationToolbar)
        XCTAssertFalse(newState.isShowingTopTabs)
        XCTAssertFalse(newState.canGoBack)
        XCTAssertFalse(newState.canGoForward)
        XCTAssertEqual(newState.numberOfTabs, 1)
        XCTAssertFalse(newState.showMenuWarningBadge)
        XCTAssertFalse(newState.canShowNavigationHint)
        XCTAssertNil(newState.addressToolbar.translationConfiguration)
    }

    func test_borderPositionChangedAction_returnsExpectedState() {
        let initialState = createSubject()

        let newState = ToolbarState.reduce(
            initialState,
            with: ToolbarAction(
                addressBorderPosition: .top,
                displayNavBorder: false,
                windowUUID: windowUUID,
                actionType: ToolbarActionType.borderPositionChanged)
        )

        XCTAssertEqual(newState.windowUUID, windowUUID)
        XCTAssertNotEqual(newState.addressToolbar, initialState.addressToolbar)
        XCTAssertEqual(newState.navigationToolbar, initialState.navigationToolbar)
    }

    func test_urlDidChangeAction_returnsExpectedState() {
        let initialState = createSubject()

        let newState = loadWebsiteAction(state: initialState)

        XCTAssertEqual(newState.windowUUID, windowUUID)
        XCTAssertFalse(newState.isPrivateMode)
        XCTAssertTrue(newState.isShowingNavigationToolbar)
        XCTAssertTrue(newState.canGoBack)
        XCTAssertFalse(newState.canGoForward)
        XCTAssertNil(newState.addressToolbar.translationConfiguration)
    }

    func test_urlDidChangeAction_withTranslationConfiguration_returnsExpectedState() {
        let initialState = createSubject()

        let newState = ToolbarState.reduce(
            initialState,
            with: ToolbarAction(
                translationConfiguration: TranslationConfiguration(prefs: mockProfile.prefs),
                windowUUID: windowUUID,
                actionType: ToolbarActionType.urlDidChange
            )
        )

        XCTAssertEqual(newState.windowUUID, windowUUID)
        XCTAssertNotNil(newState.addressToolbar.translationConfiguration)
    }

    func test_didSetTextInLocationViewAction_returnsExpectedState() {
        let initialState = createSubject()

        let newState = ToolbarState.reduce(
            initialState,
            with: ToolbarAction(
                searchTerm: "text",
                windowUUID: windowUUID,
                actionType: ToolbarActionType.didSetTextInLocationView)
        )

        XCTAssertNotEqual(newState.addressToolbar, initialState.addressToolbar)
        XCTAssertEqual(newState.navigationToolbar, initialState.navigationToolbar)
    }

    func test_didPasteSearchTermAction_returnsExpectedState() {
        let initialState = createSubject()

        let newState = ToolbarState.reduce(
            initialState,
            with: ToolbarAction(
                searchTerm: "text",
                windowUUID: windowUUID,
                actionType: ToolbarActionType.didPasteSearchTerm)
        )

        XCTAssertNotEqual(newState.addressToolbar, initialState.addressToolbar)
        XCTAssertEqual(newState.navigationToolbar, initialState.navigationToolbar)
    }

    func test_didStartEditingUrlAction_returnsExpectedState() {
        let initialState = createSubject()

        let newState = ToolbarState.reduce(
            initialState,
            with: ToolbarAction(
                windowUUID: windowUUID,
                actionType: ToolbarActionType.didStartEditingUrl)
        )

        XCTAssertNotEqual(newState.addressToolbar, initialState.addressToolbar)
        XCTAssertEqual(newState.navigationToolbar, initialState.navigationToolbar)
    }

    func test_cancelEditAction_returnsExpectedState() {
        let initialState = createSubject()

        let newState = ToolbarState.reduce(
            initialState,
            with: ToolbarAction(
                windowUUID: windowUUID,
                actionType: ToolbarActionType.cancelEdit)
        )

        XCTAssertEqual(newState.addressToolbar, initialState.addressToolbar)
        XCTAssertEqual(newState.navigationToolbar, initialState.navigationToolbar)
    }

    func test_cancelEditOnHomepageAction_returnsExpectedState() {
        let initialState = createSubject()

        let newState = ToolbarState.reduce(
            initialState,
            with: ToolbarAction(
                windowUUID: windowUUID,
                actionType: ToolbarActionType.cancelEditOnHomepage)
        )

        XCTAssertEqual(newState.addressToolbar, initialState.addressToolbar)
        XCTAssertEqual(newState.navigationToolbar, initialState.navigationToolbar)
    }

    func test_keyboardStateDidChangeAction_returnsExpectedState() {
        let initialState = createSubject()

        let newState = ToolbarState.reduce(
            initialState,
            with: ToolbarAction(
                shouldShowKeyboard: true,
                windowUUID: windowUUID,
                actionType: ToolbarActionType.keyboardStateDidChange)
        )

        XCTAssertNotEqual(newState.addressToolbar, initialState.addressToolbar)
        XCTAssertEqual(newState.navigationToolbar, initialState.navigationToolbar)
    }

    func test_websiteLoadingStateDidChangeAction_returnsExpectedState() {
        let initialState = createSubject()

        let newState = ToolbarState.reduce(
            initialState,
            with: ToolbarAction(
                isLoading: true,
                windowUUID: windowUUID,
                actionType: ToolbarActionType.websiteLoadingStateDidChange)
        )

        XCTAssertNotEqual(newState.addressToolbar, initialState.addressToolbar)
        XCTAssertEqual(newState.navigationToolbar, initialState.navigationToolbar)
    }

    func test_searchEngineDidChangeAction_returnsExpectedState() {
        let initialState = createSubject()

        let newState = ToolbarState.reduce(
            initialState,
            with: ToolbarAction(
                windowUUID: windowUUID,
                actionType: ToolbarActionType.searchEngineDidChange)
        )

        XCTAssertEqual(newState.addressToolbar, initialState.addressToolbar)
        XCTAssertEqual(newState.navigationToolbar, initialState.navigationToolbar)
    }

    func test_googleLensAvailabilityDidChangeAction_updatesAddressToolbarGoogleLensAvailability() {
        let initialState = createSubject()

        let newState = ToolbarState.reduce(
            initialState,
            with: ToolbarMiddlewareAction(
                isGoogleLensEnabled: true,
                windowUUID: windowUUID,
                actionType: ToolbarMiddlewareActionType.googleLensAvailabilityDidChange)
        )

        XCTAssertEqual(newState.addressToolbar.editingAccessoryAction?.actionType, .googleLens)
        XCTAssertEqual(newState.navigationToolbar, initialState.navigationToolbar)
    }

    func test_clearSearchAction_returnsExpectedState() {
        let initialState = createSubject()

        let newState = ToolbarState.reduce(
            initialState,
            with: ToolbarAction(
                windowUUID: windowUUID,
                actionType: ToolbarActionType.clearSearch)
        )

        XCTAssertNotEqual(newState.addressToolbar, initialState.addressToolbar)
        XCTAssertEqual(newState.navigationToolbar, initialState.navigationToolbar)
    }

    func test_didDeleteSearchTermAction_returnsExpectedState() {
        let initialState = createSubject()

        let newState = ToolbarState.reduce(
            initialState,
            with: ToolbarAction(
                windowUUID: windowUUID,
                actionType: ToolbarActionType.didDeleteSearchTerm)
        )

        XCTAssertNotEqual(newState.addressToolbar, initialState.addressToolbar)
        XCTAssertEqual(newState.navigationToolbar, initialState.navigationToolbar)
    }

    func test_didEnterSearchTermAction_returnsExpectedState() {
        let initialState = createSubject()

        let newState = ToolbarState.reduce(
            initialState,
            with: ToolbarAction(
                windowUUID: windowUUID,
                actionType: ToolbarActionType.didEnterSearchTerm)
        )

        XCTAssertNotEqual(newState.addressToolbar, initialState.addressToolbar)
        XCTAssertEqual(newState.navigationToolbar, initialState.navigationToolbar)
    }

    func test_didSetSearchTermAction_returnsExpectedState() {
        let initialState = createSubject()

        let newState = ToolbarState.reduce(
            initialState,
            with: ToolbarAction(
                searchTerm: "text",
                windowUUID: windowUUID,
                actionType: ToolbarActionType.didSetSearchTerm)
        )

        XCTAssertNotEqual(newState.addressToolbar, initialState.addressToolbar)
        XCTAssertEqual(newState.navigationToolbar, initialState.navigationToolbar)
    }

    func test_didStartTypingAction_returnsExpectedState() {
        let initialState = createSubject()

        let newState = ToolbarState.reduce(
            initialState,
            with: ToolbarAction(
                windowUUID: windowUUID,
                actionType: ToolbarActionType.didStartTyping)
        )

        XCTAssertNotEqual(newState.addressToolbar, initialState.addressToolbar)
        XCTAssertEqual(newState.navigationToolbar, initialState.navigationToolbar)
    }

    func test_animationStateChanged_returnsExpectedState() {
        let initialState = createSubject()

        let newState = ToolbarState.reduce(
            initialState,
            with: ToolbarAction(
                shouldAnimate: false,
                windowUUID: windowUUID,
                actionType: ToolbarActionType.animationStateChanged)
        )

        XCTAssertNotEqual(newState.shouldAnimate, initialState.shouldAnimate)
        XCTAssertFalse(newState.shouldAnimate)
    }

    func test_showMenuWarningBadgeAction_returnsExpectedState() {
        let initialState = createSubject()

        let newState = ToolbarState.reduce(
            initialState,
            with: ToolbarAction(
                showMenuWarningBadge: true,
                windowUUID: windowUUID,
                actionType: ToolbarActionType.showMenuWarningBadge
            )
        )

        XCTAssertEqual(newState.windowUUID, windowUUID)
        XCTAssertTrue(newState.showMenuWarningBadge)
    }

    func test_numberOfTabsChangedAction_returnsExpectedState() {
        let initialState = createSubject()

        let newState = ToolbarState.reduce(
            initialState,
            with: ToolbarAction(
                numberOfTabs: 2,
                isShowingTopTabs: false,
                windowUUID: windowUUID,
                actionType: ToolbarActionType.numberOfTabsChanged
            )
        )

        XCTAssertEqual(newState.windowUUID, windowUUID)
        XCTAssertEqual(newState.numberOfTabs, 2)
    }

    func test_toolbarPositionChangedAction_returnsExpectedState() {
        let initialState = createSubject()

        let newState = ToolbarState.reduce(
            initialState,
            with: ToolbarAction(
                toolbarPosition: .top,
                addressBorderPosition: .bottom,
                displayNavBorder: true,
                windowUUID: windowUUID,
                actionType: ToolbarActionType.toolbarPositionChanged
            )
        )

        XCTAssertEqual(newState.windowUUID, windowUUID)
        XCTAssertEqual(newState.toolbarPosition, .top)
    }

    func test_readerModeStateChangedAction_onHomepage_returnsExpectedState() {
        let initialState = createSubject()

        let newState = ToolbarState.reduce(
            initialState,
            with: ToolbarAction(
                readerModeState: .available,
                windowUUID: windowUUID,
                actionType: ToolbarActionType.readerModeStateChanged
            )
        )

        XCTAssertNotEqual(newState.addressToolbar, initialState.addressToolbar)
        XCTAssertEqual(newState.navigationToolbar, initialState.navigationToolbar)
    }

    func test_navigationMiddleButtonDidChangeAction_returnsExpectedState() {
        let initialState = createSubject()

        let newState = ToolbarState.reduce(
            initialState,
            with: ToolbarAction(
                middleButton: .home,
                windowUUID: windowUUID,
                actionType: ToolbarActionType.navigationMiddleButtonDidChange
            )
        )

        XCTAssertEqual(newState.addressToolbar, initialState.addressToolbar)
        XCTAssertNotEqual(newState.navigationToolbar, initialState.navigationToolbar)
    }

    func test_backForwardButtonStateChangedAction_returnsExpectedState() {
        let initialState = createSubject()

        let urlDidChangeState = loadWebsiteAction(state: initialState)
        let newState = ToolbarState.reduce(
            urlDidChangeState,
            with: ToolbarAction(
                canGoBack: true,
                canGoForward: false,
                windowUUID: windowUUID,
                actionType: ToolbarActionType.backForwardButtonStateChanged
            )
        )

        XCTAssertEqual(newState.windowUUID, windowUUID)
        XCTAssertTrue(newState.canGoBack)
        XCTAssertFalse(newState.canGoForward)
    }

    func test_traitCollectionDidChangeAction_returnsExpectedState() {
        let initialState = createSubject()

        let newState = ToolbarState.reduce(
            initialState,
            with: ToolbarAction(
                isShowingNavigationToolbar: false,
                isShowingTopTabs: true,
                windowUUID: windowUUID,
                actionType: ToolbarActionType.traitCollectionDidChange
            )
        )

        XCTAssertEqual(newState.windowUUID, windowUUID)
        XCTAssertFalse(newState.isShowingNavigationToolbar)
        XCTAssertTrue(newState.isShowingTopTabs)
    }

    func test_navigationButtonDoubleTappedAction_returnsExpectedState() {
        let initialState = createSubject()

        let newState = ToolbarState.reduce(
            initialState,
            with: ToolbarAction(
                windowUUID: windowUUID,
                actionType: ToolbarActionType.navigationButtonDoubleTapped
            )
        )

        XCTAssertEqual(newState.windowUUID, windowUUID)
        XCTAssertTrue(newState.canShowNavigationHint)
    }

    func test_navigationHintFinishedPresentingAction_returnsExpectedState() {
        let initialState = createSubject()

        let newState = ToolbarState.reduce(
            initialState,
            with: ToolbarAction(
                windowUUID: windowUUID,
                actionType: ToolbarActionType.navigationHintFinishedPresenting
            )
        )

        XCTAssertEqual(newState.windowUUID, windowUUID)
        XCTAssertFalse(newState.canShowNavigationHint)
    }

    func test_didTapSearchEngineAction_returnsExpectedState() {
        let initialState = createSubject()
                let searchEngineModel = SearchEngineModel(
            name: "Google",
            image: UIImage(named: StandardImageIdentifiers.ExtraSmall.chevronDown)!)

        let newState = ToolbarState.reduce(
            initialState,
            with: SearchEngineSelectionAction(
                windowUUID: self.windowUUID,
                actionType: SearchEngineSelectionActionType.didTapSearchEngine,
                selectedSearchEngine: searchEngineModel
            )
        )

        XCTAssertNotEqual(newState.addressToolbar, initialState.addressToolbar)
        XCTAssertEqual(newState.navigationToolbar, initialState.navigationToolbar)
    }

    func test_urlDidChangeStateAction_returnsExpectedState() {
        let initialState = createSubject()

        let urlDidChangeState = loadWebsiteAction(state: initialState)
        let newState = ToolbarState.reduce(
            urlDidChangeState,
            with: ToolbarAction(
                canGoBack: true,
                canGoForward: false,
                windowUUID: windowUUID,
                actionType: ToolbarActionType.backForwardButtonStateChanged
            )
        )

        XCTAssertTrue(newState.shouldAnimate)
    }

    func test_didClearAlternativeSearchEngineAction_returnsExpectedState() {
        let initialState = createSubject()

        let newState = ToolbarState.reduce(
            initialState,
            with: SearchEngineSelectionAction(
                windowUUID: self.windowUUID,
                actionType: SearchEngineSelectionMiddlewareActionType.didClearAlternativeSearchEngine
            )
        )

        XCTAssertNil(newState.addressToolbar.alternativeSearchEngine)
        XCTAssertEqual(newState.navigationToolbar, initialState.navigationToolbar)
    }

    func test_showToastAction_forShakeToSummarizeNotAvailable_restoresMinimizedAddressBar() {
        let initialState = createSubject()

        let minimizedState = ToolbarState.reduceModern(
            initialState,
            with: ToolbarModernAction.userDidScroll(minimizeAddressBar: true)
        )
        XCTAssertTrue(minimizedState.isAddressBarMinimized)

        let newState = ToolbarState.reduce(
            minimizedState,
            with: GeneralBrowserAction(
                toastType: .shakeToSummarizeNotAvailable,
                windowUUID: windowUUID,
                actionType: GeneralBrowserActionType.showToast
            )
        )

        XCTAssertFalse(newState.isAddressBarMinimized)
    }

    // MARK: - Private
    private func createSubject() -> ToolbarState {
        return ToolbarState(windowUUID: windowUUID)
    }

    private func loadWebsiteAction(state: ToolbarState) -> ToolbarState {
        return ToolbarState.reduce(
            state,
            with: ToolbarAction(
                url: URL(string: "http://mozilla.com"),
                isPrivate: false,
                isShowingNavigationToolbar: true,
                canGoBack: true,
                canGoForward: false,
                lockIconImageName: StandardImageIdentifiers.Small.shieldCheckmarkFill,
                safeListedURLImageName: nil,
                windowUUID: windowUUID,
                actionType: ToolbarActionType.urlDidChange
            )
        )
    }

    // MARK: BusTestUtility

    func setupBus() {
        mockBus = MockBrowserEventBus()
        BusTestUtilityHelper.setupBus(with: mockBus)
    }

    // In order to avoid flaky tests, we should reset the store
    // similar to production
    func resetBus() {
        BusTestUtilityHelper.resetBus()
    }
}
