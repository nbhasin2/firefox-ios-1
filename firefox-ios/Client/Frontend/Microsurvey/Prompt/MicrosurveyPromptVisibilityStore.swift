// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Foundation

/// Whether the microsurvey prompt is on screen, per window.
///
/// `ToolbarMiddleware` needs this to decide which toolbar borders to hide — a survey sitting
/// between the address bar and the navigation bar should look like part of the app, which means
/// suppressing the border between them. It used to read `BrowserViewControllerState` out of the
/// store; with that state owned by `BrowserViewController` there is no shared place to read it
/// from, and the middleware has no reference to the controller.
///
/// Deliberately narrow: one boolean per window, written only by `BrowserViewController`. Same
/// shape and same justification as `SearchBarVisibilityStore`, and it goes the same way — when
/// the microsurvey prompt migrates off `BrowserViewControllerState`, its own view model owns this.
@MainActor
final class MicrosurveyPromptVisibilityStore {
    static let shared = MicrosurveyPromptVisibilityStore()

    private var visibilityByWindow: [WindowUUID: Bool] = [:]

    func setPromptVisible(_ isVisible: Bool, for windowUUID: WindowUUID) {
        visibilityByWindow[windowUUID] = isVisible
    }

    func isPromptVisible(for windowUUID: WindowUUID) -> Bool {
        return visibilityByWindow[windowUUID] ?? false
    }
}
