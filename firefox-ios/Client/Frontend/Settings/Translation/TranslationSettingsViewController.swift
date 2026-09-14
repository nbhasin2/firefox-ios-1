// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Shared

/// Legacy translation settings view controller used when the `translationLanguagePicker`
/// feature flag is OFF (Phase 1 / pre-language-picker behavior).
final class TranslationSettingsViewController: SettingsTableViewController {
    let prefs: Prefs
    private let service: TranslationSettingsServicing

    init(prefs: Prefs, windowUUID: WindowUUID, service: TranslationSettingsServicing? = nil) {
        self.prefs = prefs
        self.service = service ?? TranslationSettingsService(windowUUID: windowUUID)
        super.init(style: .grouped, windowUUID: windowUUID)
        self.title = .Settings.Translation.Title
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var theme: Theme {
        themeManager.getCurrentTheme(for: windowUUID)
    }

    override func generateSettings() -> [SettingSection] {
        return [translationSection]
    }

    private var translationSection: SettingSection {
        let enableFeatureSwitch = BoolSetting(
            prefs: prefs,
            theme: theme,
            prefKey: PrefsKeys.Settings.translationsFeature,
            defaultValue: true,
            titleText: .Settings.Translation.ToggleTitle
        ) { [weak self] _ in
            guard let self else { return }
            // `BoolSetting` has already written the pref; re-broadcast the new value.
            let isEnabled = self.prefs.boolForKey(PrefsKeys.Settings.translationsFeature) ?? true
            self.service.setTranslationsEnabled(isEnabled, toggledViaAIControls: false)
        }
        return SettingSection(
            title: NSAttributedString(
                string: .Settings.Translation.SectionTitle
            ),
            children: [enableFeatureSwitch]
        )
    }
}
