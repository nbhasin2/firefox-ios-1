// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import Shared
@testable import Storage

import XCTest

class TestSQLitePinnedSites: XCTestCase {
    lazy var files = makeTemporaryFiles()
    @discardableResult
    private func chainSuccess(
        _ initial: @Sendable () -> Success,
        _ steps: @Sendable () -> Success...
    ) -> Success {
        return steps.reduce(initial()) { current, next in
            current.bind { result in
                if result.isSuccess {
                    return next()
                }

                return deferMaybe(result.failureValue!)
            }
        }
    }

    func testPinnedTopSites() {
        let database = BrowserDB(filename: "testPinnedTopSites.db", schema: BrowserSchema(), files: files)
        let prefs = MockProfilePrefs()
        let pinnedSites = BrowserDBSQLite(database: database, prefs: prefs)

        // add 2 sites to pinned topsite
        // get pinned site and make sure it exists in the right order
        // remove pinned sites
        // make sure pinned sites dont exist

        // create pinned sites.
        let site1 = Site.createBasicSite(url: "http://s\(1)ite\(1).com/foo", title: "A \(1)")
        let site2 = Site.createBasicSite(url: "http://s\(2)ite\(2).com/foo", title: "A \(2)")

        let expectation = self.expectation(description: "First.")
        let done: @Sendable () -> Success = {
            expectation.fulfill()
            return succeed()
        }

        let addPinnedSites: @Sendable () -> Success = {
            return pinnedSites.addPinnedTopSite(site1).bind { result in
                if let error = result.failureValue {
                    return deferMaybe(error)
                }
                sleep(1) // Sleep to prevent intermittent issue with sorting on the timestamp
                return pinnedSites.addPinnedTopSite(site2)
            }
        }

        let checkPinnedSites: @Sendable () -> Success = {
            return pinnedSites.getPinnedTopSites().bind { result in
                if let pinnedSites = result.successValue {
                    XCTAssertEqual(pinnedSites.count, 2)
                    XCTAssertEqual(pinnedSites[0]?.url, site2.url)
                    XCTAssertEqual(pinnedSites[1]?.url, site1.url, "The older pinned site should be last")
                    return succeed()
                }

                return deferMaybe(result.failureValue!)
            }
        }

        let removePinnedSites: @Sendable () -> Success = {
            return pinnedSites.removeFromPinnedTopSites(site2).bind { removalResult in
                if removalResult.isFailure {
                    return deferMaybe(removalResult.failureValue!)
                }

                return pinnedSites.getPinnedTopSites().bind { result in
                    if let pinnedSites = result.successValue {
                        XCTAssertEqual(pinnedSites.count, 1, "There should only be one pinned site")
                        XCTAssertEqual(pinnedSites[0]?.url, site1.url, "Site1 should be the only pin left")
                        return succeed()
                    }

                    return deferMaybe(result.failureValue!)
                }
            }
        }

        let dupePinnedSite: @Sendable () -> Success = {
            return pinnedSites.addPinnedTopSite(site1).bind { result in
                if let error = result.failureValue {
                    return deferMaybe(error)
                }
                return pinnedSites.getPinnedTopSites().bind { result in
                    if let pinnedSites = result.successValue {
                        XCTAssertEqual(pinnedSites.count, 1, "There should not be a dupe")
                        XCTAssertEqual(pinnedSites[0]?.url, site1.url, "Site1 should still be the only pin")
                        return succeed()
                    }

                    return deferMaybe(result.failureValue!)
                }
            }
        }

        chainSuccess(
            addPinnedSites,
            checkPinnedSites,
            removePinnedSites,
            dupePinnedSite,
            done
        )

        wait(for: [expectation], timeout: 3)
    }

    func testPinnedTopSitesDuplicateDomains() {
        let database = BrowserDB(
            filename: "testPinnedTopSitesDuplicateDomains.db",
            schema: BrowserSchema(),
            files: files
        )
        let prefs = MockProfilePrefs()
        let pinnedSites = BrowserDBSQLite(database: database, prefs: prefs)

        // create pinned sites with a same domain name
        let site1 = Site.createBasicSite(url: "http://site.com/foo1", title: "A duplicate domain \(1)")
        let site2 = Site.createBasicSite(url: "http://site.com/foo2", title: "A duplicate domain \(2)")

        let expectation = self.expectation(description: "First.")
        let done: @Sendable () -> Success = {
            expectation.fulfill()
            return succeed()
        }

        let addPinnedSites: @Sendable () -> Success = {
            return pinnedSites.addPinnedTopSite(site1).bind { result in
                if let error = result.failureValue {
                    return deferMaybe(error)
                }
                sleep(1) // Sleep to prevent intermittent issue with sorting on the timestamp
                return pinnedSites.addPinnedTopSite(site2)
            }
        }

        let checkPinnedSites: @Sendable () -> Success = {
            return pinnedSites.getPinnedTopSites().bind { result in
                if let pinnedSites = result.successValue {
                    XCTAssertEqual(pinnedSites.count, 2)
                    XCTAssertEqual(pinnedSites[0]?.url, site2.url)
                    XCTAssertEqual(pinnedSites[1]?.url, site1.url, "The older pinned site should be last")
                    return succeed()
                }

                return deferMaybe(result.failureValue!)
            }
        }

        let removePinnedSites: @Sendable () -> Success = {
            return pinnedSites.removeFromPinnedTopSites(site2).bind { removalResult in
                if removalResult.isFailure {
                    return deferMaybe(removalResult.failureValue!)
                }

                return pinnedSites.getPinnedTopSites().bind { result in
                    if let pinnedSites = result.successValue {
                        XCTAssertEqual(pinnedSites.count, 0, "Duplicate pinned domains are removed with a fuzzy search")
                        return succeed()
                    }

                    return deferMaybe(result.failureValue!)
                }
            }
        }

        chainSuccess(
            addPinnedSites,
            checkPinnedSites,
            checkPinnedSites,
            removePinnedSites,
            done
        )

        wait(for: [expectation], timeout: 3)
    }

    func testPinnedTopSites_idOfMaxSizeInt64() {
        let database = BrowserDB(
            filename: "testPinnedTopSitesDuplicateDomains.db",
            schema: BrowserSchema(),
            files: files
        )
        let prefs = MockProfilePrefs()
        let pinnedSites = BrowserDBSQLite(database: database, prefs: prefs)

        // create pinned sites with a same domain name
        let site = Site.createPinnedSite(
            url: "http://site.com/foo1",
            title: "A domain",
            isGooglePinnedTile: false
        )

        let expectation = self.expectation(description: "Add site")
        let done: @Sendable () -> Success = {
            expectation.fulfill()
            return succeed()
        }

        let addPinnedSite: @Sendable () -> Success = {
            return pinnedSites.addPinnedTopSite(site)
        }

        let checkPinnedSite: @Sendable () -> Success = {
            return pinnedSites.getPinnedTopSites().bind { result in
                if let pinnedSites = result.successValue {
                    XCTAssertEqual(pinnedSites.count, 1)
                    XCTAssertEqual(pinnedSites[0]?.url, site.url)
                    XCTAssertEqual(pinnedSites[0]?.title, site.title)
                    return succeed()
                }

                return deferMaybe(result.failureValue!)
            }
        }

        let removePinnedSite: @Sendable () -> Success = {
            return pinnedSites.removeFromPinnedTopSites(site).bind { removalResult in
                if removalResult.isFailure {
                    return deferMaybe(removalResult.failureValue!)
                }

                return pinnedSites.getPinnedTopSites().bind { result in
                    if let pinnedSites = result.successValue {
                        XCTAssertEqual(pinnedSites.count, 0, "There should be no pinned sites")
                        return succeed()
                    }

                    return deferMaybe(result.failureValue!)
                }
            }
        }

        chainSuccess(
            addPinnedSite,
            checkPinnedSite,
            removePinnedSite,
            done
        )

        wait(for: [expectation], timeout: 3)
    }

    private func makeAsyncSubject(
        _ filename: String,
        notificationCenter: NotificationCenter = NotificationCenter()
    ) -> BrowserDBSQLite {
        let database = BrowserDB(filename: filename, schema: BrowserSchema(), files: files)
        return BrowserDBSQLite(database: database, prefs: MockProfilePrefs(), notificationCenter: notificationCenter)
    }

    func testPinnedTopSites_async() async throws {
        let subject = makeAsyncSubject("testPinnedTopSitesAsync.db")
        let site1 = Site.createBasicSite(url: "http://site1.com/foo", title: "A 1")
        let site2 = Site.createBasicSite(url: "http://site2.com/foo", title: "A 2")
        try await subject.addPinnedTopSite(site1)
        try await subject.addPinnedTopSite(site2)
        let pinned = try await subject.getPinnedTopSites()
        XCTAssertEqual(Set(pinned.asArray().map { $0.url }), [site1.url, site2.url])
        let isSite1Pinned = try await subject.isPinnedTopSite(site1.url)
        XCTAssertTrue(isSite1Pinned)
        try await subject.removeFromPinnedTopSites(site2)
        let remaining = try await subject.getPinnedTopSites()
        XCTAssertEqual(remaining.asArray().map { $0.url }, [site1.url])
        try await subject.addPinnedTopSite(site1)
        let afterDuplicate = try await subject.getPinnedTopSites()
        XCTAssertEqual(afterDuplicate.count, 1)
    }

    func testPinnedTopSitesDuplicateDomains_async() async throws {
        let subject = makeAsyncSubject("testPinnedTopSitesDuplicateDomainsAsync.db")
        let site1 = Site.createBasicSite(url: "http://site.com/foo1", title: "A duplicate domain 1")
        let site2 = Site.createBasicSite(url: "http://site.com/foo2", title: "A duplicate domain 2")
        try await subject.addPinnedTopSite(site1)
        try await subject.addPinnedTopSite(site2)
        let pinned = try await subject.getPinnedTopSites()
        XCTAssertEqual(pinned.count, 2)
        try await subject.removeFromPinnedTopSites(site2)
        let remaining = try await subject.getPinnedTopSites()
        XCTAssertEqual(remaining.count, 0, "Duplicate pinned domains are removed with a fuzzy search")
    }

    func testPinnedTopSites_invalidURL_async_throws() async {
        let subject = makeAsyncSubject("testPinnedTopSitesInvalidURLAsync.db")
        let site = Site.createBasicSite(url: "", title: "Invalid")
        do {
            try await subject.addPinnedTopSite(site)
            XCTFail("Expected addPinnedTopSite to throw")
        } catch {
            XCTAssertEqual((error as? DatabaseError)?.description, "Invalid site ")
        }
        do {
            try await subject.removeFromPinnedTopSites(site)
            XCTFail("Expected removeFromPinnedTopSites to throw")
        } catch {
            XCTAssertEqual((error as? DatabaseError)?.description, "Invalid url for site ")
        }
    }

    func testPinnedTopSites_async_postsTopSitesUpdated() async throws {
        let center = NotificationCenter()
        let subject = makeAsyncSubject("testPinnedTopSitesNotificationsAsync.db", notificationCenter: center)
        let site = Site.createBasicSite(url: "http://site.com/foo", title: "A")
        let added = XCTNSNotificationExpectation(name: .TopSitesUpdated, object: subject, notificationCenter: center)
        try await subject.addPinnedTopSite(site)
        await fulfillment(of: [added], timeout: 1)
        let removed = XCTNSNotificationExpectation(name: .TopSitesUpdated, object: subject, notificationCenter: center)
        try await subject.removeFromPinnedTopSites(site)
        await fulfillment(of: [removed], timeout: 1)
        try await subject.addPinnedTopSite(site)
        try await subject.remove(pinnedSite: site)
        let isPinned = try await subject.isPinnedTopSite(site.url)
        XCTAssertFalse(isPinned)
    }
}
