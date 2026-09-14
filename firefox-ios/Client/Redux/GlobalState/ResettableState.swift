// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation

/// A state value with transient fields — a toast to show once, a destination to navigate to once —
/// that have to be cleared after the owner has acted on them.
///
/// This is what is left of `StateType` and `ScreenState` after the store stopped holding state.
/// Neither the bus nor anything outside the owning view model reads it: it exists so that
/// `defaultState(from:)` stays the single description of which fields are transient, and every
/// reducer body that already calls `resetTransientState()` keeps working unchanged.
protocol ResettableState: Equatable {
    /// Returns a state with the transient fields of `state` cleared and everything else preserved.
    static func defaultState(from state: Self) -> Self
}

extension ResettableState {
    /// Call first in a `.copy()` chain, before field-specific overrides. If a field's reset behavior
    /// is handler-dependent (e.g. `toast` in `BrowserViewControllerState`), add
    /// `.copy(field: state.field)` after this call wherever it should be preserved.
    func resetTransientState() -> Self {
        return Self.defaultState(from: self)
    }
}
