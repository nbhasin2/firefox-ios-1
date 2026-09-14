// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Foundation

@MainActor
protocol SearchBarVisibilityReading: AnyObject {
    func isSearchBarVisible(for windowUUID: WindowUUID) -> Bool
}

/// Publishes whether the homepage is showing its own search bar, per window.
///
/// `BrowserViewController` and `BrowserViewControllerState`'s reducer both need this to decide
/// whether to hide the address toolbar, and neither can hold a reference to the homepage's view
/// model — the reducer is a static function. They read `HomepageState.searchState` today.
///
/// This is deliberately narrow: one boolean per window, written only by `SearchBarViewModel`. It
/// exists because BrowserViewController has not migrated yet; once it has, it can ask the embedded
/// homepage controller directly and this goes away (PLAN.md Phase 3, module 18).
@MainActor
final class SearchBarVisibilityStore: SearchBarVisibilityReading {
    static let shared = SearchBarVisibilityStore()

    private var visibilityByWindow: [WindowUUID: Bool] = [:]

    func setSearchBarVisible(_ isVisible: Bool, for windowUUID: WindowUUID) {
        visibilityByWindow[windowUUID] = isVisible
    }

    func isSearchBarVisible(for windowUUID: WindowUUID) -> Bool {
        return visibilityByWindow[windowUUID] ?? false
    }
}
