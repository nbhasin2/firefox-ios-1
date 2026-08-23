// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Foundation
import Redux
import Shared

/// The settings values the translation settings screen reads.
struct TranslationSettingsSnapshot: Equatable {
    var isTranslationsEnabled: Bool
    var isAutoTranslateEnabled: Bool
    var preferredLanguages: [PreferredLanguageDetails]
    var supportedLanguages: [String]
    var availableLanguages: [String]
}

@MainActor
protocol TranslationSettingsServicing: AnyObject {
    /// The prefs-backed values, available synchronously.
    func currentToggles() -> (isTranslationsEnabled: Bool, isAutoTranslateEnabled: Bool)
    /// The full snapshot, which needs the supported-language list from remote settings.
    func loadSettings() async -> TranslationSettingsSnapshot
    func setTranslationsEnabled(_ isEnabled: Bool, toggledViaAIControls: Bool)
    func toggleAutoTranslate() -> Bool
    func addLanguage(_ code: String, supportedLanguages: [String]) -> (preferred: [PreferredLanguageDetails],
                                                                       available: [String])
    func save(languages: [String], supportedLanguages: [String]) -> (preferred: [PreferredLanguageDetails],
                                                                     available: [String])
}

/// The effects that were `TranslationSettingsMiddleware`.
///
/// This is a service rather than logic on the view model because the AI Controls screen toggles the
/// translations pref too, without the translation settings screen being on screen at all. Under
/// Redux that worked because AI Controls dispatched the same action; here both call this.
@MainActor
final class TranslationSettingsService: TranslationSettingsServicing {
    private let prefs: Prefs
    private let manager: PreferredTranslationLanguagesManager
    private let modelsFetcher: TranslationModelsFetcherProtocol
    private let localeProvider: LocaleProvider
    private let telemetry: SettingsTelemetry
    private let broadcastSettingsChange: @MainActor (Bool?, TranslationConfiguration) -> Void

    private var resetStorageTask: Task<Void, Never>?

    init(profile: Profile = AppContainer.shared.resolve(),
         manager: PreferredTranslationLanguagesManager? = nil,
         modelsFetcher: TranslationModelsFetcherProtocol = ASTranslationModelsFetcher.shared,
         localeProvider: LocaleProvider = SystemLocaleProvider(),
         telemetry: SettingsTelemetry = SettingsTelemetry(),
         windowUUID: WindowUUID,
         broadcastSettingsChange: (@MainActor (Bool?, TranslationConfiguration) -> Void)? = nil) {
        self.prefs = profile.prefs
        self.manager = manager ?? PreferredTranslationLanguagesManager(prefs: profile.prefs)
        self.modelsFetcher = modelsFetcher
        self.localeProvider = localeProvider
        self.telemetry = telemetry
        self.broadcastSettingsChange = broadcastSettingsChange ?? { isEnabled, configuration in
            TranslationSettingsService.dispatchSettingsChange(
                isEnabled: isEnabled,
                configuration: configuration,
                windowUUID: windowUUID
            )
        }
    }

    deinit {
        resetStorageTask?.cancel()
    }

    // MARK: - Reads

    func currentToggles() -> (isTranslationsEnabled: Bool, isAutoTranslateEnabled: Bool) {
        return (prefs.boolForKey(PrefsKeys.Settings.translationsFeature) ?? true,
                prefs.boolForKey(PrefsKeys.Settings.translationAutoTranslate) ?? false)
    }

    func loadSettings() async -> TranslationSettingsSnapshot {
        let supported = await modelsFetcher.fetchSupportedTargetLanguages()
        let codes = manager.preferredLanguages(supportedTargetLanguages: supported)
        let toggles = currentToggles()
        return TranslationSettingsSnapshot(
            isTranslationsEnabled: toggles.isTranslationsEnabled,
            isAutoTranslateEnabled: toggles.isAutoTranslateEnabled,
            preferredLanguages: buildLanguageDetails(from: codes),
            supportedLanguages: supported,
            availableLanguages: buildAvailableLanguages(preferred: codes, supported: supported)
        )
    }

    // MARK: - Writes

    func setTranslationsEnabled(_ isEnabled: Bool, toggledViaAIControls: Bool) {
        let current = prefs.boolForKey(PrefsKeys.Settings.translationsFeature) ?? true
        prefs.setBool(isEnabled, forKey: PrefsKeys.Settings.translationsFeature)
        // If coming from AI Controls don't log telemetry, we are handling telemetry there
        if !toggledViaAIControls {
            telemetry.changedSetting(
                PrefsKeys.Settings.translationsFeature,
                to: "\(isEnabled)",
                from: "\(current)"
            )
        }
        broadcastSettingsChange(isEnabled,
                                TranslationConfiguration(prefs: prefs, isUserSettingEnabled: isEnabled))
        if !isEnabled {
            resetStorageTask?.cancel()
            resetStorageTask = Task { [modelsFetcher] in
                await modelsFetcher.resetStorage()
            }
        }
    }

    /// Returns the new value.
    func toggleAutoTranslate() -> Bool {
        let newValue = !(prefs.boolForKey(PrefsKeys.Settings.translationAutoTranslate) ?? false)
        prefs.setBool(newValue, forKey: PrefsKeys.Settings.translationAutoTranslate)
        telemetry.changedSetting(
            PrefsKeys.Settings.translationAutoTranslate,
            to: "\(newValue)",
            from: "\(!newValue)"
        )
        if newValue {
            broadcastSettingsChange(nil, TranslationConfiguration(prefs: prefs))
        }
        return newValue
    }

    func addLanguage(_ code: String,
                     supportedLanguages: [String]) -> (preferred: [PreferredLanguageDetails],
                                                       available: [String]) {
        let updated = manager.addLanguage(code)
        return (buildLanguageDetails(from: updated),
                buildAvailableLanguages(preferred: updated, supported: supportedLanguages))
    }

    func save(languages: [String],
              supportedLanguages: [String]) -> (preferred: [PreferredLanguageDetails],
                                                available: [String]) {
        manager.save(languages: languages)
        return (buildLanguageDetails(from: languages),
                buildAvailableLanguages(preferred: languages, supported: supportedLanguages))
    }

    // MARK: - Broadcast

    /// `didTranslationSettingsChange` is also reduced by `AddressBarState`, `ToolbarState` and
    /// `TranslationsActionHandler`, none of which have migrated yet, so this stays a dispatch
    /// (DECISIONS.md D-011). It is injectable so the service is testable without the store.
    private static func dispatchSettingsChange(isEnabled: Bool?,
                                               configuration: TranslationConfiguration,
                                               windowUUID: WindowUUID) {
        browserEventBus.dispatch(TranslationsAction(
            isTranslationsEnabled: isEnabled,
            translationConfiguration: configuration,
            windowUUID: windowUUID,
            actionType: TranslationsActionType.didTranslationSettingsChange
        ))
    }

    // MARK: - Language details

    private func buildAvailableLanguages(preferred: [String], supported: [String]) -> [String] {
        let preferredSet = Set(preferred)
        return supported
            .filter { !preferredSet.contains($0) }
            .sorted { [localeProvider] lhs, rhs in
                let lhsName = localeProvider.nativeLanguageName(for: lhs)
                let rhsName = localeProvider.nativeLanguageName(for: rhs)
                return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
            }
    }

    private func buildLanguageDetails(from codes: [String]) -> [PreferredLanguageDetails] {
        let deviceCode = localeProvider.current.languageCode ?? ""
        return codes.map { code in
            let native = localeProvider.nativeLanguageName(for: code)
            let localized = localeProvider.localizedLanguageName(for: code)
            let isDeviceLanguage = code == deviceCode
            let subtitle: String? = isDeviceLanguage
                ? .Settings.Translation.PreferredLanguages.DeviceLanguage
                : (native == localized ? nil : localized)
            return PreferredLanguageDetails(
                code: code, mainText: native, subtitleText: subtitle, isDeviceLanguage: isDeviceLanguage
            )
        }
    }
}
