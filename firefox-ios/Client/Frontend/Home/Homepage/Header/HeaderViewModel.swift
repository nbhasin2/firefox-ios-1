// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Foundation

/// Replaces `HeaderState`'s reducer and `QuickAnswersMiddleware`.
///
/// `HeaderState` stays as a plain `Hashable` struct because the diffable data source uses it as an
/// item identity; only its Redux conformance goes.
@MainActor
final class HeaderViewModel {
    private(set) var state: HeaderState {
        didSet {
            guard state != oldValue else { return }
            onChange?()
        }
    }

    var onChange: (() -> Void)?

    private let windowUUID: WindowUUID
    private let quickAnswersStore: QuickAnswersStore

    init(windowUUID: WindowUUID,
         quickAnswersStore: QuickAnswersStore = QuickAnswersService()) {
        self.windowUUID = windowUUID
        self.quickAnswersStore = quickAnswersStore
        self.state = HeaderState(windowUUID: windowUUID, quickAnswersStore: quickAnswersStore)
    }

    // MARK: - Intents

    /// Homepage initialize and view-will-appear, which is when the middleware recomputed.
    ///
    /// This also subsumes `QuickAnswersActionType.didSettingsChange`: the setting can only be
    /// changed from a screen presented over the homepage, so returning to the homepage recomputes
    /// here anyway. The middleware dispatched on both and the second was always redundant.
    func refresh() {
        state = state
            .copy(isPrivate: false)
            .copy(showQuickAnswersButton: quickAnswersStore.isQuickAnswersEnabled)
    }
}
