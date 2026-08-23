// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Foundation
import Redux

/// The store's state, now that every screen owns its own (FXIOS-16660).
///
/// It is empty and stays that way. What the store is still for is the browser event bus (D-016):
/// a typed, window-keyed channel for the cross-cutting announcements no single screen owns — the
/// URL changed, a tab was selected, the tab tray was dismissed. `Store` keeps its dispatch and its
/// action-observer list; what it no longer keeps is screens.
struct AppState: StateType, Sendable {
    static let reducer: Reducer<Self> = (legacyReducer, modernReducer)

    static let modernReducer: ReducerMethod<Self> = { state, _, _ in state }

    static let legacyReducer: LegacyReducerMethod<Self> = { state, _ in state }

    static func defaultState(from state: AppState) -> AppState {
        return state
    }
}

// In order for us to mock and test the services easier,
// we change the store to be instantiated as a variable.
// For non testing builds, we leave the store as a constant.
#if TESTING
@MainActor
var store: any DefaultDispatchStore<AppState> = Store(
    state: AppState(),
    reducer: AppState.reducer,
    middlewares: []
)
#else
@MainActor
let store: any DefaultDispatchStore<AppState> = Store(state: AppState(),
                                                      reducer: AppState.reducer,
                                                      middlewares: [])
#endif

/// The six services that were middlewares. None of them has a screen or a state — each reacts to
/// browser events and performs work or announces another event, which is what the bus is for
/// (D-016). They are registered in the order the middleware array had them, because some react to
/// what an earlier one dispatches.
///
/// Held for the app's lifetime: the store keeps observers weakly.
@MainActor
final class BrowserActionServices {
    static let shared = BrowserActionServices()

    private let microsurveyPrompt = MicrosurveyPromptMiddleware()
    private let tabManager = TabManagerMiddleware()
    private let toolbar = ToolbarMiddleware()
    private let startAtHome = StartAtHomeMiddleware()
    private let summarizer = SummarizerMiddleware()
    private let translations = TranslationsMiddleware()

    private var isRegistered = false

    func register(on bus: any ActionObserving = store) {
        guard !isRegistered else { return }
        isRegistered = true

        bus.addActionObserver(microsurveyPrompt) { [microsurveyPrompt] in microsurveyPrompt.handle($0) }
        bus.addActionObserver(tabManager) { [tabManager] in tabManager.handle($0) }
        bus.addActionObserver(toolbar) { [toolbar] in toolbar.handle($0) }
        bus.addActionObserver(startAtHome) { [startAtHome] in startAtHome.handle($0) }
        bus.addActionObserver(summarizer) { [summarizer] in summarizer.handle($0) }
        bus.addActionObserver(translations) { [translations] in translations.handle($0) }
    }
}
