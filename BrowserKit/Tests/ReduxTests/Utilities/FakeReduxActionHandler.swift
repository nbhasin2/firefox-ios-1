// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Foundation

@testable import Redux

let windowUUID = UUID(uuidString: "D9D9D9D9-D9D9-D9D9-D9D9-CD68A019860B")!

/// A stand-in for the services that were middlewares: it hears a command action, does the work, and
/// announces the result as another action.
///
/// It owns `counter` rather than reading it out of the store, which is the shape every consumer has
/// now that the store holds no state.
@MainActor
final class FakeReduxActionHandler {
    var generateInitialCountValue: (() -> Int)?

    private(set) var counter = 0
    private(set) var isInPrivateMode = false

    private weak var bus: (any BrowserEventBusing)?

    func register(on bus: any BrowserEventBusing) {
        self.bus = bus
        bus.addActionObserver(self, tier: .effects) { [weak self] action in
            self?.handle(action)
        }
        bus.addModernActionObserver(self, tier: .effects) { [weak self] action, windowUUID in
            self?.handle(action, forWindowUUID: windowUUID)
        }
    }

    private func handle(_ action: Action) {
        guard let actionType = action.actionType as? FakeReduxActionType else { return }

        switch actionType {
        case .requestInitialValue:
            counter = generateInitialCountValue?() ?? 0
            bus?.dispatch(FakeReduxAction(counterValue: counter,
                                          windowUUID: windowUUID,
                                          actionType: FakeReduxActionType.initialValueLoaded))

        case .increaseCounter:
            counter += 1
            bus?.dispatch(FakeReduxAction(counterValue: counter,
                                          windowUUID: windowUUID,
                                          actionType: FakeReduxActionType.counterIncreased))

        case .decreaseCounter:
            counter -= 1
            bus?.dispatch(FakeReduxAction(counterValue: counter,
                                          windowUUID: windowUUID,
                                          actionType: FakeReduxActionType.counterDecreased))

        case .setPrivateModeTo:
            isInPrivateMode = (action as? FakeReduxAction)?.privateMode ?? isInPrivateMode

        default:
            break
        }
    }

    private func handle(_ action: ModernAction, forWindowUUID windowUUID: WindowUUID) {
        guard let action = action as? FakeReduxModernAction else { return }

        switch action {
        case .requestInitialValue:
            counter = generateInitialCountValue?() ?? 0
            bus?.dispatch(FakeReduxModernAction.initialValueLoaded(initialValue: counter),
                          forWindowUUID: windowUUID)

        case .increaseCounter:
            counter += 1
            bus?.dispatch(FakeReduxModernAction.counterIncreased(counterValue: counter),
                          forWindowUUID: windowUUID)

        case .decreaseCounter:
            counter -= 1
            bus?.dispatch(FakeReduxModernAction.counterDecreased(counterValue: counter),
                          forWindowUUID: windowUUID)

        case .setPrivateModeTo(let isPrivate):
            isInPrivateMode = isPrivate

        default:
            break
        }
    }
}
