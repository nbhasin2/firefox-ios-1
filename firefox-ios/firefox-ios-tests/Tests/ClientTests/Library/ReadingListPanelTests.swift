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
        let mockNimbusLayer = MockNimbusFeatureFlagLayer()
        mockNimbusLayer.enabledFlags.insert(.deferredRemoval)
        DependencyHelperMock().bootstrapDependencies(
            injectedFeatureFlagProvider: FeatureFlagsProvider(prefs: profile.prefs, backendLayer: mockNimbusLayer)
        )
        let url = "https://example.com/article"
        _ = try await profile.readingList.createRecordWithURL(url, title: "Article", addedBy: "Test")
        let subject = createSubject(profile: profile)
        subject.refreshReadingList()
        let updated = expectation(forNotification: .ReadingListUpdated, object: nil)

        subject.tableView(subject.tableView, didSelectRowAt: IndexPath(row: 0, section: 0))
        await fulfillment(of: [updated], timeout: 5)

        let record = try await profile.readingList.getRecordWithURL(url)
        XCTAssertFalse(record.unread)
    }

    private func createSubject(profile: Profile? = nil) -> ReadingListPanel {
        let profile = profile ?? makeProfile()
        let subject = ReadingListPanel(profile: profile, windowUUID: windowUUID)
        trackForMemoryLeaks(subject)
        return subject
    }
}
