// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import ModifiedCopy
import Redux

@Copyable
struct HomepageState: ScreenState, Equatable {
    var windowUUID: WindowUUID

    // Homepage sections state in the order they appear on the collection view

    let telemetryState: HomepageTelemetryState

    /// `shouldShowPrivacyNotice` is true when the homepage should display the privacy notice card. This is the case when a
    /// new privacy notice is available after a user has already accepted the ToS/ToU
    let shouldShowPrivacyNotice: Bool

    init(appState: AppState, uuid: WindowUUID) {
        guard let homepageState = appState.componentState(
            HomepageState.self,
            for: .homepage,
            window: uuid
        ) else {
            self.init(windowUUID: uuid)
            return
        }

        self.init(
            windowUUID: homepageState.windowUUID,
            telemetryState: homepageState.telemetryState,
            shouldShowPrivacyNotice: homepageState.shouldShowPrivacyNotice
        )
    }

    init(windowUUID: WindowUUID) {
        self.init(
            windowUUID: windowUUID,
            telemetryState: HomepageTelemetryState(windowUUID: windowUUID),
            shouldShowPrivacyNotice: false,
        )
    }

    private init(
        windowUUID: WindowUUID,
        telemetryState: HomepageTelemetryState,
        shouldShowPrivacyNotice: Bool
    ) {
        self.windowUUID = windowUUID
        self.telemetryState = telemetryState
        self.shouldShowPrivacyNotice = shouldShowPrivacyNotice
    }

    static let reducer: Reducer<Self> = (legacyReducer, modernReducer)

    static let modernReducer: ReducerMethod<Self> = { state, action, actionWindowUUID in
        // Does not handle any modern actions
        return defaultState(from: state)
    }

    static let legacyReducer: LegacyReducerMethod<Self> = { state, action in
        guard action.windowUUID == .unavailable || action.windowUUID == state.windowUUID
        else {
            return passthroughState(from: state, action: action)
        }

        switch action.actionType {
        case HomepageActionType.initialize, HomepageActionType.viewWillTransition:
            return handleInitializeAndViewWillTransitionAction(state: state, action: action)
        case HomepageActionType.embeddedHomepage:
            return handleEmbeddedHomepageAction(state: state, action: action)
        case HomepageActionType.privacyNoticeCloseButtonTapped:
            return handlePrivacyNoticeCloseButtonTappedAction(state: state, action: action)
        case GeneralBrowserActionType.didSelectedTabChangeToHomepage:
            return handleDidTabChangeToHomepageAction(state: state, action: action)
        case HomepageMiddlewareActionType.configuredPrivacyNotice:
            return handlePrivacyNoticeInitialization(action: action, state: state)
        default:
            return passthroughState(from: state, action: action)
        }
    }

    @MainActor
    private static func handleInitializeAndViewWillTransitionAction(state: HomepageState, action: Action) -> HomepageState {
        return state
            .resetTransientState()
            .copy(telemetryState: HomepageTelemetryState.reducer.legacyReducer(state.telemetryState, action))
    }

    @MainActor
    private static func handleEmbeddedHomepageAction(state: HomepageState, action: Action) -> HomepageState {
        return state
            .resetTransientState()
            .copy(telemetryState: HomepageTelemetryState.reducer.legacyReducer(state.telemetryState, action))
    }

    @MainActor
    private static func handlePrivacyNoticeCloseButtonTappedAction(state: HomepageState, action: Action) -> HomepageState {
        return state
            .resetTransientState()
            .copy(telemetryState: HomepageTelemetryState.reducer.legacyReducer(state.telemetryState, action))
            .copy(shouldShowPrivacyNotice: false)
    }

    @MainActor
    private static func handleDidTabChangeToHomepageAction(state: HomepageState, action: Action) -> HomepageState {
        return state
            .resetTransientState()
            .copy(telemetryState: HomepageTelemetryState.reducer.legacyReducer(state.telemetryState, action))
    }

    @MainActor
    private static func handlePrivacyNoticeInitialization(action: Action, state: Self) -> HomepageState {
        return state
            .resetTransientState()
            .copy(telemetryState: HomepageTelemetryState.reducer.legacyReducer(state.telemetryState, action))
            .copy(shouldShowPrivacyNotice: true)
    }

    @MainActor
    private static func passthroughState(from state: HomepageState, action: Action) -> HomepageState {
        return state
            .resetTransientState()
            .copy(telemetryState: HomepageTelemetryState.reducer.legacyReducer(state.telemetryState, action))
    }

    static func defaultState(from state: HomepageState) -> HomepageState {
        return HomepageState(
            windowUUID: state.windowUUID,
            telemetryState: HomepageTelemetryState.defaultState(from: state.telemetryState),
            shouldShowPrivacyNotice: state.shouldShowPrivacyNotice
        )
    }
}
