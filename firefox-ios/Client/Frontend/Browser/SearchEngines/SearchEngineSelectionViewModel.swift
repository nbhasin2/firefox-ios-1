// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Foundation
import Redux

/// Replaces `SearchEngineSelectionState` and `SearchEngineSelectionMiddleware`.
///
/// The middleware's load half read `SearchEnginesManager.orderedEngines` and dispatched the result
/// for the reducer to store — a read the view model can do itself. Its other half turned a tap
/// into two outward announcements, which stay as dispatches: `ToolbarActionType.didStartEditingUrl`
/// and `SearchEngineSelectionActionType.didTapSearchEngine`, both consumed by the toolbar's
/// reducers. That is the D-016 end state for a migrated screen — it dispatches outward and holds
/// no `ScreenState`.
@MainActor
final class SearchEngineSelectionViewModel {
    /// The default search engine appears in position 0.
    private(set) var searchEngines: [SearchEngineModel] = []

    var onChange: (() -> Void)?

    private let windowUUID: WindowUUID
    private let searchEnginesManager: SearchEnginesManagerProvider

    init(windowUUID: WindowUUID,
         searchEnginesManager: SearchEnginesManagerProvider =
            AppContainer.shared.resolve(SearchEnginesManager.self)) {
        self.windowUUID = windowUUID
        self.searchEnginesManager = searchEnginesManager
    }

    // MARK: - Intents

    func viewDidLoad() {
        let orderedEngines = searchEnginesManager.orderedEngines
        guard orderedEngines.isEmpty else {
            update(with: orderedEngines)
            return
        }

        // SearchEnginesManager should have loaded these by now; fetch them if it has not.
        searchEnginesManager.getOrderedEngines { [weak self] _, searchEngines in
            self?.update(with: searchEngines)
        }
    }

    func didTap(searchEngineModel: SearchEngineModel) {
        // Both are consumed by the toolbar's reducers, which have not migrated.
        browserEventBus.dispatch(
            ToolbarAction(windowUUID: windowUUID, actionType: ToolbarActionType.didStartEditingUrl)
        )
        browserEventBus.dispatch(
            SearchEngineSelectionAction(
                windowUUID: windowUUID,
                actionType: SearchEngineSelectionActionType.didTapSearchEngine,
                selectedSearchEngine: searchEngineModel
            )
        )
    }

    // MARK: - Private

    private func update(with searchEngines: [OpenSearchEngine]) {
        self.searchEngines = searchEngines.map { $0.generateModel() }
        onChange?()
    }
}
