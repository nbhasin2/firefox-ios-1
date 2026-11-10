// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import Shared

public final class SQLiteQueue: TabQueue {
    let db: BrowserDB

    public init(db: BrowserDB) {
        self.db = db
    }

    private static let insertSQL = "INSERT OR IGNORE INTO queue (url) VALUES (?)"
    private static let selectSQL = "SELECT url FROM queue"
    private static let deleteSQL = "DELETE FROM queue"

    public func addToQueue(_ tab: ShareItem) -> Success {
        return db.run(Self.insertSQL, withArgs: [tab.url])
    }

    public func addToQueue(_ tab: ShareItem) async throws {
        try await db.run(Self.insertSQL, withArgs: [tab.url])
    }

    public func getQueuedTabs() async throws -> [ShareItem] {
        let cursor = try await db.runQuery(Self.selectSQL, args: nil, factory: self.factory)
        return cursor.asArray()
    }

    public func clearQueuedTabs() async throws {
        try await db.run(Self.deleteSQL)
    }

    fileprivate func factory(_ row: SDRow) -> ShareItem {
        let url = row["url"] as? String ?? ""
        return ShareItem(url: url, title: "")
    }

    public func getQueuedTabs(completion: @MainActor @escaping ([ShareItem]) -> Void) {
        db.runQuery(Self.selectSQL, args: nil, factory: self.factory)
            .uponQueue(.main) { result in
                guard let cursor = result.successValue else { return }
                // FXIOS-13228 It should be safe to assumeIsolated here because of `.main` queue above
                MainActor.assumeIsolated {
                    completion(cursor.asArray())
                }
            }
    }

    public func clearQueuedTabs() -> Success {
        return db.run(Self.deleteSQL)
    }
}
