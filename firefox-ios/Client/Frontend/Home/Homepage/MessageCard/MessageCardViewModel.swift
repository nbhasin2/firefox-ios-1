// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Foundation

/// Replaces `MessageCardMiddleware` and `MessageCardState`.
///
/// The middleware held `private var message: GleanPlumbMessage?` across actions — state the store
/// never saw, which is why tapping the card had to re-find it. The view model owns both the
/// message and the configuration derived from it.
///
/// Everything here is synchronous; `GleanPlumbMessageManagerProtocol` does no I/O of its own.
@MainActor
final class MessageCardViewModel {
    private(set) var configuration: MessageCardConfiguration? {
        didSet {
            guard configuration != oldValue else { return }
            onConfigurationChange?(configuration)
        }
    }

    var onConfigurationChange: ((MessageCardConfiguration?) -> Void)?

    private let windowUUID: WindowUUID
    private let messagingManager: GleanPlumbMessageManagerProtocol
    private var message: GleanPlumbMessage?

    init(windowUUID: WindowUUID,
         messagingManager: GleanPlumbMessageManagerProtocol = Experiments.messaging,
         initialConfiguration: MessageCardConfiguration? = nil) {
        self.windowUUID = windowUUID
        self.messagingManager = messagingManager
        self.configuration = initialConfiguration
    }

    // MARK: - Intents

    func viewDidLoad() {
        guard let message = messagingManager.getNextMessage(for: .newTabCard) else {
            self.message = nil
            configuration = nil
            return
        }
        self.message = message
        configuration = MessageCardConfiguration(
            title: message.title,
            description: message.text,
            buttonLabel: message.buttonLabel
        )
        messagingManager.onMessageDisplayed(message)
    }

    func tappedOnActionButton() {
        guard let message else { return }
        messagingManager.onMessagePressed(message, window: windowUUID, shouldExpire: true)
        dismissCard()
    }

    func tappedOnCloseButton() {
        guard let message else { return }
        messagingManager.onMessageDismissed(message)
        dismissCard()
    }

    /// Tapping an action on the card dismisses it, as clearing the configuration did before.
    private func dismissCard() {
        message = nil
        configuration = nil
    }
}
