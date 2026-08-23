// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import Redux
@testable import Client
import XCTest

@MainActor
protocol BusTestUtility {
    func setupBus()
    func resetBus()
}

/// Utility class used when replacing the global bus for testing purposes
class BusTestUtilityHelper {
    @MainActor
    static func setupBus() {
#if TESTING
        browserEventBus = BrowserEventBus()
#endif
    }

    @MainActor
    static func setupBus(with mockBus: any BrowserEventBusing) {
#if TESTING
        browserEventBus = mockBus
#endif
    }

    /// In order to avoid flaky tests, we should reset the bus similar to production
    @MainActor
    static func resetBus() {
#if TESTING
        browserEventBus = BrowserEventBus()
        // Static per-window registries outlive a single test, so a state a previous test seeded
        // would otherwise be read by the next one.
        ToolbarViewModel.removeAllInstances()
#endif
    }
}
