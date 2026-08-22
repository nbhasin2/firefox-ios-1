// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import Common

/// Observing dispatched actions directly, rather than deriving them from a state change.
///
/// This is the subscribe half of the browser event bus. `StoreSubscriber` answers "the state
/// changed, re-render", which requires the observer to keep state in the store. A view model that
/// owns its own state still needs to hear about cross-cutting browser events — a tab changed, the
/// toolbar was unhidden — without putting a `ScreenState` back into the tree to hang a
/// subscription off.
@MainActor
public protocol ActionObserving: AnyObject {
    /// Registers `observer` for every dispatched action until `removeActionObserver` is called or
    /// the observer is deallocated. Observers are held weakly.
    func addActionObserver(_ observer: AnyObject, handler: @escaping @MainActor (Action) -> Void)
    func removeActionObserver(_ observer: AnyObject)
}
