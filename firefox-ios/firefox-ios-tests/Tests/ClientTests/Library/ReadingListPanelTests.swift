// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import XCTest
import Common
@testable import Client
@testable import Storage

@MainActor
class ReadingListPanelTests: XCTestCase {
    let windowUUID: WindowUUID = .XCTestDefaultUUID
    override func setUp() async throws {
        try await super.setUp()
        DependencyHelperMock().bootstrapDependencies()
    }

    override func tearDown() async throws {
        DependencyHelperMock().reset()
        try await super.tearDown()
    }

    func testReaderPanelButtons() {
        let subject = createSubject()

        XCTAssertTrue(subject.bottomToolbarItems.isEmpty)
    }

    func testReaderPanel_ShouldDismissOnDone() {
        let subject = createSubject()

        XCTAssertTrue(subject.shouldDismissOnDone())
    }

    func testDidSelectRow_withDeferredRemovalEnabled_marksRecordAsRead() async throws {
        let profile = makeProfile()
        enableDeferredRemoval(profile: profile)
        let url = "https://example.com/article"
        _ = try await profile.readingList.createRecordWithURL(url, title: "Article", addedBy: "Test")
        let subject = createSubject(profile: profile)
        await subject.loadReadingList()
        let updated = expectation(forNotification: .ReadingListUpdated, object: nil)

        subject.tableView(subject.tableView, didSelectRowAt: IndexPath(row: 0, section: 0))
        await fulfillment(of: [updated], timeout: 5)

        let record = try await profile.readingList.getRecordWithURL(url)
        XCTAssertFalse(record.unread)
    }

    func testRefreshReadingList_withDeferredRemovalEnabled_populatesTable() async throws {
        let profile = makeProfile()
        enableDeferredRemoval(profile: profile)
        _ = try await profile.readingList.createRecordWithURL("https://example.com/1", title: "One", addedBy: "Test")
        _ = try await profile.readingList.createRecordWithURL("https://example.com/2", title: "Two", addedBy: "Test")
        let subject = createSubject(profile: profile)

        subject.refreshReadingList()

        let populated = expectation(for: NSPredicate { _, _ in
            subject.tableView(subject.tableView, numberOfRowsInSection: 0) == 2
        }, evaluatedWith: nil)
        await fulfillment(of: [populated], timeout: 5)
    }

    func testToggleItem_withDeferredRemovalEnabled_marksRecordAsRead() async throws {
        let profile = makeProfile()
        enableDeferredRemoval(profile: profile)
        let url = "https://example.com/article"
        _ = try await profile.readingList.createRecordWithURL(url, title: "Article", addedBy: "Test")
        let subject = createSubject(profile: profile)
        subject.loadViewIfNeeded()
        await subject.loadReadingList()
        let indexPath = IndexPath(row: 0, section: 0)
        let configuration = try XCTUnwrap(
            subject.tableView(subject.tableView, trailingSwipeActionsConfigurationForRowAt: indexPath)
        )

        configuration.actions[0].handler(configuration.actions[0], UIView()) { _ in }

        let toggled = expectation(for: NSPredicate { _, _ in
            let cell = subject.tableView(subject.tableView, cellForRowAt: indexPath) as? ReadingListTableViewCell
            return cell?.unread == false
        }, evaluatedWith: nil)
        await fulfillment(of: [toggled], timeout: 5)
    }

    private func enableDeferredRemoval(profile: Profile) {
        let mockNimbusLayer = MockNimbusFeatureFlagLayer()
        mockNimbusLayer.enabledFlags.insert(.deferredRemoval)
        DependencyHelperMock().bootstrapDependencies(
            injectedFeatureFlagProvider: FeatureFlagsProvider(prefs: profile.prefs, backendLayer: mockNimbusLayer)
        )
    }

    private func createSubject(profile: Profile? = nil) -> ReadingListPanel {
        let profile = profile ?? makeProfile()
        let subject = ReadingListPanel(profile: profile, windowUUID: windowUUID)
        trackForMemoryLeaks(subject)
        return subject
    }
}
