// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Foundation
import Redux

/// Owns `ToolbarState` in place of the store's `.toolbar` screen state.
///
/// The toolbar is the one screen where the actions genuinely belong on the retained bus (D-016):
/// almost everything it shows is browser state announced from elsewhere — the URL changed, the
/// page finished loading, reader mode became available, the tab count moved. Those announcements
/// come from `BrowserViewController`, the tab manager, settings and the search-engine picker, none
/// of which owns the toolbar.
///
/// So the transitions stay exactly as they were — `ToolbarState.reduce` is the reducer body,
/// unchanged and still a pure function — and what goes is the screen state in the store, the
/// subscription, and the `.toolbar` `AppComponent` case. The four toolbar views observe this
/// instead.
@MainActor
final class ToolbarViewModel {
    /// One per window. The toolbar's four views are all created by `BrowserViewController` for a
    /// single window, and each needs the same state.
    private static var instances = [WindowUUID: ToolbarViewModel]()

    static func instance(for windowUUID: WindowUUID) -> ToolbarViewModel {
        if let existing = instances[windowUUID] { return existing }
        let created = ToolbarViewModel(windowUUID: windowUUID)
        instances[windowUUID] = created
        return created
    }

    static func removeInstance(for windowUUID: WindowUUID) {
        instances.removeValue(forKey: windowUUID)
    }

    /// Test seam: the registry is static, so a state one test seeds would otherwise be read by the
    /// next one. Called from `StoreTestUtilityHelper.resetStore`.
    static func removeAllInstances() {
        instances.removeAll()
    }

    /// Test seam: seeds the instance a window's views and reducers will read.
    static func register(_ viewModel: ToolbarViewModel, for windowUUID: WindowUUID) {
        instances[windowUUID] = viewModel
    }

    private(set) var state: ToolbarState {
        didSet {
            guard state != oldValue else { return }
            observers = observers.filter { $0.value.observer != nil }
            observers.values.forEach { $0.handler(state) }
        }
    }

    private struct ObserverBox {
        weak var observer: AnyObject?
        let handler: (ToolbarState) -> Void
    }

    private var observers: [ObjectIdentifier: ObserverBox] = [:]

    private let windowUUID: WindowUUID
    /// The store holds observers weakly and sweeps dead ones, so there is nothing to unregister.
    private let bus: (any ActionObserving)?

    init(windowUUID: WindowUUID,
         bus: (any ActionObserving)? = store,
         initialState: ToolbarState? = nil) {
        self.windowUUID = windowUUID
        self.bus = bus
        self.state = initialState ?? ToolbarState(windowUUID: windowUUID)
        observeActions()
    }

    // MARK: - Observing

    func addObserver(_ observer: AnyObject, handler: @escaping (ToolbarState) -> Void) {
        observers[ObjectIdentifier(observer)] = ObserverBox(observer: observer, handler: handler)
    }

    func removeObserver(_ observer: AnyObject) {
        observers.removeValue(forKey: ObjectIdentifier(observer))
    }

    // MARK: - Private

    private func observeActions() {
        bus?.addActionObserver(self) { [weak self] action in
            guard let self else { return }
            self.state = ToolbarState.reduce(self.state, with: action)
        }
        bus?.addModernActionObserver(self) { [weak self] action, actionWindowUUID in
            guard let self,
                  actionWindowUUID == self.windowUUID,
                  let action = action as? ToolbarModernAction
            else { return }
            self.state = ToolbarState.reduceModern(self.state, with: action)
        }
    }
}
