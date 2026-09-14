// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import Redux
import Common
import ModifiedCopy

@Copyable
struct MicrosurveyPromptState: ResettableState {
    var windowUUID: WindowUUID
    var showPrompt: Bool
    var showSurvey: Bool
    var model: MicrosurveyModel?

    init(windowUUID: WindowUUID) {
        self.init(windowUUID: windowUUID,
                  showPrompt: false,
                  showSurvey: false,
                  model: nil)
    }

    init(windowUUID: WindowUUID,
         showPrompt: Bool,
         showSurvey: Bool,
         model: MicrosurveyModel?) {
        self.windowUUID = windowUUID
        self.showPrompt = showPrompt
        self.showSurvey = showSurvey
        self.model = model
    }

    /// The reducer body, unchanged; what went is the tuple the store used to call it through.
    @MainActor
    static func reduce(_ state: MicrosurveyPromptState, with action: Action) -> MicrosurveyPromptState {
        return legacyReducer(state, action)
    }

    @MainActor

    static func reduceModern(_ state: MicrosurveyPromptState, with action: ModernAction) -> MicrosurveyPromptState {
        return modernReducer(state, action, state.windowUUID)
    }

    @MainActor

    static func modernReducer(_ state: Self, _ action: ModernAction, _ actionWindowUUID: WindowUUID) -> Self {
        // Does not handle any modern actions
        return defaultState(from: state)
    }

    @MainActor

    static func legacyReducer(_ state: Self, _ action: Action) -> Self {
        guard action.windowUUID == .unavailable || action.windowUUID == state.windowUUID
        else {
            return defaultState(from: state)
        }

        switch action.actionType {
        case MicrosurveyPromptMiddlewareActionType.initialize:
            return handleInitializeAction(state: state, action: action)
        case MicrosurveyPromptActionType.closePrompt:
            return handleClosePromptAction(state: state)
        case MicrosurveyPromptActionType.continueToSurvey:
            return handleContinueToSurveyAction(state: state)
        default:
            return defaultState(from: state)
        }
    }

    static func defaultState(from state: MicrosurveyPromptState) -> MicrosurveyPromptState {
        return MicrosurveyPromptState(
            windowUUID: state.windowUUID,
            showPrompt: state.showPrompt,
            showSurvey: false,
            model: state.model
        )
    }

    private static func handleInitializeAction(state: Self, action: Action) -> Self {
        let model = (action as? MicrosurveyPromptMiddlewareAction)?.microsurveyModel
        return state
            .resetTransientState()
            .copy(showPrompt: true)
            .copy(model: model)
    }

    private static func handleClosePromptAction(state: Self) -> Self {
        return state
            .resetTransientState()
            .copy(showPrompt: false)
    }

    private static func handleContinueToSurveyAction(state: Self) -> Self {
        return state
            .resetTransientState()
            .copy(showPrompt: true)
            .copy(showSurvey: true)
    }
}
