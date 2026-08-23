// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import XCTest
import Common

@testable import Client

final class HomepageViewControllerTests: XCTestCase, StoreTestUtility {
    let windowUUID: WindowUUID = .XCTestDefaultUUID
    var mockNotificationCenter: MockNotificationCenter?
    var mockThemeManager: MockThemeManager?
    var mockStore: MockStore!
    var mockThrottler: MockThrottler!
    var homepageTabStateStore: HomepageTabStateStore!
    var mockGleanWrapper: MockGleanWrapper!
    var recentTabsProvider: MockRecentTabsProvider!

    override func setUp() async throws {
        try await super.setUp()
        DependencyHelperMock().bootstrapDependencies()
        homepageTabStateStore = HomepageTabStateStore()
        mockGleanWrapper = MockGleanWrapper()
        recentTabsProvider = MockRecentTabsProvider()
        setupStore()
    }

    override func tearDown() async throws {
        homepageTabStateStore = nil
        mockGleanWrapper = nil
        recentTabsProvider = nil
        mockThrottler = nil
        mockNotificationCenter = nil
        mockThemeManager = nil
        DependencyHelperMock().reset()
        resetStore()
        try await super.tearDown()
    }

    // MARK: - Initial State
    func testInitialCreation_hasCorrectContentType() {
        let sut = createSubject()

        XCTAssertEqual(sut.contentType, .homepage)
    }

    func testInitialCreation_hasCorrectWindowUUID() {
        let sut = createSubject()

        XCTAssertEqual(sut.currentWindowUUID, .XCTestDefaultUUID)
    }

    func test_viewDidLoad_setsUpThemingAndNotifications() {
        let sut = createSubject()

        XCTAssertEqual(mockThemeManager?.getCurrentThemeCallCount, 0)
        XCTAssertEqual(mockNotificationCenter?.addPublisherCount, 0)

        sut.loadViewIfNeeded()

        XCTAssertEqual(mockThemeManager?.getCurrentThemeCallCount, 1)
        XCTAssertEqual(mockNotificationCenter?.addPublisherCount, 1)
        XCTAssertEqual(mockNotificationCenter?.observers, [.ThemeDidChange])
    }

    func test_scrollViewDidScroll_updatesStatusBarScrollDelegate() {
        let mockStatusBarScrollDelegate = MockStatusBarScrollDelegate()
        let homepageVC = createSubject(
            statusBarScrollDelegate: mockStatusBarScrollDelegate,
            homepageViewModel: makeViewModelWithWallpaperImage()
        )
        let scrollView = UIScrollView()

        mockStatusBarScrollDelegate.savedScrollView = nil

        homepageVC.scrollViewDidScroll(scrollView)

        XCTAssertEqual(mockStatusBarScrollDelegate.savedScrollView, scrollView)
    }

    func test_scrollToTop_updatesStatusBarScrollDelegate_andSetsCollectionViewOffset() {
        let mockStatusBarScrollDelegate = MockStatusBarScrollDelegate()
        let homepageVC = createSubject(
            statusBarScrollDelegate: mockStatusBarScrollDelegate,
            homepageViewModel: makeViewModelWithWallpaperImage()
        )

        guard let collectionView = homepageVC.view.subviews.first(where: {
            $0 is UICollectionView
        }) as? UICollectionView else {
            XCTFail()
            return
        }

        homepageVC.scrollToTop()

        XCTAssertEqual(collectionView.contentOffset, CGPoint(x: 0, y: -collectionView.adjustedContentInset.top))
        XCTAssertEqual(mockStatusBarScrollDelegate.savedScrollView, collectionView)
    }

    func test_scrollViewDidScroll_withoutScrollableContent_doesNotTriggerGeneralBrowserMiddlewareAction() throws {
        let mockStatusBarScrollDelegate = MockStatusBarScrollDelegate()
        let homepageVC = createSubject(statusBarScrollDelegate: mockStatusBarScrollDelegate)
        let scrollView = UIScrollView()
        scrollView.contentSize = CGSize(width: 320, height: 500)
        scrollView.frame = CGRect(x: 0, y: 0, width: 320, height: 600)
        scrollView.contentOffset.y = 10

        homepageVC.scrollViewDidScroll(scrollView)

        let actionCalled = mockStore.dispatchedActions.first(where: {
            $0 is GeneralBrowserMiddlewareAction
        })
        XCTAssertNil(actionCalled)
    }

    func test_scrollViewDidScroll_withScrollableContent_TriggersGeneralBrowserMiddlewareAction() throws {
        let mockStatusBarScrollDelegate = MockStatusBarScrollDelegate()
        let homepageVC = createSubject(statusBarScrollDelegate: mockStatusBarScrollDelegate)
        let scrollView = UIScrollView()
        scrollView.contentSize = CGSize(width: 320, height: 900)
        scrollView.frame = CGRect(x: 0, y: 0, width: 320, height: 600)
        scrollView.contentOffset.y = 10

        homepageVC.scrollViewDidScroll(scrollView)

        let actionCalled = try XCTUnwrap(
            mockStore.dispatchedActions.first(where: {
                $0 is GeneralBrowserMiddlewareAction
            }) as? GeneralBrowserMiddlewareAction
        )
        let actionType = try XCTUnwrap(actionCalled.actionType as? GeneralBrowserMiddlewareActionType)
        XCTAssertEqual(actionType, GeneralBrowserMiddlewareActionType.websiteDidScroll)
    }

    func test_scrollViewWillBeginDragging_triggersToolbarAction() throws {
        let homepageVC = createSubject()
        let scrollView = UIScrollView()
        scrollView.contentOffset.y = 10
        setupNimbusToolbarRefactorTesting(isEnabled: true)

        homepageVC.scrollViewWillBeginDragging(scrollView)

        let actionCalled = try XCTUnwrap(
            mockStore.dispatchedActions.first(where: {
                $0 is ToolbarAction
            }) as? ToolbarAction
        )
        let actionType = try XCTUnwrap(actionCalled.actionType as? ToolbarActionType)
        XCTAssertEqual(actionType, ToolbarActionType.cancelEditOnHomepage)
    }

    /// The lifecycle dispatches are gone; the controller drives the view model directly.
    func test_viewWillAppear_refreshesTheJumpBackInSection() {
        let viewModel = makeViewModel()
        let subject = createSubject(homepageViewModel: viewModel)

        subject.viewWillAppear(false)

        XCTAssertFalse(recentTabsProvider.requestedWindowUUIDs.isEmpty)
    }

    func test_viewDidAppear_recordsTheHomepageImpression() {
        let subject = createSubject()

        subject.viewDidAppear(false)

        XCTAssertEqual(mockGleanWrapper.recordEventNoExtraCalled, 1)
    }

    /// The tiles-per-row recalculation is a direct call on the section view model now rather than
    /// a HomepageActionType.viewDidLayoutSubviews dispatch, so the action type is gone.
    func test_viewDidLayoutSubviews_updatesTheTilesPerRow() {
        let viewModel = makeViewModel()
        let subject = createSubject(homepageViewModel: viewModel)
        subject.loadViewIfNeeded()
        viewModel.topSites.setNumberOfTilesPerRow(1)

        subject.view.layoutIfNeeded()

        XCTAssertGreaterThan(viewModel.topSites.state.numberOfTilesPerRow, 1)
    }

    func test_viewDidAppear_withPopulatedDataSource_recordsSectionImpressions() async {
        let viewModel = makeViewModel()
        let subject = createSubject(homepageViewModel: viewModel)

        // Load the view, then populate the sections through the view model so the collection view
        // has visible content, then lay out so impressions can be tracked.
        subject.loadViewIfNeeded()
        await populateSections(viewModel)
        subject.view.layoutIfNeeded()

        subject.viewDidAppear(false)

        XCTAssertTrue(mockThrottler.didCallThrottle)
        XCTAssertGreaterThan(mockGleanWrapper.incrementLabeledCounterCalled, 0)
    }

    func test_scrollViewDidEndDecelerating_recordsSectionImpressions() async {
        let viewModel = makeViewModel()
        let subject = createSubject(homepageViewModel: viewModel)

        // Load the view, then populate the sections through the view model so the collection view
        // has visible content, then lay out so impressions can be tracked.
        subject.loadViewIfNeeded()
        await populateSections(viewModel)
        subject.view.layoutIfNeeded()

        subject.scrollViewDidEndDecelerating(UIScrollView())

        XCTAssertTrue(mockThrottler.didCallThrottle)
        XCTAssertGreaterThan(mockGleanWrapper.incrementLabeledCounterCalled, 0)
    }

    /// FXIOS-11523 - the impression reset arrives from the bus now rather than through a
    /// `shouldTriggerImpression` flag on a screen state.
    func test_tabChangedToHomepage_withPopulatedDataSource_retracksImpressions() async {
        let viewModel = makeViewModel()
        let subject = createSubject(homepageViewModel: viewModel)

        // Load the view, populate the sections through the view model, then lay out so the
        // collection view has visible content.
        subject.loadViewIfNeeded()
        await populateSections(viewModel)
        subject.view.layoutIfNeeded()

        viewModel.didSelectTabChangeToHomepage()

        XCTAssertTrue(mockThrottler.didCallThrottle)
    }

    func test_restoreContentOffset_withStoredOffset_setsCollectionViewOffset() {
        let tabManager = HomepageRestoreContentOffsetTabManager()
        let tab = MockTab(profile: MockProfile(), windowUUID: .XCTestDefaultUUID)
        tabManager.tabs = [tab]
        tabManager.selectedTab = tab
        homepageTabStateStore.updateState(for: tab.tabUUID) { $0.scrollOffsetY = 180 }
        let subject = createSubject(tabManager: tabManager)

        subject.loadViewIfNeeded()

        guard let collectionView = subject.view.subviews.first(where: {
            $0 is UICollectionView
        }) as? UICollectionView else {
            XCTFail()
            return
        }

        collectionView.contentOffset = CGPoint(x: 0, y: 0)

        subject.restoreVerticalScrollOffset()

        XCTAssertEqual(collectionView.contentOffset.y, 180)
    }

    func test_restoreContentOffset_withoutStoredOffset_scrollsToTop() {
        let tabManager = HomepageRestoreContentOffsetTabManager()
        let tab = MockTab(profile: MockProfile(), windowUUID: .XCTestDefaultUUID)
        tabManager.tabs = [tab]
        tabManager.selectedTab = tab
        let subject = createSubject(tabManager: tabManager)

        subject.loadViewIfNeeded()

        guard let collectionView = subject.view.subviews.first(where: {
            $0 is UICollectionView
        }) as? UICollectionView else {
            XCTFail()
            return
        }

        collectionView.contentOffset = CGPoint(x: 0, y: 75)

        subject.restoreVerticalScrollOffset()

        XCTAssertEqual(collectionView.contentOffset, CGPoint(x: 0, y: -collectionView.adjustedContentInset.top))
    }

    func test_restoreContentOffset_whenNotForcedAndSameTab_doesNotRestoreStoredOffset() {
        let tabManager = HomepageRestoreContentOffsetTabManager()
        let tab = MockTab(profile: MockProfile(), windowUUID: .XCTestDefaultUUID)
        tabManager.tabs = [tab]
        tabManager.selectedTab = tab
        homepageTabStateStore.updateState(for: tab.tabUUID) { $0.scrollOffsetY = 180 }
        let subject = createSubject(tabManager: tabManager)

        subject.loadViewIfNeeded()
        subject.viewWillAppear(false)

        guard let collectionView = subject.view.subviews.first(where: {
            $0 is UICollectionView
        }) as? UICollectionView else {
            XCTFail()
            return
        }

        collectionView.contentOffset = CGPoint(x: 0, y: 75)

        subject.restoreVerticalScrollOffset(force: false)

        XCTAssertEqual(collectionView.contentOffset.y, 75)
    }

    func test_viewDidDisappear_savesVerticalScrollOffset() {
        let tabManager = HomepageRestoreContentOffsetTabManager()
        let tab = MockTab(profile: MockProfile(), windowUUID: .XCTestDefaultUUID)
        tabManager.tabs = [tab]
        tabManager.selectedTab = tab
        let subject = createSubject(tabManager: tabManager)

        subject.loadViewIfNeeded()
        subject.viewWillAppear(false)

        guard let collectionView = subject.view.subviews.first(where: {
            $0 is UICollectionView
        }) as? UICollectionView else {
            XCTFail()
            return
        }

        collectionView.contentOffset = CGPoint(x: 0, y: 140)

        subject.viewWillDisappear(false)

        XCTAssertEqual(homepageTabStateStore.state(for: tab.tabUUID).scrollOffsetY, 140)
    }

    func test_stopScrollingAndSaveVerticalScrollOffset_savesCurrentOffset() {
        let tabManager = HomepageRestoreContentOffsetTabManager()
        let tab = MockTab(profile: MockProfile(), windowUUID: .XCTestDefaultUUID)
        tabManager.tabs = [tab]
        tabManager.selectedTab = tab
        let subject = createSubject(tabManager: tabManager)

        subject.loadViewIfNeeded()
        subject.viewWillAppear(false)

        guard let collectionView = subject.view.subviews.first(where: {
            $0 is UICollectionView
        }) as? UICollectionView else {
            XCTFail()
            return
        }

        collectionView.contentOffset = CGPoint(x: 0, y: 140)

        subject.stopScrollingAndSaveVerticalScrollOffset()

        XCTAssertEqual(homepageTabStateStore.state(for: tab.tabUUID).scrollOffsetY, 140)
    }

    func test_scrollViewDidEndDragging_savesVerticalScrollOffset() {
        let tabManager = HomepageRestoreContentOffsetTabManager()
        let tab = MockTab(profile: MockProfile(), windowUUID: .XCTestDefaultUUID)
        tabManager.tabs = [tab]
        tabManager.selectedTab = tab
        let subject = createSubject(tabManager: tabManager)

        subject.loadViewIfNeeded()
        subject.viewWillAppear(false)

        guard let collectionView = subject.view.subviews.first(where: {
            $0 is UICollectionView
        }) as? UICollectionView else {
            XCTFail()
            return
        }

        collectionView.contentOffset = CGPoint(x: 0, y: 140)

        subject.scrollViewDidEndDragging(UIScrollView(), willDecelerate: false)

        XCTAssertEqual(homepageTabStateStore.state(for: tab.tabUUID).scrollOffsetY, 140)
    }

    func test_scrollViewDidEndDecelerating_savesVerticalScrollOffset() {
        let tabManager = HomepageRestoreContentOffsetTabManager()
        let tab = MockTab(profile: MockProfile(), windowUUID: .XCTestDefaultUUID)
        tabManager.tabs = [tab]
        tabManager.selectedTab = tab
        let subject = createSubject(tabManager: tabManager)

        subject.loadViewIfNeeded()
        subject.viewWillAppear(false)

        guard let collectionView = subject.view.subviews.first(where: {
            $0 is UICollectionView
        }) as? UICollectionView else {
            XCTFail()
            return
        }

        collectionView.contentOffset = CGPoint(x: 0, y: 140)

        subject.scrollViewDidEndDecelerating(UIScrollView())

        XCTAssertEqual(homepageTabStateStore.state(for: tab.tabUUID).scrollOffsetY, 140)
    }

    /// BrowserViewController hands the geometry over directly now instead of dispatching.
    func test_updateAvailableHeights_updatesWallpaperHeightConstraint() throws {
        let subject = createSubject()
        subject.loadViewIfNeeded()

        subject.updateAvailableHeights(content: 100, wallpaper: 300)

        let wallpaperView = try XCTUnwrap(
            subject.view.subviews.first(where: { $0 is WallpaperBackgroundView }) as? WallpaperBackgroundView
        )
        let wallpaperHeightConstraint = try XCTUnwrap(
            wallpaperView.constraints.first(where: { $0.firstAttribute == .height && $0.firstItem === wallpaperView })
        )
        XCTAssertEqual(wallpaperHeightConstraint.constant, 300)
    }

    /// A homepage whose wallpaper reports an image, which is what gates the status-bar overlay.
    private func makeViewModelWithWallpaperImage() -> HomepageViewModel {
        return HomepageViewModel(
            windowUUID: .XCTestDefaultUUID,
            wallpaper: WallpaperViewModel(
                wallpaperManager: WallpaperManagerMock(),
                initialState: WallpaperState(
                    wallpaperConfiguration: WallpaperConfiguration(hasImage: true)
                )
            ),
            topSites: makeTopSitesViewModel(),
            topSitesService: makeTopSitesService()
        )
    }

    private func makeTopSitesService() -> TopSitesService {
        return TopSitesService(topSitesManager: MockTopSitesManager())
    }

    private func makeTopSitesViewModel() -> TopSitesSectionViewModel {
        return TopSitesSectionViewModel(windowUUID: .XCTestDefaultUUID,
                                        profile: MockProfile(),
                                        topSitesService: makeTopSitesService(),
                                        featureFlagsProvider: MockNimbusFeatureFlags())
    }

    private func createSubject(
        tabManager: TabManager = MockTabManager(),
        statusBarScrollDelegate: StatusBarScrollDelegate? = nil,
        homepageViewModel: HomepageViewModel? = nil
    ) -> HomepageViewController {
        let notificationCenter = MockNotificationCenter()
        let themeManager = MockThemeManager()
        let mockOverlayManager = MockOverlayModeManager()
        let throttler = MockThrottler()
        mockNotificationCenter = notificationCenter
        mockThemeManager = themeManager
        mockThrottler = throttler
        let homepageViewController = HomepageViewController(
            windowUUID: .XCTestDefaultUUID,
            themeManager: themeManager,
            tabManager: tabManager,
            homepageTabStateStore: homepageTabStateStore,
            overlayManager: mockOverlayManager,
            statusBarScrollDelegate: statusBarScrollDelegate,
            toastContainer: UIView(),
            notificationCenter: notificationCenter,
            throttler: mockThrottler,
            // Never the production default: it resolves the top-sites service and the feature
            // flag provider out of AppContainer, which the mock helper tears down between tests.
            homepageViewModel: homepageViewModel ?? makeViewModel()
        )
        trackForMemoryLeaks(homepageViewController)
        return homepageViewController
    }

    func setupStore() {
        mockStore = MockStore()
        StoreTestUtilityHelper.setupStore(with: mockStore)
    }

    func resetStore() {
        StoreTestUtilityHelper.resetStore()
    }

    private func setupNimbusToolbarRefactorTesting(isEnabled: Bool) {
        FxNimbus.shared.features.toolbarRefactorFeature.with { _, _ in
            return ToolbarRefactorFeature()
        }
    }

    private func getCollectionView(from subject: HomepageViewController) throws -> UICollectionView {
        return try XCTUnwrap(subject.view.subviews.first(where: { $0 is UICollectionView }) as? UICollectionView)
    }

    private func getPocketSectionIndex(from collectionView: UICollectionView) throws -> Int {
        let dataSource = try XCTUnwrap(collectionView.dataSource as? HomepageDiffableDataSource)
        return try XCTUnwrap(dataSource.snapshot().sectionIdentifiers.firstIndex(where: { section in
            if case .pocket = section { return true }
            return false
        }))
    }

    /// Merino moved off the store, so the stories that make sections visible come from the view
    /// model. Fetching after the view controller has bound to it is what triggers the snapshot,
    /// which `newState` used to do when the stories arrived in the state.
    /// The header is owned by the view model now rather than read from the store, so it measures
    /// for real here rather than collapsing to zero; the quick-answers store is stubbed off so
    /// TipKit stays out of these tests.
    private func makeViewModel() -> HomepageViewModel {
        return HomepageViewModel(
            windowUUID: .XCTestDefaultUUID,
            merino: MerinoSectionViewModel(merinoManager: MockMerinoManager()),
            header: HeaderViewModel(windowUUID: .XCTestDefaultUUID,
                                    quickAnswersStore: MockQuickAnswersStore()),
            wallpaper: WallpaperViewModel(wallpaperManager: WallpaperManagerMock(),
                                          initialState: WallpaperState()),
            topSites: makeTopSitesViewModel(),
            jumpBackIn: JumpBackInSectionViewModel(windowUUID: .XCTestDefaultUUID,
                                                   recentTabsProvider: recentTabsProvider,
                                                   syncedTabProvider: MockSyncedTabProvider(),
                                                   bus: nil),
            topSitesService: makeTopSitesService(),
            telemetry: HomepageTelemetry(gleanWrapper: mockGleanWrapper),
            termsOfUseTelemetry: TermsOfUseTelemetry(gleanWrapper: mockGleanWrapper),
            bus: nil
        )
    }

    private func populateSections(_ viewModel: HomepageViewModel) async {
        viewModel.merino.refreshStories()
        await waitUntil { viewModel.merino.hasMerinoResponseContent }
    }
}

private final class HomepageRestoreContentOffsetTabManager: MockTabManager {
    override func getTabForUUID(uuid: TabUUID) -> Tab? {
        return tabs.first(where: { $0.tabUUID == uuid })
    }
}
