// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Foundation
import Shared

/// Owns the generated-password draft and the effects that were `PasswordGeneratorMiddleware`.
///
/// The middleware bounced every generated password back through the store as an
/// `updateGeneratedPassword` action; here the JS call is awaited and the result assigned directly.
@MainActor
final class PasswordGeneratorViewModel {
    private(set) var state: PasswordGeneratorState {
        didSet {
            guard state != oldValue else { return }
            onStateChange?(state)
        }
    }

    var onStateChange: ((PasswordGeneratorState) -> Void)?

    private let frameContext: PasswordGeneratorFrameContext
    private let generatedPasswordStorage: GeneratedPasswordStorageProtocol
    private let rulesProvider: PasswordRulesProviding
    private let telemetry: PasswordGeneratorTelemetry
    private let logger: Logger

    init(frameContext: PasswordGeneratorFrameContext,
         generatedPasswordStorage: GeneratedPasswordStorageProtocol = GeneratedPasswordStorage.shared,
         rulesProvider: PasswordRulesProviding = PasswordRulesProvider.shared,
         telemetry: PasswordGeneratorTelemetry = PasswordGeneratorTelemetry(),
         logger: Logger = DefaultLogger.shared) {
        self.frameContext = frameContext
        self.generatedPasswordStorage = generatedPasswordStorage
        self.rulesProvider = rulesProvider
        self.telemetry = telemetry
        self.logger = logger
        self.state = PasswordGeneratorState()
    }

    // MARK: - Intents

    /// Reuses the password already generated for this origin so reopening the sheet is stable.
    func showPasswordGenerator() async {
        guard let origin = frameContext.origin else { return }
        telemetry.passwordGeneratorDialogShown()

        if let password = generatedPasswordStorage.getPasswordForOrigin(origin: origin) {
            state.password = password
        } else {
            await generateAndStorePassword(origin: origin)
        }
    }

    func refreshPassword() async {
        guard let origin = frameContext.origin else { return }
        await generateAndStorePassword(origin: origin)
    }

    func usePassword() async {
        telemetry.usePasswordButtonPressed()
        guard let escapedPassword = escape(state.password) else { return }

        do {
            _ = try await frameContext.scriptEvaluator.evaluateStringInDefaultContentWorld(
                "window.__firefox__.logins.fillGeneratedPassword(\(escapedPassword))",
                in: frameContext.frameInfo
            )
        } catch {
            logger.log("Error filling in password info",
                       level: .warning,
                       category: .passwordGenerator)
        }
    }

    func hidePassword() {
        state.passwordHidden = true
    }

    func showPassword() {
        state.passwordHidden = false
    }

    // MARK: - Generation

    private func generateAndStorePassword(origin: String) async {
        guard let password = await generateNewPassword() else { return }
        generatedPasswordStorage.setPasswordForOrigin(origin: origin, password: password)
        state.password = password
    }

    private func generateNewPassword() async -> String? {
        let originRules = await rulesProvider.rule(for: frameContext.host)
        let jsFunctionCall = "window.__firefox__.logins.generatePassword(\(originRules ?? ""))"

        do {
            return try await frameContext.scriptEvaluator.evaluateStringInDefaultContentWorld(
                jsFunctionCall,
                in: frameContext.frameInfo
            )
        } catch {
            logger.log("JavaScript evaluation error",
                       level: .warning,
                       category: .webview,
                       description: "\(error.localizedDescription)")
            return nil
        }
    }

    private func escape(_ string: String) -> String? {
        guard let jsonData = try? JSONEncoder().encode(string),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            logger.log("Error encoding generated password to JSON",
                       level: .warning,
                       category: .passwordGenerator)
            return nil
        }
        return jsonString
    }
}
