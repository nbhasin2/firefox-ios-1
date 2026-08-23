// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Foundation
import Redux

struct SearchEngineSelectionAction: Action {
    let windowUUID: WindowUUID
    let actionType: ActionType
    let selectedSearchEngine: SearchEngineModel?

    init(
        windowUUID: WindowUUID,
        actionType: ActionType,
        selectedSearchEngine: SearchEngineModel? = nil
    ) {
        self.windowUUID = windowUUID
        self.actionType = actionType
        self.selectedSearchEngine = selectedSearchEngine
    }
}

enum SearchEngineSelectionActionType: ActionType {
    case didTapSearchEngine
}

enum SearchEngineSelectionMiddlewareActionType: ActionType {
    case didClearAlternativeSearchEngine
}
