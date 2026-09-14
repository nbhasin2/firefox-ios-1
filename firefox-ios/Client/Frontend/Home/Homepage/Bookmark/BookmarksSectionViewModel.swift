// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Foundation
import Shared
import Storage

/// Replaces `BookmarksMiddleware` and `BookmarksSectionState`.
///
/// `getRecentBookmarks` is completion-handler based; the bridge narrows it to
/// `[BookmarkConfiguration]` before crossing the continuation, per D-013.
@MainActor
final class BookmarksSectionViewModel {
    struct Constants {
        static let sectionHeaderConfiguration = SectionHeaderConfiguration(
            title: .BookmarksSectionTitle,
            a11yIdentifier: AccessibilityIdentifiers.FirefoxHomepage.SectionTitles.bookmarks,
            isButtonHidden: false,
            buttonA11yIdentifier: AccessibilityIdentifiers.FirefoxHomepage.MoreButtons.bookmarks,
            buttonTitle: .BookmarksSavedShowAllText
        )
    }

    private static let bookmarkItemsLimit: UInt = 8

    private(set) var bookmarks: [BookmarkConfiguration] = []
    private(set) var shouldShowSection: Bool

    var onChange: (() -> Void)?

    private let bookmarksHandler: BookmarksHandler
    private var loadTask: Task<Void, Never>?

    init(profile: Profile = AppContainer.shared.resolve(),
         bookmarksHandler: BookmarksHandler? = nil,
         userPreferences: UserFeaturePreferring = AppContainer.shared.resolve(),
         initialBookmarks: [BookmarkConfiguration] = []) {
        self.bookmarksHandler = bookmarksHandler ?? profile.places
        self.shouldShowSection = userPreferences.getPreferenceFor(.homepageBookmarksSectionDefault)
        self.bookmarks = initialBookmarks
    }

    deinit {
        loadTask?.cancel()
    }

    // MARK: - Intents

    /// Called on homepage initialize and whenever bookmarks change underneath us.
    func refreshBookmarks() {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            let bookmarks = await self.recentBookmarks()
            guard !Task.isCancelled else { return }
            // No change-detection here: `BookmarkConfiguration` carries a fresh `UUID` as its
            // identity, so two configurations for the same bookmark never compare equal.
            self.bookmarks = bookmarks
            self.onChange?()
        }
    }

    func setSectionEnabled(_ isEnabled: Bool) {
        guard isEnabled != shouldShowSection else { return }
        shouldShowSection = isEnabled
        onChange?()
    }

    // MARK: - Private

    private func recentBookmarks() async -> [BookmarkConfiguration] {
        return await withCheckedContinuation { continuation in
            bookmarksHandler.getRecentBookmarks(limit: Self.bookmarkItemsLimit) { bookmarks in
                let configurations = bookmarks.map {
                    BookmarkConfiguration(
                        site: Site.createBasicSite(url: $0.url, title: $0.title, isBookmarked: true)
                    )
                }
                continuation.resume(returning: configurations)
            }
        }
    }
}
