// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import ModifiedCopy

struct PreferredLanguageDetails: Equatable, Hashable {
    let code: String
    let mainText: String
    let subtitleText: String?
    let isDeviceLanguage: Bool

    init(code: String, mainText: String, subtitleText: String?, isDeviceLanguage: Bool = false) {
        self.code = code
        self.mainText = mainText
        self.subtitleText = subtitleText
        self.isDeviceLanguage = isDeviceLanguage
    }
}

@Copyable
struct TranslationSettingsState: Equatable {
    var isTranslationsEnabled: Bool
    var isAutoTranslateEnabled: Bool
    var isEditing: Bool
    var pendingLanguages: [PreferredLanguageDetails]?
    var preferredLanguages: [PreferredLanguageDetails]
    var supportedLanguages: [String]
    var availableLanguages: [String]

    init(isTranslationsEnabled: Bool = true,
         isAutoTranslateEnabled: Bool = false,
         isEditing: Bool = false,
         pendingLanguages: [PreferredLanguageDetails]? = nil,
         preferredLanguages: [PreferredLanguageDetails] = [],
         supportedLanguages: [String] = [],
         availableLanguages: [String] = []) {
        self.isTranslationsEnabled = isTranslationsEnabled
        self.isAutoTranslateEnabled = isAutoTranslateEnabled
        self.isEditing = isEditing
        self.pendingLanguages = pendingLanguages
        self.preferredLanguages = preferredLanguages
        self.supportedLanguages = supportedLanguages
        self.availableLanguages = availableLanguages
    }
}
