// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Foundation
import Redux
import Shared
import Storage
import UIKit

/// Replaces `TabPeekState` and the tab-peek block of `TabManagerMiddleware`.
///
/// `TabPeekState` stays a plain struct because the view controller reads its fields directly;
/// only its Redux conformance goes.
///
/// Four of the five actions were commands on the tab and bookmark layers that happened to be
/// routed through the store — bookmark it, unbookmark it, copy its URL, load its preview. They are
/// method calls now. The fifth, closing the tab, still dispatches: `TabManagerMiddleware` needs
/// `TabsPanelState.isPrivateMode` to do it, and the tabs panel has not migrated.
@MainActor
final class TabPeekViewModel: CanRemoveQuickActionBookmark {
    private(set) var state: TabPeekState {
        didSet { onChange?(state) }
    }

    var onChange: ((TabPeekState) -> Void)?

    private let tabUUID: TabUUID
    private let windowUUID: WindowUUID
    private let profile: Profile
    private let windowManager: WindowManager
    private let bookmarksSaver: BookmarksSaver
    let bookmarksHandler: BookmarksHandler

    init(tabUUID: TabUUID,
         windowUUID: WindowUUID,
         profile: Profile = AppContainer.shared.resolve(),
         windowManager: WindowManager = AppContainer.shared.resolve(),
         bookmarksSaver: BookmarksSaver? = nil,
         bookmarksHandler: BookmarksHandler? = nil) {
        self.tabUUID = tabUUID
        self.windowUUID = windowUUID
        self.profile = profile
        self.windowManager = windowManager
        self.bookmarksSaver = bookmarksSaver ?? DefaultBookmarksSaver(profile: profile)
        self.bookmarksHandler = bookmarksHandler ?? profile.places
        self.state = TabPeekState(windowUUID: windowUUID)
    }

    // MARK: - Intents

    func viewDidLoad() {
        let tab = self.tab
        let urlString = tab?.url?.absoluteString ?? ""

        Task { @MainActor [weak self] in
            guard let self else { return }
            let isBookmarked = await self.isBookmarked(url: urlString)
            self.state = self.state
                .copy(showAddToBookmarks: Self.canBeSaved(tab: tab,
                                                          isBookmarked: isBookmarked,
                                                          urlString: urlString))
                .copy(showRemoveBookmark: isBookmarked)
                .copy(showSendToDevice: self.profile.hasSyncableAccount()
                      && Self.canBeSaved(tab: tab, isBookmarked: isBookmarked, urlString: urlString))
                .copy(showCopyURL: Self.canCopyURL(tab: tab, urlString: urlString))
                .copy(previewAccessibilityLabel: tab?.webView?.accessibilityLabel ?? "")
                .copy(screenshot: tab?.screenshot ?? UIImage())
        }
    }

    func addToBookmarks() {
        guard let shareItem = makeShareItem() else { return }
        Task { [bookmarksSaver] in
            await bookmarksSaver.createBookmark(url: shareItem.url, title: shareItem.title, position: 0)
        }
        addQuickActionShortcut(for: shareItem)
    }

    func removeBookmark() {
        guard let url = tab?.url?.absoluteString, !url.isEmpty else { return }
        profile.places.deleteBookmarksWithURL(url: url).uponQueue(.main) { [weak self] result in
            // FXIOS-13228 It should be safe to assumeIsolated here because of `.main` queue above
            MainActor.assumeIsolated {
                guard result.isSuccess, let self else { return }
                Self.removeBookmarkShortcut(withBookmarksHandler: self.bookmarksHandler)
            }
        }
    }

    func copyURL() {
        UIPasteboard.general.url = tab?.canonicalURL
    }

    /// Still a dispatch: closing needs the tabs panel's private-mode flag, which lives in
    /// `TabsPanelState`.
    func closeTab() {
        store.dispatch(
            TabPeekAction(tabUUID: tabUUID,
                          windowUUID: windowUUID,
                          actionType: TabPeekActionType.closeTab)
        )
    }

    // MARK: - Private

    private var tab: Tab? {
        return windowManager.tabManager(for: windowUUID)?.getTabForUUID(uuid: tabUUID)
    }

    private func isBookmarked(url: String) async -> Bool {
        return await withCheckedContinuation { continuation in
            bookmarksHandler.isBookmarked(url: url) { result in
                continuation.resume(returning: (try? result.get()) ?? false)
            }
        }
    }

    private func makeShareItem() -> ShareItem? {
        guard let tab, let url = tab.url?.absoluteString, !url.isEmpty else { return nil }
        var title = (tab.tabState.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { title = url }
        return ShareItem(url: url, title: title)
    }

    /// The middleware registered this twice per bookmark — once in `addToBookmarks` and again in
    /// `setBookmarkQuickActions`, both called from the same switch case.
    private func addQuickActionShortcut(for shareItem: ShareItem) {
        var userData = [QuickActionInfos.tabURLKey: shareItem.url]
        if let title = shareItem.title {
            userData[QuickActionInfos.tabTitleKey] = title
        }
        QuickActionsImplementation().addDynamicApplicationShortcutItemOfType(
            .openLastBookmark,
            withUserData: userData,
            toApplication: .shared
        )
    }

    /// Can be saved only if it is not already bookmarked, the URL is not too long (database
    /// restriction), and it is not a homepage (FxHome) tab or empty url
    private static func canBeSaved(tab: Tab?, isBookmarked: Bool, urlString: String) -> Bool {
        guard let tab else { return false }
        return !isBookmarked && !tab.urlIsTooLong && !tab.isFxHomeTab && !urlString.isEmpty
    }

    private static func canCopyURL(tab: Tab?, urlString: String) -> Bool {
        guard let tab else { return false }
        return !tab.isFxHomeTab && !urlString.isEmpty
    }
}
