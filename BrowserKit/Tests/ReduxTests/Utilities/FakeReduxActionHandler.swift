// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Foundation

@testable import Redux

/// Registered on the store's action bus in place of the middleware this used to be. It reads
/// `store.state` where the middleware was handed the state, which is the same value: observers are
/// notified after the reducer has run and the new state has been assigned.
@MainActor
class FakeReduxActionHandler {
    var generateInitialCountValue: (() -> Int)?

    func register(on store: any ActionObserving) {
        store.addActionObserver(self, tier: .effects) { [weak self] action in
            self?.handle(action)
        }
        store.addModernActionObserver(self, tier: .effects) { [weak self] action, windowUUID in
            self?.handle(action, forWindowUUID: windowUUID)
        }
    }

    private func handle(_ action: ModernAction, forWindowUUID windowUUID: WindowUUID) {
        // Handles one type of action
        guard let action = action as? FakeReduxModernAction else { return }
        let state = store.state

        switch action {
        case .requestInitialValue:
            let initialValue = self.generateInitialCountValue?() ?? 0
            store.dispatch(
                FakeReduxModernAction.initialValueLoaded(initialValue: initialValue),
                forWindowUUID: windowUUID
            )

        case .increaseCounter:
            let existingValue = state.counter
            let newValue = self.increaseCounter(currentValue: existingValue)
            store.dispatch(
                FakeReduxModernAction.counterIncreased(counterValue: newValue),
                forWindowUUID: windowUUID
            )

        case .decreaseCounter:
            let existingValue = state.counter
            let newValue = self.decreaseCounter(currentValue: existingValue)
            store.dispatch(
                FakeReduxModernAction.counterDecreased(counterValue: newValue),
                forWindowUUID: windowUUID
            )

        default:
            break
        }
    }

    private func handle(_ action: Action) {
        // Handles one type of action
        guard let actionType = action.actionType as? FakeReduxActionType else { return }
        let state = store.state

        switch actionType {
        case .requestInitialValue:
            let initialValue = self.generateInitialCountValue?() ?? 0
            let action = FakeReduxAction(counterValue: initialValue,
                                         windowUUID: windowUUID,
                                         actionType: FakeReduxActionType.initialValueLoaded)
            store.dispatch(action)

        case .increaseCounter:
            let existingValue = state.counter
            let newValue = self.increaseCounter(currentValue: existingValue)
            let action = FakeReduxAction(counterValue: newValue,
                                         windowUUID: windowUUID,
                                         actionType: FakeReduxActionType.counterIncreased)
            store.dispatch(action)

        case .decreaseCounter:
            let existingValue = state.counter
            let newValue = self.decreaseCounter(currentValue: existingValue)
            let action = FakeReduxAction(counterValue: newValue,
                                         windowUUID: windowUUID,
                                         actionType: FakeReduxActionType.counterDecreased)
            store.dispatch(action)

        default:
           break
        }
    }

    private func increaseCounter(currentValue: Int) -> Int {
        return currentValue + 1
    }

    private func decreaseCounter(currentValue: Int) -> Int {
        return currentValue - 1
    }
}
