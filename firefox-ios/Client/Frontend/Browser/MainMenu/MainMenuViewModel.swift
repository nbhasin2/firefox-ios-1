// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Foundation
import MenuKit
import Redux
import Shared
import UIKit

@MainActor
protocol MainMenuViewModelDelegate: AnyObject {
    func mainMenuViewModelDidRequestNavigation(to destination: MenuNavigationDestination)
    func mainMenuViewModelDidRequestDismiss()
}

/// Replaces `MainMenuMiddleware` and `MainMenuState`'s reducer.
///
/// `shouldDismiss` and `navigationDestination` were transient fields that `newState` turned
/// straight back into a coordinator call and the next action then had to clear; they are delegate
/// calls here. The tab data the menu renders comes from `MainMenuTabInfoProvider`, which
/// `TabManagerActionHandler` used to push in through six `MainMenuAction` cases.
@MainActor
final class MainMenuViewModel: MainMenuActionHandling {
    /// Glean option strings, moved verbatim from `MainMenuMiddleware`.
    private enum TelemetryAction {
        static let addToShortcuts = "add_to_shortcuts"
        static let bookmarks = "bookmarks"
        static let adBlocker = "ad_blocker"
        static let bookmarkThisPage = "bookmark_this_page"
        static let defaultBrowserSettings = "default_browser_settings"
        static let downloads = "downloads"
        static let editBookmark = "edit_bookmark"
        static let findInPage = "find_in_page"
        static let history = "history"
        static let nightModeTurnOff = "night_mode_turn_off"
        static let nightModeTurnOn = "night_mode_turn_on"
        static let passwords = "passwords"
        static let readerView = "reader_view"
        static let print = "print"
        static let removeFromShortcuts = "remove_from_shortcuts"
        static let reportBrokenSite = "report_broken_site"
        static let saveAsPDF = "save_as_PDF"
        static let settings = "settings"
        static let share = "share"
        static let signInAccount = "sign_in_account"
        static let siteProtections = "site_protections"
        static let switchToDesktopSite = "switch_to_desktop_site"
        static let switchToMobileSite = "switch_to_mobile_site"
        static let translatePage = "translate_page"
        static let webpageSummary = "webpage_summary"
        static let zoom = "zoom"
    }

    private(set) var state: MainMenuState {
        didSet {
            guard state != oldValue else { return }
            onStateChange?(state)
        }
    }

    var onStateChange: ((MainMenuState) -> Void)?
    weak var delegate: MainMenuViewModelDelegate?

    private let windowUUID: WindowUUID
    private let tabInfoProvider: MainMenuTabInfoProviding
    private let menuConfigurator: MainMenuConfigurationUtility
    private let telemetry: MainMenuTelemetry
    private let webCompatTelemetry: WebCompatReporterTelemetry
    private let isBrowserDefault: () -> Bool
    private let isPhoneLandscape: () -> Bool
    private let toggleNightMode: () -> Void

    private var loadTask: Task<Void, Never>?

    private var isHomepage: Bool { state.currentTabInfo?.isHomepage ?? false }

    init(windowUUID: WindowUUID,
         tabInfoProvider: MainMenuTabInfoProviding? = nil,
         menuConfigurator: MainMenuConfigurationUtility = MainMenuConfigurationUtility(),
         telemetry: MainMenuTelemetry = MainMenuTelemetry(),
         webCompatTelemetry: WebCompatReporterTelemetry = WebCompatReporterTelemetry(),
         isBrowserDefault: @escaping () -> Bool = { DefaultBrowserUtility().isDefaultBrowser },
         isPhoneLandscape: @escaping () -> Bool = { UIDevice().isIphoneLandscape },
         toggleNightMode: @escaping () -> Void = { NightModeHelper.toggle() }) {
        self.windowUUID = windowUUID
        self.tabInfoProvider = tabInfoProvider ?? MainMenuTabInfoProvider()
        self.menuConfigurator = menuConfigurator
        self.telemetry = telemetry
        self.webCompatTelemetry = webCompatTelemetry
        self.isBrowserDefault = isBrowserDefault
        self.isPhoneLandscape = isPhoneLandscape
        self.toggleNightMode = toggleNightMode
        self.state = MainMenuState()
        // The generated MenuElement closures call back through this; without it every row in the
        // menu is inert.
        menuConfigurator.actionHandler = self
    }

    deinit {
        loadTask?.cancel()
    }

    // MARK: - Lifecycle intents

    func viewDidLoad() {
        state = state
            .copy(isBrowserDefault: isBrowserDefault())
            .copy(isPhoneLandscape: isPhoneLandscape())
        reloadTabInfo()
        reloadSiteProtections()
    }

    func updateMenuAppearance() {
        state = state.copy(isPhoneLandscape: isPhoneLandscape())
    }

    func viewWillTransition() {
        reloadTabInfo()
    }

    func menuDismissed() {
        telemetry.menuDismissed(isHomepage: isHomepage)
    }

    // MARK: - Menu intents

    func tapNavigateToDestination(_ destination: MenuNavigationDestination) {
        recordTelemetry(for: destination.destination)
        delegate?.mainMenuViewModelDidRequestNavigation(to: destination)
    }

    func tapCloseMenu() {
        telemetry.closeButtonTapped(isHomepage: isHomepage)
        delegate?.mainMenuViewModelDidRequestDismiss()
    }

    func tapMoreOptions(isExpanded: Bool) {
        guard let currentTabInfo = state.currentTabInfo else { return }
        state = state
            .copy(menuElements: menuConfigurator.generateMenuElements(
                with: currentTabInfo,
                and: windowUUID,
                isExpanded: !isExpanded,
                profileImage: state.accountProfileImage
            ))
            .copy(moreCellTapped: true)
    }

    func tapToggleUserAgent(isDefaultUserAgentDesktop: Bool, hasChangedUserAgent: Bool) {
        let option: String
        if isDefaultUserAgentDesktop {
            option = hasChangedUserAgent ? TelemetryAction.switchToDesktopSite : TelemetryAction.switchToMobileSite
        } else {
            option = hasChangedUserAgent ? TelemetryAction.switchToMobileSite : TelemetryAction.switchToDesktopSite
        }
        telemetry.mainMenuOptionTapped(with: isHomepage, and: option)
        tabInfoProvider.toggleUserAgent(for: windowUUID)
        delegate?.mainMenuViewModelDidRequestDismiss()
    }

    func tapToggleNightMode(isActionOn: Bool) {
        let option = isActionOn ? TelemetryAction.nightModeTurnOn : TelemetryAction.nightModeTurnOff
        telemetry.mainMenuOptionTapped(with: isHomepage, and: option)
        toggleNightMode()
        delegate?.mainMenuViewModelDidRequestDismiss()
    }

    func tapZoom() {
        telemetry.mainMenuOptionTapped(with: isHomepage, and: TelemetryAction.zoom)
        delegate?.mainMenuViewModelDidRequestNavigation(to: MenuNavigationDestination(.zoom))
    }

    func tapEditBookmark() {
        telemetry.mainMenuOptionTapped(with: isHomepage, and: TelemetryAction.editBookmark)
        delegate?.mainMenuViewModelDidRequestNavigation(to: MenuNavigationDestination(.editBookmark))
    }

    func tapAddToBookmarks() {
        telemetry.mainMenuOptionTapped(with: isHomepage, and: TelemetryAction.bookmarkThisPage)
        if let url = tabInfoProvider.addToBookmarks(tabID: state.currentTabInfo?.tabID, windowUUID: windowUUID) {
            showAddBookmarkToast(urlString: url)
        }
        delegate?.mainMenuViewModelDidRequestDismiss()
    }

    func tapAddToShortcuts() {
        telemetry.mainMenuOptionTapped(with: isHomepage, and: TelemetryAction.addToShortcuts)
        tabInfoProvider.addToShortcuts(tabID: state.currentTabInfo?.tabID, windowUUID: windowUUID)
        delegate?.mainMenuViewModelDidRequestDismiss()
    }

    func tapRemoveFromShortcuts() {
        telemetry.mainMenuOptionTapped(with: isHomepage, and: TelemetryAction.removeFromShortcuts)
        tabInfoProvider.removeFromShortcuts(tabID: state.currentTabInfo?.tabID, windowUUID: windowUUID)
        delegate?.mainMenuViewModelDidRequestDismiss()
    }

    /// Browser-level, so it stays on the bus (DECISIONS.md D-016/D-017).
    private func showAddBookmarkToast(urlString: String) {
        store.dispatch(
            GeneralBrowserAction(
                toastType: .addBookmark(urlString: urlString),
                windowUUID: windowUUID,
                actionType: GeneralBrowserActionType.showToast
            )
        )
    }

    // MARK: - Refresh

    private func reloadTabInfo() {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self, let tabInfo = await self.tabInfoProvider.tabInfo(for: self.windowUUID) else { return }
            self.apply(tabInfo)
            guard let image = await self.tabInfoProvider.profileImage(for: tabInfo.accountData) else { return }
            self.applyProfileImage(image)
        }
    }

    private func reloadSiteProtections() {
        guard let data = tabInfoProvider.siteProtectionsData(for: windowUUID) else { return }
        state = state.copy(siteProtectionsData: data)
    }

    private func apply(_ tabInfo: MainMenuTabInfo) {
        state = state
            .copy(menuElements: menuConfigurator.generateMenuElements(
                with: tabInfo,
                and: windowUUID,
                isExpanded: state.moreCellTapped
            ))
            .copy(currentTabInfo: tabInfo)
            .copy(accountData: tabInfo.accountData)
    }

    private func applyProfileImage(_ image: UIImage) {
        guard let currentTabInfo = state.currentTabInfo else { return }
        state = state
            .copy(menuElements: menuConfigurator.generateMenuElements(
                with: currentTabInfo,
                and: windowUUID,
                isExpanded: state.moreCellTapped,
                profileImage: image
            ))
            .copy(accountProfileImage: image)
    }

    // MARK: - Telemetry

    private func recordTelemetry(for destination: MainMenuNavigationDestination) {
        switch destination {
        case .findInPage:
            telemetry.mainMenuOptionTapped(with: isHomepage, and: TelemetryAction.findInPage)
        case .bookmarks:
            telemetry.mainMenuOptionTapped(with: isHomepage, and: TelemetryAction.bookmarks)
        case .history:
            telemetry.mainMenuOptionTapped(with: isHomepage, and: TelemetryAction.history)
        case .downloads:
            telemetry.mainMenuOptionTapped(with: isHomepage, and: TelemetryAction.downloads)
        case .passwords:
            telemetry.mainMenuOptionTapped(with: isHomepage, and: TelemetryAction.passwords)
        case .readerView:
            telemetry.mainMenuOptionTapped(with: isHomepage, and: TelemetryAction.readerView)
        case .settings:
            telemetry.mainMenuOptionTapped(with: isHomepage, and: TelemetryAction.settings)
        case .printSheet:
            telemetry.mainMenuOptionTapped(with: isHomepage, and: TelemetryAction.print)
        case .reportBrokenSite:
            telemetry.mainMenuOptionTapped(with: isHomepage, and: TelemetryAction.reportBrokenSite)
            webCompatTelemetry.opened(source: .hamburgerMenu)
        case .shareSheet:
            telemetry.mainMenuOptionTapped(with: isHomepage, and: TelemetryAction.share)
        case .saveAsPDF:
            telemetry.mainMenuOptionTapped(with: isHomepage, and: TelemetryAction.saveAsPDF)
        case .syncSignIn:
            telemetry.mainMenuOptionTapped(with: isHomepage, and: TelemetryAction.signInAccount)
        case .editBookmark:
            telemetry.mainMenuOptionTapped(with: isHomepage, and: TelemetryAction.editBookmark)
        case .zoom:
            telemetry.mainMenuOptionTapped(with: isHomepage, and: TelemetryAction.zoom)
        case .siteProtections:
            telemetry.mainMenuOptionTapped(with: isHomepage, and: TelemetryAction.siteProtections)
        case .adBlocker:
            telemetry.mainMenuOptionTapped(with: isHomepage, and: TelemetryAction.adBlocker)
        case .defaultBrowser:
            telemetry.mainMenuOptionTapped(with: isHomepage, and: TelemetryAction.defaultBrowserSettings)
        case .webpageSummary:
            telemetry.mainMenuOptionTapped(with: isHomepage, and: TelemetryAction.webpageSummary)
        case .translatePage:
            telemetry.mainMenuOptionTapped(with: isHomepage, and: TelemetryAction.translatePage)
        }
    }
}
