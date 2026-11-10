// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import Shared
@testable import Storage
import XCTest

class SupportingFiles: FileAccessor {
    var rootPath: String

    init() {
        rootPath = Bundle.main.bundlePath + "/PlugIns/StorageTests.xctest/"
    }
}

class TestBrowserDB: XCTestCase, @unchecked Sendable {
    lazy var files = makeTemporaryFiles()

    class MockFailingSchema: Schema {
        var name: String { return "FAILURE" }
        var version: Int { return BrowserSchema.DefaultVersion + 1 }
        func drop(_ db: SQLiteDBConnection) -> Bool {
            return true
        }
        func create(_ db: SQLiteDBConnection) -> Bool {
            return false
        }
        func update(_ db: SQLiteDBConnection, from: Int) -> Bool {
            return false
        }
    }

    fileprivate class MockListener {
        var notification: Notification?
        @objc
        func onDatabaseWasRecreated(_ notification: Notification) {
            self.notification = notification
        }
    }

    func testUpgradeV33toV34RemovesLongURLs() {
        let db = BrowserDB(filename: "v33.db", schema: BrowserSchema(), files: SupportingFiles())
        let results = db.runQuery("SELECT bmkUri, title FROM bookmarksLocal WHERE type = 1",
                                  args: nil,
                                  factory: { row in
            guard let bmkUri = row[0] as? String else {
                XCTFail("Failed to cast value for key 'bmkUri' to String.")
                return ("", "")
            }

            guard let title = row[1] as? String else {
                XCTFail("Failed to cast value for key 'title' to String.")
                return (bmkUri, "")
            }

            return (bmkUri, title)
        }).value.successValue!

        // The bookmark with the long URL has been deleted.
        XCTAssertTrue(results.count == 1)

        let remaining = results[0]!

        // This one's title has been truncated to 4096 chars.
        XCTAssertEqual(remaining.1.count, 4096)
        XCTAssertEqual(remaining.1.utf8.count, 4096)
        XCTAssertTrue(remaining.1.hasPrefix("abcdefghijkl"))
        XCTAssertEqual(remaining.0, "http://example.com/short")
    }
    // Temp. Disabled: https://mozilla-hub.atlassian.net/browse/FXIOS-7505
    func testMovesDB() throws {
        var db = BrowserDB(filename: "foo.db", schema: BrowserSchema(), files: self.files)
        db.run("CREATE TABLE foo (bar TEXT)").succeeded() // Just so we have writes in the WAL.

        XCTAssertTrue(files.exists("foo.db"))
        XCTAssertTrue(files.exists("foo.db-shm"))
        XCTAssertTrue(files.exists("foo.db-wal"))

        // Grab a pointer to the -shm so we can compare later.
        let shmAAttributes = try files.attributesForFileAt(relativePath: "foo.db-shm")
        guard let creationA = shmAAttributes[FileAttributeKey.creationDate] as? Date else {
            XCTFail("Failed to cast value for key 'creationDate' to Date.")
            return
        }
        guard let inodeA = (shmAAttributes[FileAttributeKey.systemFileNumber] as? NSNumber)?.uintValue else {
            XCTFail("Failed to cast value for key 'systemFileNumber' to NSNumber.")
            return
        }

        XCTAssertFalse(files.exists("foo.db.bak.1"))
        XCTAssertFalse(files.exists("foo.db.bak.1-shm"))
        XCTAssertFalse(files.exists("foo.db.bak.1-wal"))

        let center = NotificationCenter.default
        let listener = MockListener()
        center.addObserver(
            listener,
            selector: #selector(MockListener.onDatabaseWasRecreated),
            name: .DatabaseWasRecreated,
            object: nil
        )
        defer { center.removeObserver(listener) }

        // It'll still fail, but it moved our old DB.
        // Our current observation is that closing the DB deletes the .shm file and also
        // checkpoints the WAL.
        db.forceClose()

        db = BrowserDB(filename: "foo.db", schema: MockFailingSchema(), files: self.files)
        // This won't actually write since we'll get a failed connection
        db.run("CREATE TABLE foo (bar TEXT)").failed()
        db = BrowserDB(filename: "foo.db", schema: BrowserSchema(), files: self.files)
        db.run("CREATE TABLE foo (bar TEXT)").succeeded() // Just so we have writes in the WAL.

        XCTAssertTrue(files.exists("foo.db"))
        XCTAssertTrue(files.exists("foo.db-shm"))
        XCTAssertTrue(files.exists("foo.db-wal"))

        // But now it's been reopened, it's not the same -shm!
        let shmBAttributes = try files.attributesForFileAt(relativePath: "foo.db-shm")
        guard let creationB = shmBAttributes[FileAttributeKey.creationDate] as? Date else {
            XCTFail("Failed to cast value for key 'creationDate' to Date.")
            return
        }
        guard let inodeB = (shmBAttributes[FileAttributeKey.systemFileNumber] as? NSNumber)?.uintValue else {
            XCTFail("Failed to cast value for key 'systemFileNumber' to NSNumber.")
            return
        }
        XCTAssertTrue(creationA.compare(creationB) != ComparisonResult.orderedDescending)
        XCTAssertNotEqual(inodeA, inodeB)

        XCTAssertTrue(files.exists("foo.db.bak.1"))
        XCTAssertFalse(files.exists("foo.db.bak.1-shm"))
        XCTAssertFalse(files.exists("foo.db.bak.1-wal"))

        // The right notification was issued.
        XCTAssertEqual("foo.db", (listener.notification?.object as? String))
    }

    func testConcurrentQueriesDealloc() async {
        let expectation = self.expectation(description: "Got all DB results")

        let shortConcurrentQuery = makeShortConcurrentQuery()

        await self.trackForMemoryLeaks(shortConcurrentQuery)

        _ = shortConcurrentQuery.bind { result -> Deferred<Maybe<Bool>> in
            if result.successValue?.asArray() != nil {
                expectation.fulfill()
                return deferMaybe(true)
            }

            return deferMaybe(DatabaseError(description: "Unable to execute concurrent short-running query"))
        }

        await fulfillment(of: [expectation], timeout: 3)
    }

    // Sync context so the Deferred overloads are chosen over the async ones.
    private func makeShortConcurrentQuery() -> Deferred<Maybe<Cursor<[String: Any]>>> {
        let db = BrowserDB(filename: "foo.db", schema: BrowserSchema(), files: self.files)
        db.run("CREATE TABLE foo (id INTEGER PRIMARY KEY AUTOINCREMENT, bar TEXT)").succeeded()

        _ = db.withConnection { connection in
            for i in 0..<1000 {
                let args: Args = ["bar \(i)"]
                try connection.executeChange(
                    "INSERT INTO foo (bar) VALUES (?)",
                    withArgs: args
                )
            }
        }

        return db.runQueryConcurrently(
            "SELECT * FROM foo LIMIT 1",
            args: nil,
            factory: Self.fooBarFactory
        )
    }

    func testAsyncRunAndRunQuery() async throws {
        let db = BrowserDB(filename: "foo.db", schema: BrowserSchema(), files: self.files)
        try await db.run("CREATE TABLE foo (id INTEGER PRIMARY KEY AUTOINCREMENT, bar TEXT)")
        try await db.run([
            (sql: "INSERT INTO foo (bar) VALUES (?)", args: ["one"]),
            (sql: "INSERT INTO foo (bar) VALUES (?)", args: ["two"])
        ])

        let cursor = try await db.runQuery("SELECT * FROM foo", args: nil, factory: Self.fooBarFactory)
        let concurrentCursor = try await db.runQueryConcurrently(
            "SELECT * FROM foo LIMIT 1",
            args: nil,
            factory: Self.fooBarFactory
        )

        XCTAssertEqual(cursor.asArray().count, 2)
        XCTAssertEqual(concurrentCursor.asArray().count, 1)
    }

    func testAsyncRunEmptyCommandsSucceeds() async throws {
        let db = BrowserDB(filename: "foo.db", schema: BrowserSchema(), files: self.files)
        try await db.run([])
    }

    func testAsyncRunThrowsDatabaseErrorOnInvalidSQL() async {
        let db = BrowserDB(filename: "foo.db", schema: BrowserSchema(), files: self.files)
        do {
            try await db.run("INSERT INTO missing_table (bar) VALUES (1)")
            XCTFail("Expected run to throw")
        } catch {
            XCTAssertTrue(error is DatabaseError)
        }
    }

    func testAsyncTransactionRollsBackOnThrow() async throws {
        let db = BrowserDB(filename: "foo.db", schema: BrowserSchema(), files: self.files)
        try await db.run("CREATE TABLE foo (id INTEGER PRIMARY KEY AUTOINCREMENT, bar TEXT)")

        do {
            try await db.run([
                (sql: "INSERT INTO foo (bar) VALUES (?)", args: ["one"]),
                (sql: "INSERT INTO missing_table (bar) VALUES (1)", args: nil)
            ])
            XCTFail("Expected transaction to throw")
        } catch {
            XCTAssertTrue(error is DatabaseError)
        }

        let hasRows = try await db.queryReturnsResults("SELECT * FROM foo")
        XCTAssertFalse(hasRows)
    }

    func testAsyncQueryReturnsResults() async throws {
        let db = BrowserDB(filename: "foo.db", schema: BrowserSchema(), files: self.files)
        try await db.run("CREATE TABLE foo (id INTEGER PRIMARY KEY AUTOINCREMENT, bar TEXT)")

        let beforeInsert = try await db.queryReturnsResults("SELECT * FROM foo")
        XCTAssertFalse(beforeInsert)

        try await db.run("INSERT INTO foo (bar) VALUES (?)", withArgs: ["one"])

        let afterInsert = try await db.queryReturnsResults("SELECT * FROM foo WHERE bar = ?", args: ["one"])
        XCTAssertTrue(afterInsert)
    }

    func testAsyncWithConnectionReturnsValueAndThrows() async throws {
        let db = BrowserDB(filename: "foo.db", schema: BrowserSchema(), files: self.files)
        let value = try await db.withConnection { _ in 42 }
        XCTAssertEqual(value, 42)

        do {
            _ = try await db.withConnection { connection -> Int in
                try connection.executeChange("INSERT INTO missing_table (bar) VALUES (1)")
                return 0
            }
            XCTFail("Expected withConnection to throw")
        } catch {
            XCTAssertTrue(error is DatabaseError)
        }
    }

    nonisolated static func fooBarFactory(_ row: SDRow) -> [String: Any] {
        var result: [String: Any] = [:]
        result["id"] = row["id"]
        result["bar"] = row["bar"]
        return result
    }

    @MainActor
    func trackForMemoryLeaks(_ instance: AnyObject, file: StaticString = #filePath, line: UInt = #line) {
        addTeardownBlock { [weak instance] in
            XCTAssertNil(
                instance,
                "Instance should have been deallocated, potential memory leak.",
                file: file,
                line: line
            )
        }
    }
}
