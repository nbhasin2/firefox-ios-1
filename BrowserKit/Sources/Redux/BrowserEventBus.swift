// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import Common

/// A window-keyed channel for the browser-level events no single screen owns — the URL changed, a
/// tab was selected, the tab tray was dismissed.
///
/// It held the whole app's state once, with reducers deriving screens from it and subscribers
/// re-rendering on the diff. Every screen owns its own state now (FXIOS-16660), so what is left is
/// the part that was never about state: an action is dispatched, and the observers registered for
/// it are told, in a defined order, one action at a time.
@MainActor
public final class BrowserEventBus: ActionDispatching, ActionObserving {
    private let logger: Logger

    private var actionQueue: [(action: Either<Action, ModernAction>, windowUUID: WindowUUID)] = []
    private var isProcessingActions = false

    private struct ActionObserverBox {
        let id: ObjectIdentifier
        let tier: ActionObserverTier
        weak var observer: AnyObject?
        let handler: @MainActor (Action) -> Void
    }
    /// An array rather than a dictionary because delivery order is part of the contract: the
    /// services that replaced middlewares ran in a fixed order, and some of them react to actions
    /// the earlier ones dispatch. `.state` observers are delivered to before `.effects` ones, which
    /// is what running every reducer before any middleware used to guarantee.
    private var actionObservers: [ActionObserverBox] = []

    private struct ModernActionObserverBox {
        let id: ObjectIdentifier
        let tier: ActionObserverTier
        weak var observer: AnyObject?
        let handler: @MainActor (ModernAction, WindowUUID) -> Void
    }
    private var modernActionObservers: [ModernActionObserverBox] = []

    public init(logger: Logger = DefaultLogger.shared) {
        self.logger = logger
    }

    // MARK: - Dispatching

    /// Legacy method to dispatch actions onto the bus. Eventually will be deprecated and replaced by
    /// `dispatch(_action:forWindowUUID)`, which takes a `ModernAction`.
    public func dispatch(_ action: Action) {
        MainActor.assertIsolated("Expected to be called only on main actor.")
        logger.log("Dispatched action: \(action.debugDescription)", level: .info, category: .redux)

        // We queue and process actions to ensure each single action is completely delivered to the
        // observers before the next action fires.
        actionQueue.append((.legacy(action), action.windowUUID))
        processQueuedActions()
    }

    /// Method to dispatch actions onto the bus.
    public func dispatch(_ action: ModernAction, forWindowUUID windowUUID: WindowUUID) {
        MainActor.assertIsolated("Expected to be called only on main actor.")
        logger.log("Dispatched action: \(action.description)", level: .info, category: .redux)

        actionQueue.append((.modern(action), windowUUID))
        processQueuedActions()
    }

    private func processQueuedActions() {
        guard !isProcessingActions else { return }
        isProcessingActions = true
        while !actionQueue.isEmpty {
            let tuple = actionQueue.removeFirst()
            notifyActionObservers(of: tuple.action, forWindowUUID: tuple.windowUUID)
        }
        isProcessingActions = false
    }

    // MARK: - ActionObserving

    public func addActionObserver(_ observer: AnyObject,
                                  tier: ActionObserverTier,
                                  handler: @escaping @MainActor (Action) -> Void) {
        let id = ObjectIdentifier(observer)
        let box = ActionObserverBox(id: id, tier: tier, observer: observer, handler: handler)
        // Re-registering keeps the original position, so order does not depend on when a screen
        // happens to re-subscribe.
        if let index = actionObservers.firstIndex(where: { $0.id == id }) {
            actionObservers[index] = box
        } else {
            actionObservers.append(box)
        }
    }

    public func addModernActionObserver(_ observer: AnyObject,
                                        tier: ActionObserverTier,
                                        handler: @escaping @MainActor (ModernAction, WindowUUID) -> Void) {
        let id = ObjectIdentifier(observer)
        let box = ModernActionObserverBox(id: id, tier: tier, observer: observer, handler: handler)
        if let index = modernActionObservers.firstIndex(where: { $0.id == id }) {
            modernActionObservers[index] = box
        } else {
            modernActionObservers.append(box)
        }
    }

    public func removeActionObserver(_ observer: AnyObject) {
        let id = ObjectIdentifier(observer)
        actionObservers.removeAll { $0.id == id }
        modernActionObservers.removeAll { $0.id == id }
    }

    /// Only legacy actions carry their own `windowUUID`; observers filter on it themselves, as
    /// reducers used to.
    private func notifyActionObservers(of action: Either<Action, ModernAction>, forWindowUUID windowUUID: WindowUUID) {
        switch action {
        case .legacy(let legacyAction):
            guard !actionObservers.isEmpty else { return }
            // Drop deallocated observers first, so a handler cannot resurrect one mid-iteration.
            actionObservers = actionObservers.filter { $0.observer != nil }
            let observers = actionObservers
            for box in observers where box.tier == .state {
                box.handler(legacyAction)
            }
            for box in observers where box.tier == .effects {
                box.handler(legacyAction)
            }

        case .modern(let modernAction):
            guard !modernActionObservers.isEmpty else { return }
            modernActionObservers = modernActionObservers.filter { $0.observer != nil }
            let observers = modernActionObservers
            for box in observers where box.tier == .state {
                box.handler(modernAction, windowUUID)
            }
            for box in observers where box.tier == .effects {
                box.handler(modernAction, windowUUID)
            }
        }
    }
}
