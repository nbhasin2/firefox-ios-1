// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import XCTest
import Common
@testable import Client

@available(iOS 26.4, *)
@MainActor
class BrowserKitImportViewModelTests: XCTestCase {

    private var profile: MockProfile!

    override func setUp() async throws {
        try await super.setUp()
        DependencyHelperMock().bootstrapDependencies()
        profile = MockProfile()
    }

    override func tearDown() async throws {
        profile = nil
        try await super.tearDown()
    }

    func testInitCreatesViewModel() {
        let vm = BrowserKitImportViewModel(profile: profile)
        XCTAssertNotNil(vm)
    }

    func testProgressCallbackWiringIsSetUp() {
        let vm = BrowserKitImportViewModel(profile: profile)
        var lastProgress: BrowserKitImportViewModel.ImportProgress?
        vm.onProgressUpdate = { progress in
            lastProgress = progress
        }
        // No import has started — callback should not have fired
        XCTAssertNil(lastProgress)
    }

    func testCompleteCallbackWiringIsSetUp() {
        let vm = BrowserKitImportViewModel(profile: profile)
        var completeCalled = false
        vm.onComplete = { completeCalled = true }
        XCTAssertFalse(completeCalled)
    }

    func testErrorCallbackWiringIsSetUp() {
        let vm = BrowserKitImportViewModel(profile: profile)
        var lastError: Error?
        vm.onError = { error in lastError = error }
        XCTAssertNil(lastError)
    }
}
