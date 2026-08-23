// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Foundation

/// Replaces `TranslationSettingsMiddleware`'s screen half and `TranslationSettingsState`'s reducer.
/// The effects themselves live in `TranslationSettingsService`, because AI Controls drives them too.
@MainActor
final class TranslationSettingsViewModel {
    private(set) var state: TranslationSettingsState {
        didSet {
            guard state != oldValue else { return }
            onStateChange?(state)
        }
    }

    var onStateChange: ((TranslationSettingsState) -> Void)?

    private let service: TranslationSettingsServicing
    private var loadSettingsTask: Task<Void, Never>?

    init(service: TranslationSettingsServicing) {
        self.service = service
        self.state = TranslationSettingsState()
    }

    deinit {
        loadSettingsTask?.cancel()
    }

    // MARK: - Intents

    func viewDidLoad() {
        // The prefs-backed toggles render immediately; the language lists need remote settings.
        let toggles = service.currentToggles()
        state = state
            .copy(isTranslationsEnabled: toggles.isTranslationsEnabled)
            .copy(isAutoTranslateEnabled: toggles.isAutoTranslateEnabled)

        loadSettingsTask?.cancel()
        loadSettingsTask = Task { [weak self] in
            guard let snapshot = await self?.service.loadSettings() else { return }
            self?.apply(snapshot)
        }
    }

    func toggleTranslationsEnabled(newValue: Bool? = nil, toggledViaAIControls: Bool = false) {
        let isEnabled = newValue ?? !state.isTranslationsEnabled
        service.setTranslationsEnabled(isEnabled, toggledViaAIControls: toggledViaAIControls)
        state = state.copy(isTranslationsEnabled: isEnabled)
    }

    func toggleAutoTranslate() {
        state = state.copy(isAutoTranslateEnabled: service.toggleAutoTranslate())
    }

    func addLanguage(code: String) {
        let result = service.addLanguage(code, supportedLanguages: state.supportedLanguages)
        state = state
            .copy(preferredLanguages: result.preferred)
            .copy(availableLanguages: result.available)
    }

    func saveLanguages(_ codes: [String]) {
        let result = service.save(languages: codes, supportedLanguages: state.supportedLanguages)
        state = state
            .copy(preferredLanguages: result.preferred)
            .copy(availableLanguages: result.available)
    }

    func enterEditMode() {
        state = state
            .copy(isEditing: true)
            .copy(pendingLanguages: state.preferredLanguages)
    }

    func cancelEditMode() {
        state = state
            .copy(isEditing: false)
            .copy(pendingLanguages: nil)
    }

    func reorderLanguages(_ languages: [PreferredLanguageDetails]) {
        state = state.copy(pendingLanguages: languages)
    }

    func removeLanguage(code: String) {
        var pending = state.pendingLanguages ?? state.preferredLanguages
        pending.removeAll { $0.code == code }
        state = state.copy(pendingLanguages: pending)
    }

    // MARK: - Private

    private func apply(_ snapshot: TranslationSettingsSnapshot) {
        state = state
            .copy(isTranslationsEnabled: snapshot.isTranslationsEnabled)
            .copy(isAutoTranslateEnabled: snapshot.isAutoTranslateEnabled)
            .copy(preferredLanguages: snapshot.preferredLanguages)
            .copy(supportedLanguages: snapshot.supportedLanguages)
            .copy(availableLanguages: snapshot.availableLanguages)
    }
}
