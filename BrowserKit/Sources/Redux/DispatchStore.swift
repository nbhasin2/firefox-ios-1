// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import Common

/// Dispatching an action onto the bus. Separate from `ActionObserving` so a sender can be handed
/// the dispatch half without the ability to register observers.
@MainActor
public protocol DispatchStore {
    func dispatch(_ action: Action)
    func dispatch(_ action: ModernAction, forWindowUUID windowUUID: WindowUUID)
}

/// What the app's global bus is typed as: it both dispatches and takes observers.
public typealias DefaultDispatchStore = DispatchStore & ActionObserving
