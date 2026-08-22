// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Account
import Common
import Foundation
import Shared
import Redux
import Storage
import SummarizeKit
import UIKit

@MainActor
protocol MainMenuTabInfoProviding: AnyObject {
    /// Everything the menu needs about the selected tab. Nil when there is no selected tab.
    func tabInfo(for windowUUID: WindowUUID) async -> MainMenuTabInfo?
    /// The signed-in account's avatar, fetched separately because it is slow and optional.
    func profileImage(for accountData: AccountData) async -> UIImage?
    func siteProtectionsData(for windowUUID: WindowUUID) -> SiteProtectionsData?
    func toggleUserAgent(for windowUUID: WindowUUID)
    func addToShortcuts(tabID: TabUUID?, windowUUID: WindowUUID)
    func removeFromShortcuts(tabID: TabUUID?, windowUUID: WindowUUID)
    /// Returns the bookmarked URL so the caller can show the confirmation toast.
    func addToBookmarks(tabID: TabUUID?, windowUUID: WindowUUID) -> String?
}

/// Assembles the main menu's view of the selected tab. Extracted from `TabManagerMiddleware`, which
/// reached this code through six `MainMenuAction` cases.
///
/// The three profile lookups were a `DispatchGroup` fan-out writing into three
/// `nonisolated(unsafe)` variables, carrying `TODO: FXIOS-13675 These should be made actually
/// threadsafe`. They are `async let` here, so the concurrency is expressed in the type system and
/// the unsafe annotations are gone.
@MainActor
final class MainMenuTabInfoProvider: MainMenuTabInfoProviding {
    private let profile: Profile
    private let windowManager: WindowManager
    private let summarizerConfigFactory: SummarizerConfigFactory
    private let summarizerNimbusUtility: SummarizerNimbusUtils
    private let bookmarksSaver: BookmarksSaver
    private let logger: Logger

    init(profile: Profile = AppContainer.shared.resolve(),
         windowManager: WindowManager = AppContainer.shared.resolve(),
         summarizerConfigFactory: SummarizerConfigFactory = SummarizerMiddleware(),
         summarizerNimbusUtility: SummarizerNimbusUtils = DefaultSummarizerNimbusUtils(),
         bookmarksSaver: BookmarksSaver? = nil,
         logger: Logger = DefaultLogger.shared) {
        self.bookmarksSaver = bookmarksSaver ?? DefaultBookmarksSaver(profile: profile)
        self.profile = profile
        self.windowManager = windowManager
        self.summarizerConfigFactory = summarizerConfigFactory
        self.summarizerNimbusUtility = summarizerNimbusUtility
        self.logger = logger
    }

    // MARK: - Tab info

    func tabInfo(for windowUUID: WindowUUID) async -> MainMenuTabInfo? {
        guard let selectedTab = tabManager(for: windowUUID)?.selectedTab else {
            logger.log(
                "Attempted to get `selectedTab` but it was `nil` when in shouldn't be",
                level: .fatal,
                category: .tabs
            )
            return nil
        }

        let accountData = accountData()
        let profileInfo = await profileTabInfo(for: selectedTab.url)

        var summarizerConfig: SummarizerConfig?
        if summarizerNimbusUtility.isSummarizeFeatureEnabled,
           !selectedTab.isFxHomeTab,
           let webView = selectedTab.webView {
            summarizerConfig = await summarizerConfigFactory.makeConfiguration(from: webView)
        }

        return makeTabInfo(
            selectedTab: selectedTab,
            windowUUID: windowUUID,
            accountData: accountData,
            profileInfo: profileInfo,
            summarizerConfig: summarizerConfig
        )
    }

    func profileImage(for accountData: AccountData) async -> UIImage? {
        guard let iconURL = accountData.iconURL else { return nil }
        return await withCheckedContinuation { continuation in
            GeneralizedImageFetcher().getImageFor(url: iconURL) { image in
                continuation.resume(returning: image)
            }
        }
    }

    // MARK: - Site protections

    func siteProtectionsData(for windowUUID: WindowUUID) -> SiteProtectionsData? {
        guard let selectedTab = tabManager(for: windowUUID)?.selectedTab else {
            logger.log(
                "Attempted to get `selectedTab` but it was `nil` when in shouldn't be",
                level: .fatal,
                category: .tabs
            )
            return nil
        }

        let subtitle: String?
        if let internalURL = InternalURL(selectedTab.url), internalURL.isCertificateErrorURL {
            subtitle = internalURL.originalURLFromErrorPage?.baseDomain
        } else {
            subtitle = selectedTab.url?.baseDomain
        }

        return SiteProtectionsData(
            title: selectedTab.displayTitle,
            subtitle: subtitle,
            image: selectedTab.url?.absoluteString,
            state: siteProtectionState(for: selectedTab)
        )
    }

    // MARK: - User agent

    func toggleUserAgent(for windowUUID: WindowUUID) {
        guard let selectedTab = tabManager(for: windowUUID)?.selectedTab,
              let url = selectedTab.url else { return }

        // When the user changes user agent do the new request using the original URL
        let originalURL = InternalURL(url)?.originalURLFromErrorPage ?? url
        selectedTab.toggleChangeUserAgent(originalURL: originalURL)
        Tab.ChangeUserAgent.updateDomainList(
            forUrl: originalURL,
            isChangedUA: selectedTab.changedUserAgent,
            isPrivate: selectedTab.isPrivate
        )
    }

    // MARK: - Shortcuts and bookmarks

    func addToShortcuts(tabID: TabUUID?, windowUUID: WindowUUID) {
        guard let site = site(for: tabID, windowUUID: windowUUID) else { return }
        profile.pinnedSites.addPinnedTopSite(site)
        store.dispatch(
            TopSitesAction(
                shortcutPinnedSource: .appMenu,
                windowUUID: windowUUID,
                actionType: TopSitesActionType.shortcutPinned
            )
        )
    }

    func removeFromShortcuts(tabID: TabUUID?, windowUUID: WindowUUID) {
        guard let site = site(for: tabID, windowUUID: windowUUID) else { return }
        profile.pinnedSites.removeFromPinnedTopSites(site)
        store.dispatch(
            TopSitesAction(
                shortcutUnpinnedSource: .appMenu,
                windowUUID: windowUUID,
                actionType: TopSitesActionType.shortcutUnpinned
            )
        )
    }

    /// TODO: `TabManagerMiddleware` keeps its own copy for the tab-peek path; the two converge
    /// when Tabs migrates in Phase 3.
    func addToBookmarks(tabID: TabUUID?, windowUUID: WindowUUID) -> String? {
        guard let tabID,
              let tab = tabManager(for: windowUUID)?.getTabForUUID(uuid: tabID),
              let url = tab.url?.absoluteString, !url.isEmpty
        else { return nil }

        var title = (tab.tabState.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { title = url }

        Task { [bookmarksSaver] in
            await bookmarksSaver.createBookmark(url: url, title: title, position: 0)
        }

        QuickActionsImplementation().addDynamicApplicationShortcutItemOfType(
            .openLastBookmark,
            withUserData: [QuickActionInfos.tabURLKey: url, QuickActionInfos.tabTitleKey: title],
            toApplication: .shared
        )
        return url
    }

    // MARK: - Private

    private func site(for tabID: TabUUID?, windowUUID: WindowUUID) -> Site? {
        guard let tabID,
              let tab = tabManager(for: windowUUID)?.getTabForUUID(uuid: tabID),
              let url = tab.url?.displayURL?.absoluteString
        else { return nil }
        return Site.createBasicSite(url: url, title: tab.displayTitle)
    }

    private struct ProfileTabInfo {
        let isBookmarked: Bool
        let isInReadingList: Bool
        let isPinned: Bool
    }

    private func tabManager(for windowUUID: WindowUUID) -> TabManager? {
        return windowManager.tabManager(for: windowUUID)
    }

    private func profileTabInfo(for tabURL: URL?) async -> ProfileTabInfo {
        guard let tabURL, let url = absoluteString(from: tabURL) else {
            return ProfileTabInfo(isBookmarked: false, isInReadingList: false, isPinned: false)
        }

        async let isBookmarked = isBookmarked(url: url)
        async let isPinned = isPinned(url: url)
        async let isInReadingList = isInReadingList(url: url)

        return await ProfileTabInfo(
            isBookmarked: isBookmarked,
            isInReadingList: isInReadingList,
            isPinned: isPinned
        )
    }

    private func isBookmarked(url: String) async -> Bool {
        return await withCheckedContinuation { continuation in
            profile.places.isBookmarked(url: url).uponQueue(.global()) { result in
                continuation.resume(returning: result.successValue ?? false)
            }
        }
    }

    private func isPinned(url: String) async -> Bool {
        return await withCheckedContinuation { continuation in
            profile.pinnedSites.isPinnedTopSite(url).uponQueue(.global()) { result in
                continuation.resume(returning: result.successValue ?? false)
            }
        }
    }

    private func isInReadingList(url: String) async -> Bool {
        return await withCheckedContinuation { continuation in
            profile.readingList.getRecordWithURL(url).uponQueue(.global()) { result in
                continuation.resume(returning: result.successValue != nil)
            }
        }
    }

    private func absoluteString(from url: URL) -> String? {
        return url.decodeReaderModeURL?.absoluteString ?? url.absoluteString
    }

    private func makeTabInfo(selectedTab: Tab,
                             windowUUID: WindowUUID,
                             accountData: AccountData,
                             profileInfo: ProfileTabInfo,
                             summarizerConfig: SummarizerConfig?) -> MainMenuTabInfo {
        return MainMenuTabInfo(
            tabID: selectedTab.tabUUID,
            url: selectedTab.url,
            canonicalURL: selectedTab.canonicalURL?.displayURL,
            isHomepage: selectedTab.isFxHomeTab,
            isDefaultUserAgentDesktop: UserAgent.isDesktop(ua: UserAgent.getUserAgent()),
            hasChangedUserAgent: selectedTab.changedUserAgent,
            zoomLevel: selectedTab.pageZoom,
            readerModeConfiguration: ReaderModeConfiguration(
                isAvailable: selectedTab.readerModeAvailableOrActive,
                isActive: selectedTab.readerModeState == .active
            ),
            summaryIsAvailable: summarizerConfig != nil,
            summarizerConfig: summarizerConfig,
            isBookmarked: profileInfo.isBookmarked,
            isInReadingList: profileInfo.isInReadingList,
            isPinned: profileInfo.isPinned,
            accountData: accountData,
            translationConfiguration: translationConfiguration(for: windowUUID)
        )
    }

    /// The toolbar still keeps this in Redux; it moves to a direct read when Toolbar migrates.
    private func translationConfiguration(for windowUUID: WindowUUID) -> TranslationConfiguration? {
        let toolbarState = store.state.componentState(ToolbarState.self, for: .toolbar, window: windowUUID)
        return toolbarState?.addressToolbar.translationConfiguration
    }

    private func siteProtectionState(for selectedTab: Tab) -> SiteProtectionsState {
        let isContentBlockingConfigEnabled = profile.prefs.boolForKey(ContentBlockingConfig.Prefs.EnabledKey) ?? true
        guard let url = selectedTab.url,
              !ContentBlocker.shared.isSafelisted(url: url),
              isContentBlockingConfigEnabled else { return .off }
        return selectedTab.webView?.hasOnlySecureContent ?? false ? .on : .notSecure
    }

    private func accountData() -> AccountData {
        let rustAccount = RustFirefoxAccounts.shared

        switch rustAccount.accountTransition {
        case .signingOut:
            return AccountData(title: .MainMenu.Account.SigningOutTitle, subtitle: nil)
        case .idle:
            break
        }

        let needsReAuth = rustAccount.accountNeedsReauth()

        guard let userProfile = rustAccount.userProfile else {
            return AccountData(title: .MainMenu.Account.SignedOutTitle,
                               subtitle: .MainMenu.Account.SignedOutDescriptionV2,
                               needsReAuth: nil,
                               iconURL: nil)
        }

        let subtitle: String? = needsReAuth
            ? .MainMenu.Account.SyncErrorDescription
            : .MainMenu.Account.SignedInDescription
        var iconURL: URL?
        if let str = userProfile.avatarUrl, let url = URL(string: str) {
            iconURL = url
        }

        return AccountData(title: userProfile.displayName ?? userProfile.email,
                           subtitle: subtitle,
                           needsReAuth: needsReAuth,
                           iconURL: iconURL)
    }
}
