// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Foundation
import Redux
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
    let wallpaper: WallpaperViewModel
    let topSitesService: TopSitesService
    let topSites: TopSitesSectionViewModel
    let jumpBackIn: JumpBackInSectionViewModel

    /// FXIOS-11504 / FXIOS-6203 - true when the homepage was opened from the tab tray, a long
    /// press on the tab bar, or the home button, rather than by tapping the url bar on a loaded
    /// page. Drives top sites and merino telemetry and the contextual pop-overs. Set by
    /// `BrowserCoordinator`, which embeds the homepage and is the only thing that knows.
    private(set) var isZeroSearch = false

    /// True when a new privacy notice is available after the user already accepted the ToS/ToU.
    private(set) var shouldShowPrivacyNotice = false

    /// Fired when the homepage should re-record impressions from scratch.
    var onImpressionReset: (() -> Void)?

    /// Fired when any owned section changes and the snapshot needs re-applying.
    var onSectionChange: (() -> Void)?

    private let windowUUID: WindowUUID
    private let privacyNoticeHelper: PrivacyNoticeHelperProtocol
    private let telemetry: HomepageTelemetry
    /// The privacy notice is a Terms of Use surface, so its impression and dismissal are ToU
    /// events. They were recorded in `HomepageMiddleware` after `TermsOfUseMiddleware` went.
    private let termsOfUseTelemetry: TermsOfUseTelemetry
    /// The store holds observers weakly and sweeps dead ones, so there is nothing to unregister.
    private let bus: (any ActionObserving)?

    let notificationCenter: NotificationProtocol

    init(windowUUID: WindowUUID,
         messageCard: MessageCardViewModel? = nil,
         trackerBlockerModule: TrackerBlockerModuleViewModel? = nil,
         bookmarks: BookmarksSectionViewModel? = nil,
         merino: MerinoSectionViewModel? = nil,
         searchBar: SearchBarViewModel? = nil,
         header: HeaderViewModel? = nil,
         wallpaper: WallpaperViewModel? = nil,
         topSites: TopSitesSectionViewModel? = nil,
         jumpBackIn: JumpBackInSectionViewModel? = nil,
         topSitesService: TopSitesService = .shared,
         privacyNoticeHelper: PrivacyNoticeHelperProtocol? = nil,
         telemetry: HomepageTelemetry = HomepageTelemetry(),
         termsOfUseTelemetry: TermsOfUseTelemetry = TermsOfUseTelemetry(),
         profile: Profile = AppContainer.shared.resolve(),
         bus: (any ActionObserving)? = store,
         notificationCenter: NotificationProtocol = NotificationCenter.default) {
        self.windowUUID = windowUUID
        self.messageCard = messageCard ?? MessageCardViewModel(windowUUID: windowUUID)
        self.trackerBlockerModule = trackerBlockerModule ?? TrackerBlockerModuleViewModel()
        self.bookmarks = bookmarks ?? BookmarksSectionViewModel()
        self.merino = merino ?? MerinoSectionViewModel()
        self.searchBar = searchBar ?? SearchBarViewModel(windowUUID: windowUUID)
        self.header = header ?? HeaderViewModel(windowUUID: windowUUID)
        self.wallpaper = wallpaper ?? WallpaperViewModel()
        self.topSitesService = topSitesService
        self.topSites = topSites ?? TopSitesSectionViewModel(
            windowUUID: windowUUID,
            topSitesService: topSitesService
        )
        self.jumpBackIn = jumpBackIn ?? JumpBackInSectionViewModel(windowUUID: windowUUID)
        self.privacyNoticeHelper = privacyNoticeHelper ?? PrivacyNoticeHelper(prefs: profile.prefs)
        self.telemetry = telemetry
        self.termsOfUseTelemetry = termsOfUseTelemetry
        self.bus = bus
        self.notificationCenter = notificationCenter
        bindSections()
        observeTabChange()
        // The migrated sections observe their own refresh triggers. `HomepageMiddleware` still
        // observes the same names for the sections that have not moved yet; both can coexist
        // because each only acts on its own sections.
        startObservingNotifications(
            withNotificationCenter: notificationCenter,
            forObserver: self,
            observing: [.homepageSectionSettingsChanged,
                        UIApplication.didBecomeActiveNotification,
                        .BookmarksUpdated,
                        .RustPlacesOpened,
                        // The five that used to reach TopSitesMiddleware through
                        // HomepageMiddlewareActionType.topSitesUpdated. Observing them per window
                        // replaces the middleware's fan-out over every window.
                        .TopSitesUpdated,
                        .PrivateDataClearedHistory,
                        .DefaultSearchEngineUpdated,
                        .ProfileDidFinishSyncing,
                        .FirefoxAccountChanged]
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
                case .TopSitesUpdated, .PrivateDataClearedHistory, .DefaultSearchEngineUpdated:
                    self?.refreshTopSites()
                case .ProfileDidFinishSyncing, .FirefoxAccountChanged:
                    // Both sections used to be refreshed off these through the middleware.
                    self?.refreshTopSites()
                    self?.jumpBackIn.refresh()
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
            case .jumpBackIn:
                self.jumpBackIn.setSectionEnabled(isEnabled)
            case .topSites:
                // TopSitesSectionViewModel observes the notification itself; it needs the row
                // count too, which this switch does not carry.
                break
            case nil:
                break
            }
        }
    }

    // MARK: - Lifecycle

    /// Set by `BrowserCoordinator` when it embeds the homepage; see `isZeroSearch`.
    func setZeroSearch(_ isZeroSearch: Bool) {
        self.isZeroSearch = isZeroSearch
    }

    /// A tab switched to the homepage, so impressions should be recorded again from scratch.
    func didSelectTabChangeToHomepage() {
        onImpressionReset?()
    }

    // MARK: - Privacy notice

    func configurePrivacyNoticeIfNeeded() {
        guard privacyNoticeHelper.shouldShowPrivacyNotice() else { return }
        termsOfUseTelemetry.termsOfUseDisplayed(surface: .privacyNotice)
        shouldShowPrivacyNotice = true
        onSectionChange?()
    }

    func privacyNoticeDismissed() {
        termsOfUseTelemetry.termsOfUseDismissed(surface: .privacyNotice)
        shouldShowPrivacyNotice = false
        onSectionChange?()
    }

    // MARK: - Telemetry

    func recordHomepageImpression() {
        telemetry.sendHomepageImpressionEvent()
    }

    func recordItemTapped(_ itemType: HomepageTelemetry.ItemType) {
        telemetry.sendItemTappedTelemetryEvent(for: itemType)
    }

    func recordSectionSeen(_ itemType: HomepageTelemetry.ItemType) {
        switch itemType {
        case .quickAnswersEntryPoint:
            telemetry.sendQuickAnswersButtonViewedEvent()
        default:
            telemetry.sendSectionLabeledCounter(for: itemType)
        }
    }

    /// Homepage `initialize`.
    func viewDidLoad() {
        messageCard.viewDidLoad()
        trackerBlockerModule.refreshBlockedCount()
        bookmarks.refreshBookmarks()
        merino.refreshStories()
        searchBar.refreshVisibility()
        header.refresh()
        refreshTopSites()
        jumpBackIn.refresh()
        configurePrivacyNoticeIfNeeded()
    }

    /// Homepage `viewWillAppear`.
    func viewWillAppear() {
        header.refresh()
        jumpBackIn.refresh()
    }

    /// Homepage `viewDidAppear`, and app foreground.
    func refreshOnAppearance() {
        trackerBlockerModule.refreshBlockedCount()
    }

    /// App returned to the foreground.
    func refreshOnBecomeActive() {
        trackerBlockerModule.refreshBlockedCount()
        merino.refreshStories()
        refreshTopSites()
    }

    /// The top sites changed underneath the homepage, or it is being shown for the first time.
    func refreshTopSites() {
        topSitesService.refresh(for: windowUUID)
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

    /// FXIOS-11523 - a tab switching to the homepage is a browser-level event with no ownership
    /// path here, so it comes off the bus (D-016) rather than through a `ScreenState`.
    private func observeTabChange() {
        bus?.addActionObserver(self) { [weak self] action in
            guard let self,
                  action.windowUUID == self.windowUUID || action.windowUUID == .unavailable,
                  action.actionType as? GeneralBrowserActionType == .didSelectedTabChangeToHomepage
            else { return }
            self.didSelectTabChangeToHomepage()
        }
    }

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
        topSites.onChange = { [weak self] in
            self?.onSectionChange?()
        }
        jumpBackIn.onChange = { [weak self] in
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
    /// Only the top sites section carries this; it has a row-count setting as well as a toggle.
    static let numberOfRowsKey = "numberOfRows"

    enum Section: String {
        case trackerBlockerModule
        case bookmarks
        case merino
        case topSites
        case jumpBackIn
    }

    @MainActor
    static func post(section: Section,
                     isEnabled: Bool? = nil,
                     numberOfRows: Int? = nil,
                     windowUUID: WindowUUID,
                     notificationCenter: NotificationProtocol = NotificationCenter.default) {
        var userInfo: [String: Any] = [windowUUIDKey: windowUUID, sectionKey: section.rawValue]
        userInfo[isEnabledKey] = isEnabled
        userInfo[numberOfRowsKey] = numberOfRows
        notificationCenter.post(
            name: .homepageSectionSettingsChanged,
            withObject: nil,
            withUserInfo: userInfo
        )
    }
}
