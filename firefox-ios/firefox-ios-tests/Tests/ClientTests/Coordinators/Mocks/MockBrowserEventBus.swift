// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import Common
import Redux

/// A mock Store used to test the services and view models that observe the action bus.
///
/// If you need to highly customize this mock to meet your testing needs, you should subclass it and/or make your own
/// mock implementation (e.g. storing a completion handler for asynchronous work so you can await expectations in your
/// tests).
class MockBrowserEventBus: BrowserEventBusing {
    /// Bus observers, so a test can assert on what a view model heard. Ordered and tiered like the
    /// real store's, so a test sees the same delivery order production does.
    private struct ObserverBox {
        let id: ObjectIdentifier
        let tier: ActionObserverTier
        let handler: @MainActor (Action) -> Void
    }
    private struct ModernObserverBox {
        let id: ObjectIdentifier
        let tier: ActionObserverTier
        let handler: @MainActor (ModernAction, WindowUUID) -> Void
    }
    private var observers: [ObserverBox] = []
    private var modernObservers: [ModernObserverBox] = []

    var actionObserverCount: Int { return observers.count }

    func addActionObserver(_ observer: AnyObject,
                           tier: ActionObserverTier,
                           handler: @escaping @MainActor (Action) -> Void) {
        let box = ObserverBox(id: ObjectIdentifier(observer), tier: tier, handler: handler)
        if let index = observers.firstIndex(where: { $0.id == box.id }) {
            observers[index] = box
        } else {
            observers.append(box)
        }
    }

    func addModernActionObserver(_ observer: AnyObject,
                                 tier: ActionObserverTier,
                                 handler: @escaping @MainActor (ModernAction, WindowUUID) -> Void) {
        let box = ModernObserverBox(id: ObjectIdentifier(observer), tier: tier, handler: handler)
        if let index = modernObservers.firstIndex(where: { $0.id == box.id }) {
            modernObservers[index] = box
        } else {
            modernObservers.append(box)
        }
    }

    func removeActionObserver(_ observer: AnyObject) {
        let id = ObjectIdentifier(observer)
        observers.removeAll { $0.id == id }
        modernObservers.removeAll { $0.id == id }
    }

    private let lock = NSLock()

    /// Records all actions dispatched to the mock store. Check this property to ensure that the code under test
    /// dispatches the right action(s), and the right count of actions, in response to a given action.
    var dispatchedActions: [Redux.Action] = []
    var dispatchedModernActions: [Redux.ModernAction] = []

    /// Called every time an action is dispatched to the mock store. Used to confirm that a dispatched action completed.
    /// This is useful when the code under test makes an asynchronous call and we want to await an expectation.
    var dispatchCalled: (() -> Void)?

    /// We implemented the lock to ensure that this is thread safe
    /// since actions can be dispatch in concurrent tasks
    func dispatch(_ action: Redux.Action) {
        lock.lock()
        dispatchedActions.append(action)
        let notified = observers
        lock.unlock()
        // Mirror the real store: bus observers see every dispatched legacy action, state tier first.
        notified.filter { $0.tier == .state }.forEach { $0.handler(action) }
        notified.filter { $0.tier == .effects }.forEach { $0.handler(action) }
        dispatchCalled?()
    }

    func dispatch(_ action: any Redux.ModernAction, forWindowUUID windowUUID: Common.WindowUUID) {
        lock.lock()
        dispatchedModernActions.append(action)
        let notified = modernObservers
        lock.unlock()
        notified.filter { $0.tier == .state }.forEach { $0.handler(action, windowUUID) }
        notified.filter { $0.tier == .effects }.forEach { $0.handler(action, windowUUID) }
        dispatchCalled?()
    }
}
