// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import MenuKit
import ModifiedCopy
import SummarizeKit
import UIKit

struct AccountData: Equatable {
    let title: String
    let subtitle: String?
    let warningIcon: String?
    let needsReAuth: Bool?
    let iconURL: URL?

    init(title: String, subtitle: String?, warningIcon: String? = nil, needsReAuth: Bool? = nil, iconURL: URL? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.warningIcon = warningIcon
        self.needsReAuth = needsReAuth
        self.iconURL = iconURL
    }
}

enum SiteProtectionsState {
    case on
    case off
    case notSecure
}

struct SiteProtectionsData: Equatable {
    let title: String?
    let subtitle: String?
    let image: String?
    let state: SiteProtectionsState
}

struct TelemetryInfo: Equatable {
    let isHomepage: Bool
    let isActionOn: Bool?
    let isDefaultUserAgentDesktop: Bool?
    let hasChangedUserAgent: Bool?

    init(isHomepage: Bool,
         isActionOn: Bool? = nil,
         isDefaultUserAgentDesktop: Bool? = nil,
         hasChangedUserAgent: Bool? = nil) {
        self.isHomepage = isHomepage
        self.isActionOn = isActionOn
        self.isDefaultUserAgentDesktop = isDefaultUserAgentDesktop
        self.hasChangedUserAgent = hasChangedUserAgent
    }
}

struct ReaderModeConfiguration: Equatable {
    /// Whether Reader mode is supported by the web page.
    let isAvailable: Bool
    /// Whether Reader mode is activated on the web page.
    let isActive: Bool
}

struct MainMenuTabInfo: Equatable {
    let tabID: TabUUID
    let url: URL?
    let canonicalURL: URL?
    let isHomepage: Bool
    let isDefaultUserAgentDesktop: Bool
    let hasChangedUserAgent: Bool
    let zoomLevel: CGFloat
    let readerModeConfiguration: ReaderModeConfiguration
    let summaryIsAvailable: Bool
    let summarizerConfig: SummarizerConfig?
    let isBookmarked: Bool
    let isInReadingList: Bool
    let isPinned: Bool
    let accountData: AccountData
    let translationConfiguration: TranslationConfiguration?
}

@Copyable
struct MainMenuState: Equatable {
    var menuElements: [MenuSection]
    var accountData: AccountData?
    var accountProfileImage: UIImage?
    var isBrowserDefault: Bool
    var isPhoneLandscape: Bool
    var moreCellTapped: Bool
    var siteProtectionsData: SiteProtectionsData?
    var currentTabInfo: MainMenuTabInfo?

    init(menuElements: [MenuSection] = [],
         accountData: AccountData? = nil,
         accountProfileImage: UIImage? = nil,
         isBrowserDefault: Bool = false,
         isPhoneLandscape: Bool = false,
         moreCellTapped: Bool = false,
         siteProtectionsData: SiteProtectionsData? = nil,
         currentTabInfo: MainMenuTabInfo? = nil) {
        self.menuElements = menuElements
        self.accountData = accountData
        self.accountProfileImage = accountProfileImage
        self.isBrowserDefault = isBrowserDefault
        self.isPhoneLandscape = isPhoneLandscape
        self.moreCellTapped = moreCellTapped
        self.siteProtectionsData = siteProtectionsData
        self.currentTabInfo = currentTabInfo
    }
}
