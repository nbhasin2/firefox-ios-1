// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import Redux
import Common

enum ComponentState: Sendable, Equatable {
    case browserViewController(BrowserViewControllerState)
    case tabsPanel(TabsPanelState)
    case tabsTray(TabTrayState)
    case toolbar(ToolbarState)

    static let reducer: Reducer<Self> = (legacyReducer, modernReducer)

    // swiftlint:disable closure_body_length
    static let modernReducer: ReducerMethod<Self> = { state, action, actionWindowUUID in
        switch state {
        case .browserViewController(let state):
            return .browserViewController(BrowserViewControllerState.reducer.modernReducer(state, action, actionWindowUUID))
        case .tabsTray(let state):
            return .tabsTray(TabTrayState.reducer.modernReducer(state, action, actionWindowUUID))
        case .tabsPanel(let state):
            return .tabsPanel(TabsPanelState.reducer.modernReducer(state, action, actionWindowUUID))
        case .toolbar(let state):
            return .toolbar(ToolbarState.reducer.modernReducer(state, action, actionWindowUUID))
        }
    }

    static let legacyReducer: LegacyReducerMethod<Self> = { state, action in
        switch state {
        case .browserViewController(let state):
            return .browserViewController(BrowserViewControllerState.reducer.legacyReducer(state, action))
        case .tabsTray(let state):
            return .tabsTray(TabTrayState.reducer.legacyReducer(state, action))
        case .tabsPanel(let state):
            return .tabsPanel(TabsPanelState.reducer.legacyReducer(state, action))
        case .toolbar(let state):
            return .toolbar(ToolbarState.reducer.legacyReducer(state, action))
        }
    }
    // swiftlint:enable closure_body_length

    /// Returns the matching AppComponent enum for a given AppComponentState
    var associatedAppComponent: AppComponent {
        switch self {
        case .browserViewController: return .browserViewController
        case .tabsPanel: return .tabsPanel
        case .tabsTray: return .tabsTray
        case .toolbar: return .toolbar
        }
    }

    var windowUUID: WindowUUID? {
        switch self {
        case .browserViewController(let state): return state.windowUUID
        case .tabsPanel(let state): return state.windowUUID
        case .tabsTray(let state): return state.windowUUID
        case .toolbar(let state): return state.windowUUID
        }
    }
}

struct PresentedComponentsState: Sendable, Equatable {
    let components: [ComponentState]

    init() {
        self.components = []
    }

    init(components: [ComponentState]) {
        self.components = components
    }

    static let reducer: Reducer<Self> = (legacyReducer, modernReducer)

    static let modernReducer: ReducerMethod<Self> = { state, action, actionWindowUUID in
        // This reducer does not handle any modern actions for component state; those are in the legacy reducer, so skip
        // updating active components.
        var components = state.components

        // Reduce each component state (forward the modern action to child reducers which may act on them)
        components = components.map { ComponentState.reducer.modernReducer($0, action, actionWindowUUID) }

        return PresentedComponentsState(components: components)
    }

    static let legacyReducer: LegacyReducerMethod<Self> = { state, action in
        // Add or remove components from the active component list as needed
        var components = updateActiveComponents(action: action, components: state.components)

        // Reduce each component state
        components = components.map { ComponentState.reducer.legacyReducer($0, action) }

        return PresentedComponentsState(components: components)
    }

    private static func updateActiveComponents(action: Action, components: [ComponentState]) -> [ComponentState] {
        guard let action = action as? ComponentAction else { return components }

        var components = components

        switch action.actionType {
        case ComponentActionType.removeComponent:
            components = components.filter({
                return $0.associatedAppComponent != action.component || $0.windowUUID != action.windowUUID
            })
        case ComponentActionType.addComponent:
            let uuid = action.windowUUID
            switch action.component {
            case .browserViewController:
                components.append(.browserViewController(BrowserViewControllerState(windowUUID: uuid)))
            case .tabsTray:
                components.append(.tabsTray(TabTrayState(windowUUID: uuid)))
            case .tabsPanel:
                components.append(.tabsPanel(TabsPanelState(windowUUID: uuid)))
            case .toolbar:
                components.append(.toolbar(ToolbarState(windowUUID: uuid)))
            }
        default:
            return components
        }

        return components
    }
}
