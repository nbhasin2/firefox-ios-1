// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import Common
@testable import Redux

/// Records what the bus delivered. Replaces `MockState`, which recorded the same thing one layer
/// further in — the reducer the store used to run before notifying anyone.
@MainActor
final class MockActionObserver {
    private(set) var receivedActions = [ActionType]()
    private(set) var receivedModernActions = [(ModernAction, WindowUUID)]()

    /// Run from inside the handler, to show that an action is delivered in full before the next
    /// one starts. Cleared after it runs once.
    var midDeliveryActions: (() -> Void)?

    func observe(_ bus: any ActionObserving, tier: ActionObserverTier = .state) {
        bus.addActionObserver(self, tier: tier) { [weak self] action in
            guard let self else { return }
            self.receivedActions.append(action.actionType)
            let midDelivery = self.midDeliveryActions
            self.midDeliveryActions = nil
            midDelivery?()
        }
        bus.addModernActionObserver(self, tier: tier) { [weak self] action, windowUUID in
            self?.receivedModernActions.append((action, windowUUID))
        }
    }
}
