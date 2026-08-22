// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Foundation
import Shared
import UIKit

/// Owns the homepage sections that have moved off Redux, and tells the view controller when any of
/// them changes so it can re-apply its snapshot.
///
/// The homepage migrates one section at a time (see refactor-tracking/PLAN.md Phase 3), so during
/// the migration the view controller renders from two sources: the shrinking `HomepageState` still
/// held in the store, and the growing set of section view models here. `HomepageDiffableDataSource`
/// takes both. When the last section moves, the state parameter goes away.
@MainActor
final class HomepageViewModel: Notifiable {
    let messageCard: MessageCardViewModel
    let trackerBlockerModule: TrackerBlockerModuleViewModel
    let bookmarks: BookmarksSectionViewModel
    let merino: MerinoSectionViewModel
    let searchBar: SearchBarViewModel
    let header: HeaderViewModel

    /// Fired when any owned section changes and the snapshot needs re-applying.
    var onSectionChange: (() -> Void)?

    private let windowUUID: WindowUUID

    let notificationCenter: NotificationProtocol

    init(windowUUID: WindowUUID,
         messageCard: MessageCardViewModel? = nil,
         trackerBlockerModule: TrackerBlockerModuleViewModel? = nil,
         bookmarks: BookmarksSectionViewModel? = nil,
         merino: MerinoSectionViewModel? = nil,
         searchBar: SearchBarViewModel? = nil,
         header: HeaderViewModel? = nil,
         notificationCenter: NotificationProtocol = NotificationCenter.default) {
        self.windowUUID = windowUUID
        self.messageCard = messageCard ?? MessageCardViewModel(windowUUID: windowUUID)
        self.trackerBlockerModule = trackerBlockerModule ?? TrackerBlockerModuleViewModel()
        self.bookmarks = bookmarks ?? BookmarksSectionViewModel()
        self.merino = merino ?? MerinoSectionViewModel()
        self.searchBar = searchBar ?? SearchBarViewModel(windowUUID: windowUUID)
        self.header = header ?? HeaderViewModel(windowUUID: windowUUID)
        self.notificationCenter = notificationCenter
        bindSections()
        // The migrated sections observe their own refresh triggers. `HomepageMiddleware` still
        // observes the same names for the sections that have not moved yet; both can coexist
        // because each only acts on its own sections.
        startObservingNotifications(
            withNotificationCenter: notificationCenter,
            forObserver: self,
            observing: [.homepageSectionSettingsChanged,
                        UIApplication.didBecomeActiveNotification,
                        .BookmarksUpdated,
                        .RustPlacesOpened]
        )
    }

    nonisolated func handleNotifications(_ notification: Notification) {
        let name = notification.name
        if name != .homepageSectionSettingsChanged {
            Task { @MainActor [weak self] in
                switch name {
                case UIApplication.didBecomeActiveNotification:
                    self?.refreshOnBecomeActive()
                case .BookmarksUpdated, .RustPlacesOpened:
                    self?.refreshBookmarks()
                default:
                    break
                }
            }
            return
        }

        let info = notification.userInfo
        let uuid = info?[HomepageSectionSettingsNotification.windowUUIDKey] as? WindowUUID
        let section = info?[HomepageSectionSettingsNotification.sectionKey] as? String
        let isEnabled = info?[HomepageSectionSettingsNotification.isEnabledKey] as? Bool
        Task { @MainActor [weak self] in
            guard let self, uuid == self.windowUUID, let isEnabled else { return }
            switch section.flatMap(HomepageSectionSettingsNotification.Section.init(rawValue:)) {
            case .trackerBlockerModule:
                self.trackerBlockerModule.setSectionEnabled(isEnabled)
            case .bookmarks:
                self.bookmarks.setSectionEnabled(isEnabled)
            case .merino:
                self.merino.setSectionEnabled(isEnabled)
            case nil:
                break
            }
        }
    }

    // MARK: - Lifecycle

    /// Homepage `initialize`.
    func viewDidLoad() {
        messageCard.viewDidLoad()
        trackerBlockerModule.refreshBlockedCount()
        bookmarks.refreshBookmarks()
        merino.refreshStories()
        searchBar.refreshVisibility()
        header.refresh()
    }

    /// Homepage `viewWillAppear`.
    func viewWillAppear() {
        header.refresh()
    }

    /// Homepage `viewDidAppear`, and app foreground.
    func refreshOnAppearance() {
        trackerBlockerModule.refreshBlockedCount()
    }

    /// App returned to the foreground.
    func refreshOnBecomeActive() {
        trackerBlockerModule.refreshBlockedCount()
        merino.refreshStories()
    }

    /// Homepage `viewWillTransition`, and the toolbar events that used to recompute visibility.
    func refreshSearchBarVisibility() {
        searchBar.refreshVisibility()
    }

    /// Bookmarks changed underneath the homepage.
    func refreshBookmarks() {
        bookmarks.refreshBookmarks()
    }

    // MARK: - Private

    private func bindSections() {
        messageCard.onConfigurationChange = { [weak self] _ in
            self?.onSectionChange?()
        }
        trackerBlockerModule.onChange = { [weak self] in
            self?.onSectionChange?()
        }
        bookmarks.onChange = { [weak self] in
            self?.onSectionChange?()
        }
        merino.onChange = { [weak self] in
            self?.onSectionChange?()
        }
        searchBar.onChange = { [weak self] in
            self?.onSectionChange?()
        }
        header.onChange = { [weak self] in
            self?.onSectionChange?()
        }
    }
}

extension Notification.Name {
    /// A homepage section's visibility was toggled in Settings. Carries the `WindowUUID`.
    ///
    /// The settings screens have no ownership path to the homepage and the toggle is not a
    /// browser-level event, so this is D-017 row three. One notification covers all six section
    /// toggles rather than one action type each.
    public static let homepageSectionSettingsChanged =
        Notification.Name("homepageSectionSettingsChanged")
}

enum HomepageSectionSettingsNotification {
    static let windowUUIDKey = "windowUUID"
    static let sectionKey = "section"
    static let isEnabledKey = "isEnabled"

    enum Section: String {
        case trackerBlockerModule
        case bookmarks
        case merino
    }

    @MainActor
    static func post(section: Section,
                     isEnabled: Bool,
                     windowUUID: WindowUUID,
                     notificationCenter: NotificationProtocol = NotificationCenter.default) {
        notificationCenter.post(
            name: .homepageSectionSettingsChanged,
            withObject: nil,
            withUserInfo: [windowUUIDKey: windowUUID,
                           sectionKey: section.rawValue,
                           isEnabledKey: isEnabled]
        )
    }
}
