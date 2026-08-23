// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import Redux
@testable import Client
import XCTest

@MainActor
protocol StoreTestUtility {
    func setupAppState() -> AppState
    func setupStore()
    func resetStore()
}

/// Utility class used when replacing the global store for testing purposes
class StoreTestUtilityHelper {
    @MainActor
    static func setupStore(with appState: AppState) {
#if TESTING
        store = Store(state: appState, reducer: AppState.reducer)
#endif
    }
    @MainActor
    static func setupStore(with mockStore: any DefaultDispatchStore<AppState>) {
#if TESTING
        store = mockStore
#endif
    }

    /// In order to avoid flaky tests, we should reset the store similar to production
    @MainActor
    static func resetStore() {
#if TESTING
        store = Store(state: AppState(), reducer: AppState.reducer)
        // Static per-window registries outlive a single test, so a state a previous test seeded
        // would otherwise be read by the next one.
        ToolbarViewModel.removeAllInstances()
#endif
    }
}
