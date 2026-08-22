// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Foundation
import ModifiedCopy

/// State for the header cell that is used in the homepage header section
@Copyable
struct HeaderState: Equatable, Hashable {
    var windowUUID: WindowUUID
    var isPrivate: Bool
    var showQuickAnswersButton: Bool

    init(
        windowUUID: WindowUUID,
        isPrivate: Bool = false,
        quickAnswersStore: QuickAnswersStore? = nil
    ) {
        // Constructed lazily: private mode never reads it, and building one resolves two services
        // out of AppContainer, which is a hazard in tests (D-026).
        let showQuickAnswersButton = isPrivate
            ? false
            : (quickAnswersStore ?? QuickAnswersService()).isQuickAnswersEnabled
        self.init(
            windowUUID: windowUUID,
            isPrivate: isPrivate,
            showQuickAnswersButton: showQuickAnswersButton
        )
    }

    private init(
        windowUUID: WindowUUID,
        isPrivate: Bool,
        showQuickAnswersButton: Bool
    ) {
        self.windowUUID = windowUUID
        self.isPrivate = isPrivate
        self.showQuickAnswersButton = showQuickAnswersButton
    }
}
