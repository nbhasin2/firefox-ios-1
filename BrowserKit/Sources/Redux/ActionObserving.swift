// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import Common

/// When an observer is delivered an action, relative to the observers that own state.
///
/// Redux guaranteed that every reducer ran before any middleware, so a middleware always read
/// post-action state. Observers replaced both, and one flat list would lose that guarantee: a
/// service registered at launch would run before a view model created later and read state one
/// action behind.
public enum ActionObserverTier {
    /// Owns state and updates it from the action. Delivered first.
    case state
    /// Reacts to the action, possibly reading state a `.state` observer owns. Delivered second.
    case effects
}

/// Observing dispatched actions directly, rather than deriving them from a state change.
///
/// This is the subscribe half of the browser event bus. `StoreSubscriber` answers "the state
/// changed, re-render", which requires the observer to keep state in the bus. A view model that
/// owns its own state still needs to hear about cross-cutting browser events — a tab changed, the
/// toolbar was unhidden — without putting a `ScreenState` back into the tree to hang a
/// subscription off.
@MainActor
public protocol ActionObserving: AnyObject {
    /// Registers `observer` for every dispatched action until `removeActionObserver` is called or
    /// the observer is deallocated. Observers are held weakly, and within a tier are delivered to
    /// in registration order.
    func addActionObserver(_ observer: AnyObject,
                           tier: ActionObserverTier,
                           handler: @escaping @MainActor (Action) -> Void)

    /// `ModernAction`s carry their window separately, so they are a separate registration rather
    /// than a cast inside the legacy handler.
    func addModernActionObserver(_ observer: AnyObject,
                                 tier: ActionObserverTier,
                                 handler: @escaping @MainActor (ModernAction, WindowUUID) -> Void)

    /// Removes both the legacy and the modern registration.
    func removeActionObserver(_ observer: AnyObject)
}

public extension ActionObserving {
    /// Most observers own the state they update, so `.state` is the default; the services that
    /// read another observer's state ask for `.effects` explicitly.
    func addActionObserver(_ observer: AnyObject, handler: @escaping @MainActor (Action) -> Void) {
        addActionObserver(observer, tier: .state, handler: handler)
    }

    func addModernActionObserver(_ observer: AnyObject,
                                 handler: @escaping @MainActor (ModernAction, WindowUUID) -> Void) {
        addModernActionObserver(observer, tier: .state, handler: handler)
    }
}
