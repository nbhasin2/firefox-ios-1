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

@MainActor
let middlewares = [
    MicrosurveyPromptMiddleware().microsurveyProvider,
    TabManagerMiddleware().tabsPanelProvider,
    ToolbarMiddleware().toolbarProvider,
    StartAtHomeMiddleware().startAtHomeProvider,
    SummarizerMiddleware().summarizerProvider,
    TranslationsMiddleware().translationsProvider
]

// In order for us to mock and test the middlewares easier,
// we change the store to be instantiated as a variable.
// For non testing builds, we leave the store as a constant.
#if TESTING
@MainActor
var store: any DefaultDispatchStore<AppState> = Store(
    state: AppState(),
    reducer: AppState.reducer,
    middlewares: AppConstants.isRunningUnitTest ? [] : middlewares
)
#else
@MainActor
let store: any DefaultDispatchStore<AppState> = Store(state: AppState(),
                                                      reducer: AppState.reducer,
                                                      middlewares: middlewares)
#endif
