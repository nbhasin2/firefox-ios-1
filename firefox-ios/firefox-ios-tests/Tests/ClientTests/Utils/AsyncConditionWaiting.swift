// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import XCTest

extension XCTestCase {
    /// Yields the main actor until `condition` holds, then returns; fails the test if it does not
    /// hold before `timeout`.
    ///
    /// The view models these tests drive load asynchronously, and a fixed number of `Task.yield()`
    /// calls is not a wait — the work can need more yields than that when the whole suite is
    /// running and the machine is loaded. That reads as a flake in one test rather than as the
    /// timeout it is, so the wait is bounded by time and says so when it expires.
    @MainActor
    func waitUntil(timeout: TimeInterval = 5,
                   file: StaticString = #filePath,
                   line: UInt = #line,
                   _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            await Task.yield()
        }
        XCTAssertTrue(condition(), "Condition was still false after \(timeout)s", file: file, line: line)
    }
}
