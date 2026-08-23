// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Redux
import XCTest

@testable import Client

/// Replaces `SearchEngineSelectionMiddlewareTests` and `SearchEngineSelectionStateTests`.
@MainActor
final class SearchEngineSelectionViewModelTests: XCTestCase, BusTestUtility {
    var mockBus: MockBrowserEventBus!
    private var searchEnginesManager: SearchEnginesManagerProvider!
    private let searchEngines: [OpenSearchEngine] = [
        OpenSearchEngineTests.generateOpenSearchEngine(type: .wikipedia, withImage: UIImage()),
        OpenSearchEngineTests.generateOpenSearchEngine(type: .youtube, withImage: UIImage()),
    ]

    override func setUp() async throws {
        try await super.setUp()
        await DependencyHelperMock().bootstrapDependencies()
        searchEnginesManager = MockSearchEnginesManager(searchEngines: searchEngines)
        setupBus()
    }

    override func tearDown() async throws {
        searchEnginesManager = nil
        DependencyHelperMock().reset()
        resetBus()
        try await super.tearDown()
    }

    // MARK: - Loading

    func test_viewDidLoad_readsTheOrderedEngines() {
        let subject = createSubject()

        subject.viewDidLoad()

        XCTAssertEqual(subject.searchEngines, searchEngines.map { $0.generateModel() })
    }

    func test_viewDidLoad_publishesTheChange() {
        let subject = createSubject()
        var changes = 0
        subject.onChange = { changes += 1 }

        subject.viewDidLoad()

        XCTAssertEqual(changes, 1)
    }

    /// The middleware dispatched a `didLoadSearchEngines` action for the reducer to store; the
    /// view model holds them itself, so nothing is dispatched.
    func test_viewDidLoad_dispatchesNothing() {
        let subject = createSubject()

        subject.viewDidLoad()

        XCTAssertTrue(mockBus.dispatchedActions.isEmpty)
    }

    // MARK: - Selection

    /// Both announcements are consumed by the toolbar's reducers, which have not migrated.
    func test_didTap_dispatchesDidStartEditingUrl() throws {
        let subject = createSubject()

        subject.didTap(searchEngineModel: searchEngines[0].generateModel())

        let actionCalled = try XCTUnwrap(mockBus.dispatchedActions.first as? ToolbarAction)
        let actionType = try XCTUnwrap(actionCalled.actionType as? ToolbarActionType)
        XCTAssertEqual(actionType, ToolbarActionType.didStartEditingUrl)
    }

    func test_didTap_dispatchesDidTapSearchEngine() throws {
        let subject = createSubject()
        let model = searchEngines[0].generateModel()

        subject.didTap(searchEngineModel: model)

        let actionCalled = try XCTUnwrap(
            mockBus.dispatchedActions.last as? SearchEngineSelectionAction
        )
        let actionType = try XCTUnwrap(actionCalled.actionType as? SearchEngineSelectionActionType)
        XCTAssertEqual(actionType, SearchEngineSelectionActionType.didTapSearchEngine)
        XCTAssertEqual(actionCalled.selectedSearchEngine, model)
    }

    // MARK: - Private Helpers

    private func createSubject() -> SearchEngineSelectionViewModel {
        let subject = SearchEngineSelectionViewModel(
            windowUUID: .XCTestDefaultUUID,
            searchEnginesManager: searchEnginesManager
        )
        trackForMemoryLeaks(subject)
        return subject
    }

    // MARK: - BusTestUtility

    func setupBus() {
        mockBus = MockBrowserEventBus()
        BusTestUtilityHelper.setupBus(with: mockBus)
    }

    func resetBus() {
        BusTestUtilityHelper.resetBus()
    }
}
