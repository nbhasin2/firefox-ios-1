// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import Shared

public struct ReadingListStorageError: MaybeErrorType, Sendable {
    let message: String

    public init(message: String) {
        self.message = message
    }

    public var description: String {
        return message
    }
}

public struct SQLiteReadingList: Sendable {
    private let db: BrowserDB
    private let notificationCenter: NotificationCenter

    private let allColumns = [
        "client_id",
        "client_last_modified",
        "id",
        "last_modified",
        "url",
        "title",
        "added_by",
        "archived",
        "favorite",
        "unread"
    ].joined(separator: ",")

    public init(
        db: BrowserDB,
        notificationCenter: NotificationCenter = NotificationCenter.default
    ) {
        self.db = db
        self.notificationCenter = notificationCenter
    }
}

extension SQLiteReadingList: ReadingList {
    public func getAvailableRecords(completion: @escaping @Sendable ([ReadingListItem]) -> Void) {
        db.runQuery(
            availableRecordsSQL,
            args: nil,
            factory: SQLiteReadingList.ReadingListItemFactory
        ).upon { result in
            guard let cursor = result.successValue else {
                completion([])
                return
            }
            completion(cursor.asArray())
        }
    }

    public func getAvailableRecords() -> Deferred<Maybe<[ReadingListItem]>> {
        return db.runQuery(availableRecordsSQL, args: nil, factory: SQLiteReadingList.ReadingListItemFactory)
            .map { $0.map { cursor in cursor.asArray() } }
    }

    public func getAvailableRecords() async throws -> [ReadingListItem] {
        let cursor = try await db.runQuery(
            availableRecordsSQL,
            args: nil,
            factory: SQLiteReadingList.ReadingListItemFactory
        )
        return cursor.asArray()
    }

    public func deleteRecord(_ record: ReadingListItem, completion: (@Sendable (Bool) -> Void)? = nil) {
        let sql = "DELETE FROM items WHERE client_id = ?"
        let args: Args = [record.id]
        let deferredResponse = db.run(sql, withArgs: args)

        deferredResponse.upon { result in
            self.notificationCenter.post(name: .ReadingListUpdated, object: self)
            completion?(result.isSuccess)
        }
    }

    public func createRecordWithURL(_ url: String, title: String, addedBy: String) -> Deferred<Maybe<ReadingListItem>> {
        return db.transaction { connection -> ReadingListItem in
            return try self.insertRecord(connection, url: url, title: title, addedBy: addedBy)
        }
    }

    public func createRecordWithURL(_ url: String, title: String, addedBy: String) async throws -> ReadingListItem {
        return try await db.transaction { connection -> ReadingListItem in
            return try self.insertRecord(connection, url: url, title: title, addedBy: addedBy)
        }
    }

    public func getRecordWithURL(_ url: String) -> Deferred<Maybe<ReadingListItem>> {
        let args: Args = [url]
        return db.runQuery(recordWithURLSQL, args: args, factory: SQLiteReadingList.ReadingListItemFactory).map {
            $0.bind { cursor in
                if let item = cursor.asArray().first {
                    return Maybe(success: item)
                } else {
                    return Maybe(failure: ReadingListStorageError(message: SQLiteReadingList.recordNotFoundMessage))
                }
            }
        }
    }

    public func getRecordWithURL(_ url: String) async throws -> ReadingListItem {
        let args: Args = [url]
        let cursor = try await db.runQuery(
            recordWithURLSQL,
            args: args,
            factory: SQLiteReadingList.ReadingListItemFactory
        )
        guard let item = cursor.asArray().first else {
            throw ReadingListStorageError(message: SQLiteReadingList.recordNotFoundMessage)
        }
        return item
    }

    public func updateRecord(_ record: ReadingListItem, unread: Bool) -> Deferred<Maybe<ReadingListItem>> {
        return db.transaction { connection -> ReadingListItem in
            return try self.updateRecordRow(connection, record: record, unread: unread)
        }
    }

    public func updateRecord(_ record: ReadingListItem, unread: Bool) async throws -> ReadingListItem {
        return try await db.transaction { connection -> ReadingListItem in
            return try self.updateRecordRow(connection, record: record, unread: unread)
        }
    }

    private static let recordNotFoundMessage = "Can't create RLCR from row"

    private var availableRecordsSQL: String {
        return "SELECT \(allColumns) FROM items ORDER BY client_last_modified DESC"
    }

    private var recordWithURLSQL: String {
        return "SELECT \(allColumns) FROM items WHERE url = ? LIMIT 1"
    }

    private func insertRecord(
        _ connection: SQLiteDBConnection,
        url: String,
        title: String,
        addedBy: String
    ) throws -> ReadingListItem {
        // swiftlint:disable line_length
        let insertSQL = "INSERT OR REPLACE INTO items (client_last_modified, url, title, added_by) VALUES (?, ?, ?, ?)"
        // swiftlint:enable line_length
        let insertArgs: Args = [ReadingListNow(), url, title, addedBy]
        let lastInsertedRowID = connection.lastInsertedRowID

        try connection.executeChange(insertSQL, withArgs: insertArgs)

        if connection.lastInsertedRowID == lastInsertedRowID {
            throw ReadingListStorageError(message: "Unable to insert ReadingListItem")
        }

        let querySQL = "SELECT \(allColumns) FROM items WHERE client_id = ? LIMIT 1"
        let queryArgs: Args = [connection.lastInsertedRowID]

        let cursor = connection.executeQuery(
            querySQL,
            factory: SQLiteReadingList.ReadingListItemFactory,
            withArgs: queryArgs
        )

        let items = cursor.asArray()
        if let item = items.first {
            notificationCenter.post(name: .ReadingListUpdated, object: self)
            return item
        } else {
            throw ReadingListStorageError(message: "Unable to get inserted ReadingListItem")
        }
    }

    private func updateRecordRow(
        _ connection: SQLiteDBConnection,
        record: ReadingListItem,
        unread: Bool
    ) throws -> ReadingListItem {
        let updateSQL = "UPDATE items SET unread = ? WHERE client_id = ?"
        let updateArgs: Args = [unread, record.id]

        try connection.executeChange(updateSQL, withArgs: updateArgs)

        let querySQL = "SELECT \(allColumns) FROM items WHERE client_id = ? LIMIT 1"
        let queryArgs: Args = [record.id]

        let cursor = connection.executeQuery(
            querySQL,
            factory: SQLiteReadingList.ReadingListItemFactory,
            withArgs: queryArgs
        )

        let items = cursor.asArray()
        if let item = items.first {
            notificationCenter.post(name: .ReadingListUpdated, object: self)
            return item
        } else {
            throw ReadingListStorageError(message: "Unable to get updated ReadingListItem")
        }
    }

    fileprivate static func ReadingListItemFactory(_ row: SDRow) -> ReadingListItem {
        guard let id = row["client_id"] as? Int,
              let url = row["url"] as? String,
              let title = row["title"] as? String,
              let addedBy = row["added_by"] as? String else {
            return ReadingListItem(
                id: 0,
                lastModified: 0,
                url: "",
                title: "",
                addedBy: "",
                unread: false,
                archived: false,
                favorite: false
            )
        }
        let lastModified = row.getTimestamp("client_last_modified")!
        let archived = row.getBoolean("archived")
        let unread = row.getBoolean("unread")
        let favorite = row.getBoolean("favorite")
        return ReadingListItem(
            id: id,
            lastModified: lastModified,
            url: url,
            title: title,
            addedBy: addedBy,
            unread: unread,
            archived: archived,
            favorite: favorite
        )
    }
}
