// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import Shared

private let ignoredSchemes = ["about"]

public func isIgnoredURL(_ url: URL) -> Bool {
    guard let scheme = url.scheme else { return false }

    if ignoredSchemes.contains(scheme) { return true }

    if url.host == "localhost" { return true }

    return false
}

public func isIgnoredURL(_ url: String) -> Bool {
    if let url = URL(string: url) {
        return isIgnoredURL(url)
    }

    return false
}

extension SDRow {
    func getTimestamp(_ column: String) -> Timestamp? {
        return (self[column] as? NSNumber)?.uint64Value
    }

    func getBoolean(_ column: String) -> Bool {
        if let val = self[column] as? Int {
            return val != 0
        }
        return false
    }
}

extension BrowserDBSQLite: PinnedSites {
    private static let deletePinnedSiteSQL = "DELETE FROM pinned_top_sites where domain = ?"
    private static let showDomainOnTopSitesSQL = "UPDATE domains SET showOnTopSites = 1 WHERE domain = ?"
    private static let isPinnedSQL = """
        SELECT * FROM pinned_top_sites
        WHERE url = ?
        LIMIT 1
        """
    private static let pinnedSitesSQL = """
        SELECT * FROM pinned_top_sites
        ORDER BY pinDate DESC
        """

    private func hostForRemoval(of site: Site) -> Result<String, DatabaseError> {
        guard let host = (site.url as String).asURL?.normalizedHost else {
            return .failure(DatabaseError(description: "Invalid url for site \(site.url)"))
        }
        return .success(host)
    }

    private func insertPinnedSiteCommand(for site: Site) -> Result<(String, Args), DatabaseError> {
        guard let host = (site.url as String).asURL?.normalizedHost else {
            return .failure(DatabaseError(description: "Invalid site \(site.url)"))
        }

        let args: Args = [site.url, Date.now(), site.title, host]
        let arglist = BrowserDB.varlist(args.count)
        return .success(("INSERT OR REPLACE INTO pinned_top_sites (url, pinDate, title, domain) VALUES \(arglist)", args))
    }

    // Methods for new homepage that complies with Swift 6 Migration
    public func remove(pinnedSite site: Site) async throws {
        let host = try hostForRemoval(of: site).get()

        try await database.run(Self.deletePinnedSiteSQL, withArgs: [host])
        self.notificationCenter.post(name: .TopSitesUpdated, object: nil)
        try await database.run(Self.showDomainOnTopSitesSQL, withArgs: [host])
    }

    public func removeFromPinnedTopSites(_ site: Site) async throws {
        let host = try hostForRemoval(of: site).get()

        try await database.run(Self.deletePinnedSiteSQL, withArgs: [host])
        self.notificationCenter.post(name: .TopSitesUpdated, object: self)
        try await database.run(Self.showDomainOnTopSitesSQL, withArgs: [host])
    }

    public func isPinnedTopSite(_ url: String) async throws -> Bool {
        return try await database.queryReturnsResults(Self.isPinnedSQL, args: [url])
    }

    public func getPinnedTopSites() async throws -> Cursor<Site> {
        return try await database.runQueryConcurrently(
            Self.pinnedSitesSQL,
            args: [],
            factory: BrowserDBSQLite.historyMetadataColumnFactory
        )
    }

    public func addPinnedTopSite(_ site: Site) async throws {
        let (sql, args) = try insertPinnedSiteCommand(for: site).get()

        try await database.run(sql, withArgs: args)
        self.notificationCenter.post(name: .TopSitesUpdated, object: self)
    }

    // Legacy methods that use deferred
    public func removeFromPinnedTopSites(_ site: Site) -> Success {
        let host: String
        switch hostForRemoval(of: site) {
        case .success(let value): host = value
        case .failure(let error): return deferMaybe(error)
        }

        // do a fuzzy delete so dupes can be removed
        let query: (String, Args?) = (Self.deletePinnedSiteSQL, [host])
        return database.run([query])
            .bind { result in
                if let failureValue = result.failureValue {
                    return deferMaybe(failureValue)
                }

                self.notificationCenter.post(name: .TopSitesUpdated, object: self)
                return self.database.run([(Self.showDomainOnTopSitesSQL, [host])])
            }
    }

    public func isPinnedTopSite(_ url: String) -> Deferred<Maybe<Bool>> {
        let args: Args = [url]
        return self.database.queryReturnsResults(Self.isPinnedSQL, args: args)
    }

    public func getPinnedTopSites() -> Deferred<Maybe<Cursor<Site>>> {
        return database.runQueryConcurrently(
            Self.pinnedSitesSQL,
            args: [],
            factory: BrowserDBSQLite.historyMetadataColumnFactory
        )
    }

    public func addPinnedTopSite(_ site: Site) -> Success { // needs test
        let command: (String, Args)
        switch insertPinnedSiteCommand(for: site) {
        case .success(let value): command = value
        case .failure(let error): return deferMaybe(error)
        }

        return self.database
            .run([command])
            .bind { result in
                if let error = result.failureValue {
                    return deferMaybe(error)
                }
                self.notificationCenter.post(name: .TopSitesUpdated, object: self)
                return succeed()
            }
    }

    public func addPinnedTopSite(_ site: Site, completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        addPinnedTopSite(site).upon { result in
            if result.successValue != nil {
                completion(.success(()))
            } else if let error = result.failureValue {
                completion(.failure(error))
            }
        }
    }
}
