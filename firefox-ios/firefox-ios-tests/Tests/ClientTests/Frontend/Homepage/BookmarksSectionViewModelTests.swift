// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import MozillaAppServices
import XCTest

@testable import Client

/// Replaces `BookmarksMiddlewareTests` and the fetch half of `BookmarksSectionStateTests`.
@MainActor
final class BookmarksSectionViewModelTests: XCTestCase {
    private var bookmarksHandler: MockBookmarksHandler!
    private var profile: MockProfile!

    override func setUp() async throws {
        try await super.setUp()
        await DependencyHelperMock().bootstrapDependencies()
        bookmarksHandler = MockBookmarksHandler()
        profile = MockProfile()
    }

    override func tearDown() async throws {
        bookmarksHandler = nil
        profile = nil
        DependencyHelperMock().reset()
        try await super.tearDown()
    }

    // MARK: - Fetching

    func test_refreshBookmarks_asksForTheRecentBookmarks() async {
        bookmarksHandler.getRecentBookmarksResult = [makeBookmark(url: "https://mozilla.org")]
        let subject = createSubject()

        subject.refreshBookmarks()
        await waitForBookmarks(subject)

        XCTAssertEqual(bookmarksHandler.getRecentBookmarksCallCount, 1)
        XCTAssertEqual(subject.bookmarks.count, 1)
    }

    func test_refreshBookmarks_marksThemAsBookmarked() async {
        bookmarksHandler.getRecentBookmarksResult = [makeBookmark(url: "https://mozilla.org")]
        let subject = createSubject()

        subject.refreshBookmarks()
        await waitForBookmarks(subject)

        XCTAssertEqual(subject.bookmarks.first?.site.isBookmarked, true)
    }

    func test_refreshBookmarks_publishesTheChange() async {
        bookmarksHandler.getRecentBookmarksResult = [makeBookmark(url: "https://mozilla.org")]
        let subject = createSubject()
        var changes = 0
        subject.onChange = { changes += 1 }

        subject.refreshBookmarks()
        await waitForBookmarks(subject)

        XCTAssertEqual(changes, 1)
    }

    // MARK: - Section setting

    func test_setSectionEnabled_false_hidesTheSection() {
        let subject = createSubject()

        subject.setSectionEnabled(false)

        XCTAssertFalse(subject.shouldShowSection)
    }

    // MARK: - Private Helpers

    private func makeBookmark(url: String) -> BookmarkItemData {
        return BookmarkItemData(
            guid: "guid",
            dateAdded: Int64(Date().toTimestamp()),
            lastModified: Int64(Date().toTimestamp()),
            parentGUID: nil,
            position: 0,
            url: url,
            title: "Mozilla"
        )
    }

    private func waitForBookmarks(_ subject: BookmarksSectionViewModel) async {
        for _ in 0..<20 where subject.bookmarks.isEmpty {
            await Task.yield()
        }
    }

    private func createSubject() -> BookmarksSectionViewModel {
        let subject = BookmarksSectionViewModel(
            profile: profile,
            bookmarksHandler: bookmarksHandler
        )
        trackForMemoryLeaks(subject)
        return subject
    }
}
