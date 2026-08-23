// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Redux
import Storage
import XCTest

@testable import Client

final class DefaultSyncedTabProviderTests: XCTestCase, StoreTestUtility {
    var mockProfile: MockProfile!
    var mockStore: MockStore<AppState>!
    var appState: AppState!

    override func setUp() async throws {
        try await super.setUp()
        mockProfile = MockProfile()
        DependencyHelperMock().bootstrapDependencies()
        setupStore()
    }

    override func tearDown() async throws {
        mockProfile = nil
        DependencyHelperMock().reset()
        resetStore()
        try await super.tearDown()
    }

    /// The five tests here drove the middleware's homepage half through five different actions
    /// and asserted the same selection each time. The selection itself moved to
    /// `DefaultSyncedTabProvider`, where it is a pure function over the client list, and the
    /// triggers moved to `JumpBackInSectionViewModel` — see JumpBackInSectionViewModelTests.
    func test_mostRecentDesktopTab_picksTheLatestTabAcrossDesktopClients() throws {
        let clientAndTabs = [
            ClientAndTabs(client: remoteDesktopClient(), tabs: remoteTabs(idRange: 1...3))
        ]

        let mostRecent = try XCTUnwrap(DefaultSyncedTabProvider.mostRecentDesktopTab(from: clientAndTabs))

        XCTAssertEqual(mostRecent.client.name, "Fake client")
        XCTAssertEqual(mostRecent.tab.title, "Mozilla 3")
        XCTAssertEqual(mostRecent.tab.URL.absoluteString, "www.mozilla.org")
    }

    func test_mostRecentDesktopTab_ignoresMobileClients() {
        let mobileClient = RemoteClient(guid: nil,
                                        name: "Phone",
                                        modified: 1,
                                        type: "mobile",
                                        formfactor: nil,
                                        os: nil,
                                        version: nil,
                                        fxaDeviceId: nil)
        let clientAndTabs = [ClientAndTabs(client: mobileClient, tabs: remoteTabs(idRange: 1...3))]

        XCTAssertNil(DefaultSyncedTabProvider.mostRecentDesktopTab(from: clientAndTabs))
    }

    func test_mostRecentDesktopTab_withNoClients_returnsNil() {
        XCTAssertNil(DefaultSyncedTabProvider.mostRecentDesktopTab(from: []))
    }

    // MARK: - Helpers
    func remoteDesktopClient(name: String = "Fake client") -> RemoteClient {
        return RemoteClient(guid: nil,
                            name: name,
                            modified: 1,
                            type: "desktop",
                            formfactor: nil,
                            os: nil,
                            version: nil,
                            fxaDeviceId: nil)
    }

    func remoteTabs(idRange: ClosedRange<Int> = 1...1) -> [RemoteTab] {
        var remoteTabs: [RemoteTab] = []

        for index in idRange {
            let tab = RemoteTab(clientGUID: String(index),
                                URL: URL(string: "www.mozilla.org")!,
                                title: "Mozilla \(index)",
                                history: [],
                                lastUsed: UInt64(index),
                                icon: nil)
            remoteTabs.append(tab)
        }
        return remoteTabs
    }

    // MARK: StoreTestUtility
    func setupAppState() -> Client.AppState {
        appState = AppState()
        return appState
    }

    func setupStore() {
        mockStore = MockStore(state: setupAppState())
        StoreTestUtilityHelper.setupStore(with: mockStore)
    }

    func resetStore() {
        StoreTestUtilityHelper.resetStore()
    }
}
