// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Redux
import Storage
import XCTest

@testable import Client

/// Replaces the fetch and mutation halves of `TopSitesMiddlewareTests`.
@MainActor
final class TopSitesServiceTests: XCTestCase, StoreTestUtility {
    var mockStore: MockStoreForMiddleware<AppState>!
    private var topSitesManager: MockTopSitesManager!

    override func setUp() async throws {
        try await super.setUp()
        await DependencyHelperMock().bootstrapDependencies()
        topSitesManager = MockTopSitesManager()
        setupStore()
    }

    override func tearDown() async throws {
        topSitesManager = nil
        DependencyHelperMock().reset()
        resetStore()
        try await super.tearDown()
    }

    // MARK: - Fetching

    func test_refresh_recalculatesAndPublishes() async {
        let subject = createSubject()

        subject.refresh(for: .XCTestDefaultUUID)
        await waitForSites(subject)

        XCTAssertEqual(topSitesManager.recalculateTopSitesCalledCount, 1)
        XCTAssertFalse(subject.topSites.isEmpty)
    }

    func test_refresh_notifiesTheObserver() async {
        let subject = createSubject()
        let observer = NSObject()
        var published: [TopSiteConfiguration]?
        subject.addSitesObserver(observer) { published = $0 }

        subject.refresh(for: .XCTestDefaultUUID)
        await waitForSites(subject)

        XCTAssertEqual(published?.count, subject.topSites.count)
    }

    /// One service, a homepage per window: every observer hears each fetch.
    func test_refresh_notifiesEveryObserver() async {
        let subject = createSubject()
        let first = NSObject()
        let second = NSObject()
        var deliveries = 0
        subject.addSitesObserver(first) { _ in deliveries += 1 }
        subject.addSitesObserver(second) { _ in deliveries += 1 }

        subject.refresh(for: .XCTestDefaultUUID)
        await waitForSites(subject)

        XCTAssertEqual(deliveries, 2)
    }

    func test_refresh_afterTheObserverIsGone_doesNotCrash() async {
        let subject = createSubject()
        var deliveries = 0
        autoreleasepool {
            let transient = NSObject()
            subject.addSitesObserver(transient) { _ in deliveries += 1 }
        }

        subject.refresh(for: .XCTestDefaultUUID)
        await waitForSites(subject)

        XCTAssertEqual(deliveries, 0)
    }

    /// The shortcuts library still reduces this; see D-025.
    func test_refresh_dispatchesRetrievedUpdatedSites() async throws {
        let subject = createSubject()

        subject.refresh(for: .XCTestDefaultUUID)
        await waitForSites(subject)

        let action = try XCTUnwrap(
            mockStore.dispatchedActions.last(where: { $0 is TopSitesAction }) as? TopSitesAction
        )
        XCTAssertEqual(action.actionType as? TopSitesMiddlewareActionType, .retrievedUpdatedSites)
        XCTAssertEqual(action.topSites?.count, subject.topSites.count)
    }

    /// The launch and foreground triggers used to fire parallel sponsored requests on slow
    /// networks; the middleware's in-flight guard came here with the fetch.
    func test_refresh_whileOneIsInFlight_coalesces() async {
        let subject = createSubject()

        subject.refresh(for: .XCTestDefaultUUID)
        subject.refresh(for: .XCTestDefaultUUID)
        await waitForSites(subject)

        XCTAssertEqual(topSitesManager.recalculateTopSitesCalledCount, 1)
    }

    func test_refresh_withoutCoalescing_fetchesAgain() async {
        let subject = createSubject()

        subject.refresh(for: .XCTestDefaultUUID, coalesce: false)
        subject.refresh(for: .XCTestDefaultUUID, coalesce: false)
        for _ in 0..<40 where topSitesManager.recalculateTopSitesCalledCount < 2 {
            await Task.yield()
        }

        XCTAssertEqual(topSitesManager.recalculateTopSitesCalledCount, 2)
    }

    // MARK: - Mutations

    func test_pin_pinsTheSite() {
        let subject = createSubject()

        subject.pin(Site.createBasicSite(url: "www.example.com", title: "Pinned Top Site"))

        XCTAssertEqual(topSitesManager.pinTopSiteCalledCount, 1)
    }

    func test_unpin_unpinsTheSite() {
        let subject = createSubject()
        let expectation = XCTestExpectation(description: "Unpin reaches the manager")
        topSitesManager.unpinTopSiteCalled = { expectation.fulfill() }

        subject.unpin(Site.createBasicSite(url: "www.example.com", title: "Unpinned Top Site"))

        wait(for: [expectation], timeout: 1)
    }

    func test_remove_removesTheSite() {
        let subject = createSubject()
        let expectation = XCTestExpectation(description: "Remove reaches the manager")
        topSitesManager.removeTopSiteCalled = { expectation.fulfill() }

        subject.remove(Site.createBasicSite(url: "www.example.com", title: "Removed Top Site"))

        wait(for: [expectation], timeout: 1)
    }

    // MARK: - Private Helpers

    private func waitForSites(_ subject: TopSitesService) async {
        for _ in 0..<40 where subject.topSites.isEmpty {
            await Task.yield()
        }
    }

    private func createSubject() -> TopSitesService {
        let subject = TopSitesService(
            topSitesManager: topSitesManager,
            featureFlagsProvider: MockNimbusFeatureFlags()
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
