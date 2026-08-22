// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Foundation
import Redux

/// Replaces `MicrosurveyMiddleware` and `MicrosurveyState`.
///
/// The state was two write-only booleans, `shouldDismiss` and `showPrivacy`, that existed only to
/// carry a navigation request back to the view controller. They are direct coordinator calls here,
/// so the screen holds no state at all beyond the survey model.
@MainActor
final class MicrosurveyViewModel {
    weak var coordinator: MicrosurveyCoordinatorDelegate?

    private let model: MicrosurveyModel
    private let windowUUID: WindowUUID
    private let telemetry: MicrosurveyTelemetryProtocol
    private let closePrompt: @MainActor (WindowUUID) -> Void

    /// `closePrompt` is injected rather than called inline so this type stays testable without the
    /// store. Closing the prompt also drives `MicrosurveyPromptState` and the toolbar's border, so
    /// it must survive until the Prompt half migrates alongside Toolbar.
    init(model: MicrosurveyModel,
         windowUUID: WindowUUID,
         telemetry: MicrosurveyTelemetryProtocol = MicrosurveyTelemetry(),
         closePrompt: @escaping @MainActor (WindowUUID) -> Void = MicrosurveyViewModel.dispatchClosePrompt) {
        self.model = model
        self.windowUUID = windowUUID
        self.telemetry = telemetry
        self.closePrompt = closePrompt
    }

    // MARK: - Intents

    func surveyDidAppear() {
        telemetry.surveyViewed(surveyId: model.id)
    }

    func submitSurvey(userSelection: String?) {
        closePrompt(windowUUID)
        guard let userSelection else { return }
        telemetry.userResponseSubmitted(surveyId: model.id, userSelection: userSelection)
    }

    func confirmationViewed() {
        telemetry.confirmationShown(surveyId: model.id)
    }

    func closeSurvey() {
        telemetry.dismissButtonTapped(surveyId: model.id)
        closePrompt(windowUUID)
        coordinator?.dismissFlow()
    }

    func tapPrivacyNotice() {
        telemetry.privacyNoticeTapped(surveyId: model.id)
        coordinator?.showPrivacy(with: model.utmContent)
    }

    // MARK: - Default prompt close

    static func dispatchClosePrompt(windowUUID: WindowUUID) {
        store.dispatch(
            MicrosurveyPromptAction(
                windowUUID: windowUUID,
                actionType: MicrosurveyPromptActionType.closePrompt
            )
        )
    }
}
