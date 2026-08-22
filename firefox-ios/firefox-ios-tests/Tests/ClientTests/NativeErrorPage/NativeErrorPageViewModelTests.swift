// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import XCTest

@testable import Client

/// Replaces `NativeErrorPageStateTests` and `NativeErrorPageMiddlewareTests`: the reducer only
/// ever set `model`, and the middleware's two behaviours (build the model, bypass the certificate)
/// are now intents here.
@MainActor
final class NativeErrorPageViewModelTests: XCTestCase {
    private var errorStore: NativeErrorPageErrorStore!

    override func setUp() async throws {
        try await super.setUp()
        await DependencyHelperMock().bootstrapDependencies()
        errorStore = NativeErrorPageErrorStore()
    }

    override func tearDown() async throws {
        errorStore = nil
        DependencyHelperMock().reset()
        try await super.tearDown()
    }

    // MARK: - Loading the model

    func test_loadErrorModel_withNoRecordedError_publishesNothing() {
        let subject = createSubject()
        var received: [ErrorPageModel] = []
        subject.onModelChange = { received.append($0) }

        subject.loadErrorModel()

        XCTAssertNil(subject.model)
        XCTAssertTrue(received.isEmpty)
    }

    func test_loadErrorModel_withARecordedError_publishesTheParsedModel() throws {
        errorStore.record(error: makeNoInternetError(), for: .XCTestDefaultUUID)
        let subject = createSubject()
        var received: [ErrorPageModel] = []
        subject.onModelChange = { received.append($0) }

        subject.loadErrorModel()

        let model = try XCTUnwrap(subject.model)
        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received.first, model)
        XCTAssertTrue(model.isRegularUI, "A network error renders the regular layout, not the bad-cert one")
    }

    func test_loadErrorModel_calledAgain_republishesForAnAlreadyVisiblePage() {
        errorStore.record(error: makeNoInternetError(), for: .XCTestDefaultUUID)
        let subject = createSubject()
        var received: [ErrorPageModel] = []
        subject.onModelChange = { received.append($0) }

        subject.loadErrorModel()
        subject.loadErrorModel()

        // This is the coordinator's refresh path, which used to rely on the Redux subscription.
        XCTAssertEqual(received.count, 2)
    }

    func test_loadErrorModel_readsOnlyThisWindowsError() {
        errorStore.record(error: makeNoInternetError(), for: WindowUUID(uuidString: UUID().uuidString)!)
        let subject = createSubject()

        subject.loadErrorModel()

        // The middleware held one helper app-wide, so another window's error would have leaked in.
        XCTAssertNil(subject.model)
    }

    // MARK: - Certificate bypass

    func test_bypassCertificateWarning_withNoSelectedTab_returnsEarly() {
        let subject = createSubject(tabManager: MockTabManager())

        subject.bypassCertificateWarning()

        XCTAssertNil(subject.model)
    }

    func test_bypassCertificateWarning_withNoRecordedError_returnsEarly() {
        let tabManager = MockTabManager()
        tabManager.selectedTab = Tab(profile: MockProfile(), windowUUID: .XCTestDefaultUUID)
        let subject = createSubject(tabManager: tabManager)

        subject.bypassCertificateWarning()

        XCTAssertNil(subject.model)
    }

    // MARK: - Private Helpers

    private func makeNoInternetError() -> NSError {
        return NSError(
            domain: NSURLErrorDomain,
            code: Int(CFNetworkErrors.cfurlErrorNotConnectedToInternet.rawValue),
            userInfo: [NSURLErrorFailingURLErrorKey: URL(string: "https://example.com")!]
        )
    }

    private func createSubject(tabManager: MockTabManager = MockTabManager()) -> NativeErrorPageViewModel {
        let subject = NativeErrorPageViewModel(
            windowUUID: .XCTestDefaultUUID,
            errorStore: errorStore,
            windowManager: MockWindowManager(
                wrappedManager: WindowManagerImplementation(),
                tabManager: tabManager
            )
        )
        trackForMemoryLeaks(subject)
        return subject
    }
}
