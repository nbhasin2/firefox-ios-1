// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Redux
import UIKit
import XCTest

@testable import Client

/// Replaces `SearchBarStateTests` and the search-bar half of `HomepageMiddlewareTests`.
/// Also the first test of the retained bus (D-019): the hide events arrive as dispatched actions
/// rather than as a state change.
@MainActor
final class SearchBarViewModelTests: XCTestCase, StoreTestUtility {
    var mockStore: MockStoreForMiddleware<AppState>!
    private var visibilityStore: SearchBarVisibilityStore!

    override func setUp() async throws {
        try await super.setUp()
        await DependencyHelperMock().bootstrapDependencies()
        visibilityStore = SearchBarVisibilityStore()
        setupStore()
    }

    override func tearDown() async throws {
        visibilityStore = nil
        DependencyHelperMock().reset()
        resetStore()
        try await super.tearDown()
    }

    // MARK: - Visibility

    func test_refreshVisibility_onCompactPhone_showsTheSearchBar() {
        let subject = createSubject(isLandscape: false, idiom: .phone)

        subject.refreshVisibility()

        XCTAssertTrue(subject.shouldShowSearchBar)
    }

    func test_refreshVisibility_onLandscapePhone_hidesTheSearchBar() {
        let subject = createSubject(isLandscape: true, idiom: .phone)

        subject.refreshVisibility()

        XCTAssertFalse(subject.shouldShowSearchBar)
    }

    func test_refreshVisibility_withFeatureDisabled_hidesTheSearchBar() {
        let subject = createSubject(isFeatureEnabled: false)

        subject.refreshVisibility()

        XCTAssertFalse(subject.shouldShowSearchBar)
    }

    func test_refreshVisibility_oniPad_hidesTheSearchBar() {
        let subject = createSubject(isLandscape: false, idiom: .pad)

        subject.refreshVisibility()

        XCTAssertFalse(subject.shouldShowSearchBar)
    }

    func test_refreshVisibility_publishesTheChange() {
        let subject = createSubject()
        var changes = 0
        subject.onChange = { changes += 1 }

        subject.refreshVisibility()

        XCTAssertEqual(changes, 1)
    }

    // MARK: - Bus

    func test_enteredZeroSearchScreen_hidesTheSearchBar() {
        let subject = createSubject()
        subject.refreshVisibility()

        mockStore.dispatch(
            GeneralBrowserAction(windowUUID: .XCTestDefaultUUID,
                                 actionType: GeneralBrowserActionType.enteredZeroSearchScreen)
        )

        XCTAssertFalse(subject.shouldShowSearchBar)
    }

    func test_didUnhideToolbar_hidesTheSearchBar() {
        let subject = createSubject()
        subject.refreshVisibility()

        mockStore.dispatch(
            GeneralBrowserAction(windowUUID: .XCTestDefaultUUID,
                                 actionType: GeneralBrowserActionType.didUnhideToolbar)
        )

        XCTAssertFalse(subject.shouldShowSearchBar)
    }

    func test_didStartEditingUrl_hidesTheSearchBar() {
        let subject = createSubject()
        subject.refreshVisibility()

        mockStore.dispatch(
            ToolbarAction(windowUUID: .XCTestDefaultUUID,
                          actionType: ToolbarActionType.didStartEditingUrl)
        )

        XCTAssertFalse(subject.shouldShowSearchBar)
    }

    func test_actionForAnotherWindow_isIgnored() {
        let subject = createSubject()
        subject.refreshVisibility()
        let otherWindow = WindowUUID(uuidString: "44BA0B7D-097A-484D-8358-91A6E374451D")!

        mockStore.dispatch(
            GeneralBrowserAction(windowUUID: otherWindow,
                                 actionType: GeneralBrowserActionType.enteredZeroSearchScreen)
        )

        // The reducer's windowUUID guard, kept on the observer (D-005).
        XCTAssertTrue(subject.shouldShowSearchBar)
    }

    func test_cancelEdit_recomputesVisibility() {
        let subject = createSubject()
        mockStore.dispatch(
            GeneralBrowserAction(windowUUID: .XCTestDefaultUUID,
                                 actionType: GeneralBrowserActionType.enteredZeroSearchScreen)
        )
        XCTAssertFalse(subject.shouldShowSearchBar)

        mockStore.dispatch(
            ToolbarAction(windowUUID: .XCTestDefaultUUID, actionType: ToolbarActionType.cancelEdit)
        )

        XCTAssertTrue(subject.shouldShowSearchBar)
    }

    // MARK: - Visibility store

    func test_visibility_isPublishedForBrowserViewController() {
        let subject = createSubject()

        subject.refreshVisibility()

        // BVC and its reducer read this rather than HomepageState.
        XCTAssertTrue(visibilityStore.isSearchBarVisible(for: .XCTestDefaultUUID))
    }

    // MARK: - Private Helpers

    private func createSubject(isLandscape: Bool = false,
                               idiom: UIUserInterfaceIdiom = .phone,
                               isFeatureEnabled: Bool = true) -> SearchBarViewModel {
        let subject = SearchBarViewModel(
            windowUUID: .XCTestDefaultUUID,
            isFeatureEnabled: { isFeatureEnabled },
            isLandscape: { isLandscape },
            deviceIdiom: { idiom },
            bus: mockStore,
            visibilityStore: visibilityStore
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
