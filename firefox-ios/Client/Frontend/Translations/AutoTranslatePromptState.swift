// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import Redux
import Common
import ModifiedCopy

@Copyable
struct AutoTranslatePromptState: ResettableState {
    var windowUUID: WindowUUID
    var showPrompt: Bool

    init(windowUUID: WindowUUID) {
        self.init(windowUUID: windowUUID, showPrompt: false)
    }

    init(windowUUID: WindowUUID, showPrompt: Bool) {
        self.windowUUID = windowUUID
        self.showPrompt = showPrompt
    }

    /// The reducer body, unchanged; what went is the tuple the store used to call it through.
    @MainActor
    static func reduce(_ state: AutoTranslatePromptState, with action: Action) -> AutoTranslatePromptState {
        return legacyReducer(state, action)
    }

    @MainActor

    static func reduceModern(_ state: AutoTranslatePromptState, with action: ModernAction) -> AutoTranslatePromptState {
        return modernReducer(state, action, state.windowUUID)
    }

    @MainActor

    static func modernReducer(_ state: Self, _ action: ModernAction, _ actionWindowUUID: WindowUUID) -> Self {
        // Does not handle any modern actions
        return defaultState(from: state)
    }

    @MainActor

    static func legacyReducer(_ state: Self, _ action: Action) -> Self {
        guard action.windowUUID == .unavailable || action.windowUUID == state.windowUUID else {
            return defaultState(from: state)
        }

        switch action.actionType {
        case TranslationsActionType.showAutoTranslatePrompt:
            return state.copy(showPrompt: true)
        case TranslationsActionType.didTapEnableAutoTranslate,
             TranslationsActionType.didDismissAutoTranslatePrompt:
            return state.copy(showPrompt: false)
        default:
            return defaultState(from: state)
        }
    }

    static func defaultState(from state: AutoTranslatePromptState) -> AutoTranslatePromptState {
        return AutoTranslatePromptState(windowUUID: state.windowUUID, showPrompt: state.showPrompt)
    }
}
