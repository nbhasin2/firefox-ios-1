// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import Shared
@testable import Storage
import XCTest

class TestSQLiteQueue: XCTestCase {
    lazy var files = makeTemporaryFiles()

    private func makeSubject() -> SQLiteQueue {
        return SQLiteQueue(db: BrowserDB(filename: "TestQueue.db", schema: BrowserSchema(), files: files))
    }

    func testQueue_async_addGetClear() async throws {
        let subject = makeSubject()
        let urls = ["https://example.com/1", "https://example.com/2"]

        try await subject.addToQueue(ShareItem(url: urls[0], title: ""))
        try await subject.addToQueue(ShareItem(url: urls[1], title: ""))
        try await subject.addToQueue(ShareItem(url: urls[1], title: ""))
        let queued = try await subject.getQueuedTabs()
        XCTAssertEqual(queued.map { $0.url }, urls, "Duplicates are ignored")

        try await subject.clearQueuedTabs()
        let afterClear = try await subject.getQueuedTabs()
        XCTAssertTrue(afterClear.isEmpty)
    }
}
