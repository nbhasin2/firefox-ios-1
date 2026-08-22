// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import XCTest
import Storage
import MozillaAppServices

@testable import Client

@MainActor
final class HomepageDiffableDataSourceTests: XCTestCase {
    var collectionView: UICollectionView?
    var diffableDataSource: HomepageDiffableDataSource?
    private var profile: MockProfile!
    private var mockNimbusLayer: MockNimbusFeatureFlagLayer!
    private var privacyNoticeHelper: MockPrivacyNoticeHelper!

    override func setUp() async throws {
        try await super.setUp()
        profile = MockProfile()
        mockNimbusLayer = MockNimbusFeatureFlagLayer()
        privacyNoticeHelper = MockPrivacyNoticeHelper()
        let featureFlagProvider = FeatureFlagsProvider(prefs: profile.prefs, backendLayer: mockNimbusLayer)
        let userFeaturePreferences = UserFeaturePreferenceManager(prefs: profile.prefs, backendLayer: mockNimbusLayer)

        DependencyHelperMock().bootstrapDependencies(
            injectedProfile: profile,
            injectedFeatureFlagProvider: featureFlagProvider,
            injectedUserFeaturePreferences: userFeaturePreferences
        )

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let collectionView = try XCTUnwrap(collectionView)
        diffableDataSource = HomepageDiffableDataSource(
            collectionView: collectionView
        ) { (collectionView, indexPath, item) -> UICollectionViewCell? in
            return UICollectionViewCell()
        }
    }

    override func tearDown() async throws {
        diffableDataSource = nil
        collectionView = nil
        profile = nil
        mockNimbusLayer = nil
        DependencyHelperMock().reset()
        try await super.tearDown()
    }

    // MARK: - applyInitialSnapshot
    func test_updateSnapshot_hasCorrectData() throws {
        let dataSource = try XCTUnwrap(diffableDataSource)

        dataSource.updateSnapshot(
            viewModel: makeViewModel(),
            jumpBackInDisplayConfig: mockSectionConfig
        )

        let snapshot = dataSource.snapshot()
        XCTAssertEqual(snapshot.numberOfSections, 2)
        XCTAssertEqual(snapshot.sectionIdentifiers, [.header, .spacer])
        XCTAssertEqual(snapshot.numberOfItems(inSection: .header), 1)
        XCTAssertEqual(snapshot.numberOfItems(inSection: .spacer), 1)
    }

    @MainActor
    func test_updateSnapshot_withColorValueOnState() throws {
        let dataSource = try XCTUnwrap(diffableDataSource)
        let wallpaperConfig = WallpaperConfiguration(
            landscapeImage: nil,
            portraitImage: nil,
            textColor: .systemCyan,
            cardColor: .black,
            logoTextColor: .blue
        )

        let viewModel = makeViewModel(
            merinoResponse: MerinoStoryResponse(stories: createStories()),
            wallpaperConfiguration: wallpaperConfig
        )
        dataSource.updateSnapshot(
            viewModel: viewModel,
            jumpBackInDisplayConfig: mockSectionConfig
        )

        let snapshot = dataSource.snapshot()
        XCTAssertEqual(
            snapshot.itemIdentifiers(inSection: .header).first,
            HomepageItem.header(viewModel.header.state, .blue, false)
        )
        XCTAssertEqual(snapshot.numberOfItems(inSection: .pocket(.systemCyan)), 20)
        let expectedSections: [HomepageSection] = [
            .header,
            .spacer,
            .pocket(.systemCyan)
        ]
        XCTAssertEqual(snapshot.sectionIdentifiers, expectedSections)
    }

    @MainActor
    func test_updateSnapshot_withOverflowingTopSites_returnTopSitesWithHeader() throws {
        let dataSource = try XCTUnwrap(diffableDataSource)
        let numberOfTilesPerRow = TopSitesSectionLayoutProvider.UX.minCards

        dataSource.updateSnapshot(viewModel: makeViewModel(topSites: topSitesState(
                                      sites: createSites(),
                                      numberOfRows: 2,
                                      shouldShowSectionHeader: true
                                  )),
                                  jumpBackInDisplayConfig: mockSectionConfig)

        let snapshot = dataSource.snapshot()
        let displayedTopSitesCount = 2 * numberOfTilesPerRow
        XCTAssertEqual(snapshot.numberOfItems(inSection: .topSites(nil, numberOfTilesPerRow, true)), displayedTopSitesCount)
        let expectedSections: [HomepageSection] = [
            .header,
            .topSites(nil, numberOfTilesPerRow, true),
            .spacer
        ]
        XCTAssertEqual(snapshot.sectionIdentifiers, expectedSections)
    }

    @MainActor
    func test_updateSnapshot_withTopSitesWithinVisibleCount_returnTopSitesWithoutHeader() throws {
        let dataSource = try XCTUnwrap(diffableDataSource)
        let numberOfRows = 2
        let numberOfTilesPerRow = TopSitesSectionLayoutProvider.UX.minCards
        let topSitesCount = numberOfRows * numberOfTilesPerRow

        dataSource.updateSnapshot(viewModel: makeViewModel(topSites: topSitesState(
                                      sites: createSites(count: topSitesCount),
                                      numberOfRows: numberOfRows
                                  )),
                                  jumpBackInDisplayConfig: mockSectionConfig)

        let snapshot = dataSource.snapshot()
        XCTAssertEqual(snapshot.numberOfItems(inSection: .topSites(nil, numberOfTilesPerRow, false)), topSitesCount)
        let expectedSections: [HomepageSection] = [
            .header,
            .topSites(nil, numberOfTilesPerRow, false),
            .spacer
        ]
        XCTAssertEqual(snapshot.sectionIdentifiers, expectedSections)
    }

    @MainActor
    func test_updateSnapshot_withAddShortcutTileFlagEnabled_appendsTileWhenThereIsRoom() throws {
        let dataSource = try XCTUnwrap(diffableDataSource)
        let numberOfTilesPerRow = TopSitesSectionLayoutProvider.UX.minCards

        dataSource.updateSnapshot(viewModel: makeViewModel(topSites: topSitesState(
                                      sites: createSites(count: numberOfTilesPerRow - 1),
                                      numberOfRows: 1,
                                      shouldShowAddShortcutTile: true
                                  )),
                                  jumpBackInDisplayConfig: mockSectionConfig)

        let section = HomepageSection.topSites(nil, numberOfTilesPerRow, false)
        let items = dataSource.snapshot().itemIdentifiers(inSection: section)
        XCTAssertEqual(items.count, numberOfTilesPerRow)
        let expectedTopSiteTitles = (0..<max(numberOfTilesPerRow - 1, 0)).map { "Title \($0)" }
        XCTAssertEqual(topSiteTitles(from: items), expectedTopSiteTitles)
        guard case .addShortcutTile = items.last else {
            return XCTFail("Expected Add Shortcut tile to be the last shortcut item")
        }
    }

    @MainActor
    func test_updateSnapshot_withAddShortcutTileFlagEnabled_displacesTileWhenShortcutsFillVisibleSlots() throws {
        let dataSource = try XCTUnwrap(diffableDataSource)
        let numberOfTilesPerRow = TopSitesSectionLayoutProvider.UX.minCards

        dataSource.updateSnapshot(viewModel: makeViewModel(topSites: topSitesState(
                                      sites: createSites(count: numberOfTilesPerRow),
                                      numberOfRows: 1,
                                      shouldShowSectionHeader: true,
                                      shouldShowAddShortcutTile: true
                                  )),
                                  jumpBackInDisplayConfig: mockSectionConfig)

        let section = HomepageSection.topSites(nil, numberOfTilesPerRow, true)
        let items = dataSource.snapshot().itemIdentifiers(inSection: section)
        XCTAssertEqual(items.count, numberOfTilesPerRow)
        XCTAssertEqual(topSiteTitles(from: items), (0..<numberOfTilesPerRow).map { "Title \($0)" })
        XCTAssertFalse(items.contains { item in
            guard case .addShortcutTile = item else { return false }
            return true
        })
    }

    @MainActor
    func test_updateSnapshot_withAddShortcutTileFlagEnabledAndNoTopSites_showsAddShortcutTile() throws {
        let dataSource = try XCTUnwrap(diffableDataSource)

        dataSource.updateSnapshot(viewModel: makeViewModel(topSites: topSitesState(
                                      sites: [],
                                      numberOfRows: 1,
                                      shouldShowAddShortcutTile: true
                                  )),
                                  jumpBackInDisplayConfig: mockSectionConfig)

        let section = HomepageSection.topSites(nil, TopSitesSectionLayoutProvider.UX.minCards, false)
        let items = dataSource.snapshot().itemIdentifiers(inSection: section)
        XCTAssertEqual(items.count, 1)
        guard case .addShortcutTile = items.first else {
            return XCTFail("Expected Add Shortcut tile to be the only shortcut item")
        }
    }

    @MainActor
    func test_updateSnapshot_withValidState_returnPocketStories() throws {
        let dataSource = try XCTUnwrap(diffableDataSource)

        dataSource.updateSnapshot(
            viewModel: makeViewModel(merinoResponse: MerinoStoryResponse(stories: createStories())),
            jumpBackInDisplayConfig: mockSectionConfig
        )

        let snapshot = dataSource.snapshot()
        XCTAssertEqual(snapshot.numberOfItems(inSection: .pocket(nil)), 20)
        let expectedSections: [HomepageSection] = [
            .header,
            .spacer,
            .pocket(nil)
        ]
        XCTAssertEqual(snapshot.sectionIdentifiers, expectedSections)
    }

    @MainActor
    func test_updateSnapshot_withCategorizedStoriesAndNoSelection_returnsFlattenedStories() throws {
        let dataSource = try XCTUnwrap(diffableDataSource)

        dataSource.updateSnapshot(
            viewModel: makeViewModel(merinoResponse: MerinoStoryResponse(categories: createCategories())),
            jumpBackInDisplayConfig: mockSectionConfig
        )

        let snapshot = dataSource.snapshot()
        let items = snapshot.itemIdentifiers(inSection: .pocket(nil))

        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(merinoTitles(from: items), ["science 1", "science 2", "technology 1"])
    }

    @MainActor
    func test_updateSnapshot_withCategorizedStoriesAndSelectedCategory_returnsSelectedCategoryStories() throws {
        let dataSource = try XCTUnwrap(diffableDataSource)

        dataSource.updateSnapshot(
            viewModel: makeViewModel(merinoResponse: MerinoStoryResponse(categories: createCategories())),
            selectedNewsfeedCategoryID: "technology",
            jumpBackInDisplayConfig: mockSectionConfig
        )

        let snapshot = dataSource.snapshot()
        let items = snapshot.itemIdentifiers(inSection: .pocket(nil))

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(merinoTitles(from: items), ["technology 1"])
    }

    @MainActor
    func test_updateSnapshot_withCategorizedStoriesAndMissingSelectedCategory_omitsPocketSection() throws {
        let dataSource = try XCTUnwrap(diffableDataSource)

        dataSource.updateSnapshot(
            viewModel: makeViewModel(merinoResponse: MerinoStoryResponse(categories: createCategories())),
            selectedNewsfeedCategoryID: "missing-category",
            jumpBackInDisplayConfig: mockSectionConfig
        )

        let snapshot = dataSource.snapshot()

        XCTAssertFalse(snapshot.sectionIdentifiers.contains(.pocket(nil)))
    }

    @MainActor
    func test_updateSnapshot_withValidState_returnMessageCard() throws {
        let dataSource = try XCTUnwrap(diffableDataSource)
        let configuration = MessageCardConfiguration(
            title: "Example Title",
            description: "Example Description",
            buttonLabel: "Example Button"
        )

        let viewModel = makeViewModel(messageCardConfiguration: configuration)
        dataSource.updateSnapshot(viewModel: viewModel,
                                  jumpBackInDisplayConfig: mockSectionConfig)

        let snapshot = dataSource.snapshot()
        XCTAssertEqual(snapshot.numberOfItems(inSection: .messageCard), 1)
        XCTAssertEqual(snapshot.itemIdentifiers(inSection: .messageCard).first, HomepageItem.messageCard(configuration))
        let expectedSections: [HomepageSection] = [
            .header,
            .messageCard,
            .spacer
        ]
        XCTAssertEqual(snapshot.sectionIdentifiers, expectedSections)
    }

    @MainActor
    func test_updateSnapshot_withValidState_returnBookmarks() throws {
        let dataSource = try XCTUnwrap(diffableDataSource)

        let bookmark = BookmarkConfiguration(
            site: Site.createBasicSite(url: "www.mozilla.org", title: "Title 1", isBookmarked: true)
        )
        dataSource.updateSnapshot(
            viewModel: makeViewModel(bookmarks: [bookmark]),
            jumpBackInDisplayConfig: mockSectionConfig
        )

        let snapshot = dataSource.snapshot()
        XCTAssertEqual(snapshot.numberOfItems(inSection: .bookmarks(nil)), 1)
        let expectedSections: [HomepageSection] = [
            .header,
            .bookmarks(nil),
            .spacer
        ]
        XCTAssertEqual(snapshot.sectionIdentifiers, expectedSections)
    }

    @MainActor
    func test_updateSnapshot_withValidState_returnJumpBackInSection() throws {
        let dataSource = try XCTUnwrap(diffableDataSource)

        dataSource.updateSnapshot(
            viewModel: makeViewModel(jumpBackInTabs: [createTab(urlString: "www.mozilla.org")]),
            jumpBackInDisplayConfig: mockSectionConfig
        )

        let snapshot = dataSource.snapshot()
        XCTAssertEqual(snapshot.numberOfItems(inSection: .jumpBackIn(nil, mockSectionConfig)), 1)
        let expectedSections: [HomepageSection] = [
            .header,
            .jumpBackIn(nil, mockSectionConfig),
            .spacer
        ]
        XCTAssertEqual(snapshot.sectionIdentifiers, expectedSections)
    }

    @MainActor
    func test_updateSnapshot_withTrackerBlockerModuleEnabled_returnTrackerBlockerModuleSection() throws {
        setFeatureFlag(.homepageTrackerBlockerModule, isEnabled: true)
        let dataSource = try XCTUnwrap(diffableDataSource)

        dataSource.updateSnapshot(viewModel: makeViewModel(trackerBlockerEnabled: true),
                                  jumpBackInDisplayConfig: mockSectionConfig)

        let snapshot = dataSource.snapshot()
        XCTAssertEqual(snapshot.numberOfItems(inSection: .trackerBlockerModule), 1)
        XCTAssertEqual(snapshot.itemIdentifiers(inSection: .trackerBlockerModule).first, .trackerBlockerModule(0))
        let expectedSections: [HomepageSection] = [
            .header,
            .trackerBlockerModule,
            .spacer
        ]
        XCTAssertEqual(snapshot.sectionIdentifiers, expectedSections)
    }

    @MainActor
    func test_updateSnapshot_withShortcutsTrackerBlockerAndJumpBackIn_ordersTrackerBlockerAfterShortcuts() throws {
        setFeatureFlag(.homepageTrackerBlockerModule, isEnabled: true)
        let dataSource = try XCTUnwrap(diffableDataSource)

        dataSource.updateSnapshot(viewModel: makeViewModel(
                                      trackerBlockerEnabled: true,
                                      topSites: topSitesState(sites: createSites(),
                                                              numberOfRows: 2,
                                                              shouldShowSectionHeader: true),
                                      jumpBackInTabs: [createTab(urlString: "www.mozilla.org")]
                                  ),
                                  jumpBackInDisplayConfig: mockSectionConfig)

        let expectedSections: [HomepageSection] = [
            .header,
            .topSites(nil, TopSitesSectionLayoutProvider.UX.minCards, true),
            .trackerBlockerModule,
            .jumpBackIn(nil, mockSectionConfig),
            .spacer
        ]
        XCTAssertEqual(dataSource.snapshot().sectionIdentifiers, expectedSections)
    }

    @MainActor
    func test_updateSnapshot_withValidState_returnsPrivacyNoticeSection() throws {
        let dataSource = try XCTUnwrap(diffableDataSource)

        let viewModel = makeViewModel()
        privacyNoticeHelper.shouldShowResult = true
        viewModel.configurePrivacyNoticeIfNeeded()

        dataSource.updateSnapshot(viewModel: viewModel, jumpBackInDisplayConfig: mockSectionConfig)
        let snapshot = dataSource.snapshot()
        let expectedSections: [HomepageSection] = [
            .header,
            .privacyNotice,
            .spacer
        ]
        XCTAssertEqual(snapshot.sectionIdentifiers, expectedSections)
    }

    // MARK: - telemetryItemType
    func test_telemetryItemType_withQuickAnswersButtonShown_returnsQuickAnswersEntryPoint() {
        let item = HomepageItem.header(headerState(showQuickAnswersButton: true), nil, false)

        XCTAssertEqual(item.telemetryItemType, .quickAnswersEntryPoint)
    }

    func test_telemetryItemType_withQuickAnswersButtonHidden_returnsNil() {
        let item = HomepageItem.header(headerState(showQuickAnswersButton: false), nil, false)

        XCTAssertNil(item.telemetryItemType)
    }

    private func headerState(showQuickAnswersButton: Bool) -> HeaderState {
        let quickAnswersStore = MockQuickAnswersStore()
        quickAnswersStore.isQuickAnswersEnabled = showQuickAnswersButton
        return HeaderState(windowUUID: .XCTestDefaultUUID, quickAnswersStore: quickAnswersStore)
    }

    /// Sections that have migrated read from the view model; a seeded message card lets the data
    /// source render one without going through the store.
    private func makeViewModel(messageCardConfiguration: MessageCardConfiguration? = nil,
                               trackerBlockerEnabled: Bool = false,
                               merinoResponse: MerinoStoryResponse? = nil,
                               bookmarks: [BookmarkConfiguration] = [],
                               wallpaperConfiguration: WallpaperConfiguration? = nil,
                               topSites: TopSitesSectionState? = nil,
                               jumpBackInTabs: [Tab] = []) -> HomepageViewModel {
        let messageCard = MessageCardViewModel(
            windowUUID: .XCTestDefaultUUID,
            messagingManager: MockGleanPlumbMessageManagerProtocol(),
            initialConfiguration: messageCardConfiguration
        )
        let viewModel = HomepageViewModel(
            windowUUID: .XCTestDefaultUUID,
            messageCard: messageCard,
            bookmarks: BookmarksSectionViewModel(bookmarksHandler: MockBookmarksHandler(),
                                                 initialBookmarks: bookmarks),
            merino: MerinoSectionViewModel(merinoManager: MockMerinoManager(),
                                           initialResponse: merinoResponse),
            // Defaults to an empty configuration rather than whatever the mock manager reports,
            // so the section colours stay nil unless a test asks for a wallpaper.
            wallpaper: WallpaperViewModel(
                wallpaperManager: WallpaperManagerMock(),
                initialState: WallpaperState(
                    wallpaperConfiguration: wallpaperConfiguration ?? WallpaperConfiguration()
                )
            ),
            topSites: TopSitesSectionViewModel(
                windowUUID: .XCTestDefaultUUID,
                profile: MockProfile(),
                topSitesService: TopSitesService(topSitesManager: MockTopSitesManager(),
                                                 featureFlagsProvider: MockNimbusFeatureFlags()),
                featureFlagsProvider: MockNimbusFeatureFlags(),
                initialState: topSites ?? TopSitesSectionState(
                    topSitesData: [],
                    numberOfRows: 0,
                    numberOfTilesPerRow: TopSitesSectionLayoutProvider.UX.minCards,
                    shouldShowSection: false,
                    shouldShowSectionHeader: false,
                    shouldShowAddShortcutTile: false
                )
            ),
            jumpBackIn: JumpBackInSectionViewModel(
                windowUUID: .XCTestDefaultUUID,
                recentTabsProvider: StubRecentTabsProvider(tabs: jumpBackInTabs),
                syncedTabProvider: StubSyncedTabProvider(),
                bus: nil,
                initialState: JumpBackInSectionState(
                    jumpBackInTabs: [],
                    mostRecentSyncedTab: nil,
                    shouldShowSection: !jumpBackInTabs.isEmpty
                )
            ),
            privacyNoticeHelper: privacyNoticeHelper,
            bus: nil
        )
        if !jumpBackInTabs.isEmpty {
            viewModel.jumpBackIn.refreshLocalTabs()
        }
        if trackerBlockerEnabled {
            viewModel.trackerBlockerModule.setSectionEnabled(true)
        }
        // The bookmarks section is off by default; seeding bookmarks means the test wants it shown.
        if !bookmarks.isEmpty {
            viewModel.bookmarks.setSectionEnabled(true)
        }
        return viewModel
    }

    private func topSitesState(sites: [TopSiteConfiguration],
                               numberOfRows: Int,
                               shouldShowSectionHeader: Bool = false,
                               shouldShowAddShortcutTile: Bool = false) -> TopSitesSectionState {
        return TopSitesSectionState(
            topSitesData: sites,
            numberOfRows: numberOfRows,
            numberOfTilesPerRow: TopSitesSectionLayoutProvider.UX.minCards,
            shouldShowSection: true,
            shouldShowSectionHeader: shouldShowSectionHeader,
            shouldShowAddShortcutTile: shouldShowAddShortcutTile
        )
    }

    private func createSites(count: Int = 30) -> [TopSiteConfiguration] {
        var sites = [TopSiteConfiguration]()
        (0..<count).forEach {
            let site = Site.createBasicSite(
                url: "www.url\($0).com",
                title: "Title \($0)"
            )
            sites.append(TopSiteConfiguration(site: site))
        }
        return sites
    }

    private func createStories(count: Int = 20) -> [MerinoStoryConfiguration] {
        var feedStories = [RecommendationDataItem]()
        (0..<count).forEach {
            let story: RecommendationDataItem = .makeItem("feed \($0)")
            feedStories.append(story)
        }

        let stories = feedStories.compactMap {
            MerinoStoryConfiguration(story: MerinoStory(from: $0))
        }
        return stories
    }

    private func createCategories() -> [MerinoCategoryConfiguration] {
        [
            MerinoCategoryConfiguration(
                category: MerinoCategory(
                    feedID: "technology",
                    recommendations: [createStory(title: "technology 1")],
                    isBlocked: false,
                    isFollowed: false,
                    title: "Technology",
                    subtitle: nil,
                    receivedFeedRank: 2
                )
            ),
            MerinoCategoryConfiguration(
                category: MerinoCategory(
                    feedID: "science",
                    recommendations: [createStory(title: "science 1"), createStory(title: "science 2")],
                    isBlocked: false,
                    isFollowed: false,
                    title: "Science",
                    subtitle: nil,
                    receivedFeedRank: 1
                )
            ),
        ]
    }

    private func createStory(title: String) -> MerinoStoryConfiguration {
        return MerinoStoryConfiguration(story: MerinoStory(from: .makeItem(title)))
    }

    private func merinoTitles(from items: [HomepageItem]) -> [String] {
        items.compactMap {
            guard case .merino(let story, _) = $0 else { return nil }
            return story.title
        }
    }

    private func topSiteTitles(from items: [HomepageItem]) -> [String] {
        items.compactMap {
            guard case .topSite(let topSite, _) = $0 else { return nil }
            return topSite.title
        }
    }

    private var mockSectionConfig: JumpBackInSectionLayoutConfiguration {
        return JumpBackInSectionLayoutConfiguration(
            maxLocalTabsWhenSyncedTabExists: 1,
            maxLocalTabsWhenNoSyncedTab: 2,
            layoutType: .compact,
            hasSyncedTab: false
        )
    }

    private func setFeatureFlag(_ flag: FeatureFlagID, isEnabled: Bool) {
        if isEnabled {
            mockNimbusLayer.enabledFlags.insert(flag)
        } else {
            mockNimbusLayer.enabledFlags.remove(flag)
        }
    }

    @MainActor
    private func createTab(urlString: String) -> Tab {
        let tab = Tab(profile: MockProfile(), windowUUID: .XCTestDefaultUUID)
        tab.url = URL(string: urlString)!
        return tab
    }
}

@MainActor
private final class StubRecentTabsProvider: RecentTabsProviding {
    private let tabs: [Tab]

    init(tabs: [Tab]) {
        self.tabs = tabs
    }

    func recentTabs(for windowUUID: WindowUUID) -> [Tab] {
        return tabs
    }
}

@MainActor
private final class StubSyncedTabProvider: SyncedTabProviding {
    func mostRecentSyncedTab() async -> RemoteTabConfiguration? {
        return nil
    }
}
