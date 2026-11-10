// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import Storage
import Shared

/// A class that adheres to all the requirements for a profile's pinned sites
class MockablePinnedSites: PinnedSites, @unchecked Sendable {
    func remove(pinnedSite site: Storage.Site) async throws { }
    var addPinnedTopSiteCalledCount = 0
    var removeFromPinnedTopSitesCalledCount = 0
    func removeFromPinnedTopSites(_ site: Site) -> Success {
        removeFromPinnedTopSitesCalledCount += 1
        return Success()
    }
    func isPinnedTopSite(_ url: String) -> Deferred<Maybe<Bool>> { deferMaybe(false) }
    func addPinnedTopSite(_ site: Site) -> Success {
        addPinnedTopSiteCalledCount += 1
        return Success()
    }
    func addPinnedTopSite(_ site: Site, completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        addPinnedTopSiteCalledCount += 1
        completion(.success(()))
    }
    func getPinnedTopSites() -> Deferred<Maybe<Cursor<Site>>> { fatalError() }

    func removeFromPinnedTopSites(_ site: Site) async throws {
        removeFromPinnedTopSitesCalledCount += 1
    }
    func isPinnedTopSite(_ url: String) async throws -> Bool { false }
    func addPinnedTopSite(_ site: Site) async throws {
        addPinnedTopSiteCalledCount += 1
    }
    func getPinnedTopSites() async throws -> Cursor<Site> { fatalError() }
}
