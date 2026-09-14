// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Foundation
import Shared

/// Replaces `TopSitesSectionState`'s reducer.
///
/// `TopSitesSectionState` stays a plain struct because the diffable data source and the layout
/// provider both take one; only its Redux conformance goes.
@MainActor
final class TopSitesSectionViewModel: Notifiable {
    private(set) var state: TopSitesSectionState {
        didSet {
            guard state != oldValue else { return }
            onChange?()
        }
    }

    var onChange: (() -> Void)?

    private let windowUUID: WindowUUID
    let notificationCenter: NotificationProtocol

    init(windowUUID: WindowUUID,
         profile: Profile = AppContainer.shared.resolve(),
         topSitesService: TopSitesService = .shared,
         featureFlagsProvider: FeatureFlagProviding = AppContainer.shared.resolve(),
         notificationCenter: NotificationProtocol = NotificationCenter.default,
         initialState: TopSitesSectionState? = nil) {
        self.windowUUID = windowUUID
        self.notificationCenter = notificationCenter
        self.state = initialState ?? TopSitesSectionState(
            profile: profile,
            shouldShowAddShortcutTile: featureFlagsProvider.isEnabled(.homepageAddShortcutTile)
        )
        topSitesService.addSitesObserver(self) { [weak self] sites in
            self?.updateSites(sites)
        }
        startObservingNotifications(
            withNotificationCenter: notificationCenter,
            forObserver: self,
            observing: [.homepageSectionSettingsChanged]
        )
    }

    nonisolated func handleNotifications(_ notification: Notification) {
        guard notification.name == .homepageSectionSettingsChanged else { return }
        let info = notification.userInfo
        let uuid = info?[HomepageSectionSettingsNotification.windowUUIDKey] as? WindowUUID
        let section = info?[HomepageSectionSettingsNotification.sectionKey] as? String
        let isEnabled = info?[HomepageSectionSettingsNotification.isEnabledKey] as? Bool
        let numberOfRows = info?[HomepageSectionSettingsNotification.numberOfRowsKey] as? Int
        Task { @MainActor [weak self] in
            guard let self,
                  uuid == self.windowUUID,
                  section == HomepageSectionSettingsNotification.Section.topSites.rawValue
            else { return }
            if let isEnabled { self.setSectionEnabled(isEnabled) }
            if let numberOfRows { self.setNumberOfRows(numberOfRows) }
        }
    }

    // MARK: - Intents

    func setSectionEnabled(_ isEnabled: Bool) {
        state = state.copy(shouldShowSection: isEnabled)
    }

    func setNumberOfRows(_ numberOfRows: Int) {
        state = state
            .copy(numberOfRows: numberOfRows)
            .copy(shouldShowSectionHeader: shouldShowSectionHeader(numberOfRows: numberOfRows))
    }

    /// The homepage recomputes this from its own width on layout and rotation.
    func setNumberOfTilesPerRow(_ numberOfTilesPerRow: Int) {
        state = state
            .copy(numberOfTilesPerRow: numberOfTilesPerRow)
            .copy(shouldShowSectionHeader: shouldShowSectionHeader(numberOfTilesPerRow: numberOfTilesPerRow))
    }

    // MARK: - Private

    private func updateSites(_ sites: [TopSiteConfiguration]) {
        state = state
            .copy(topSitesData: sites)
            .copy(shouldShowSectionHeader: shouldShowSectionHeader(siteCount: sites.count))
    }

    /// Shows the shortcuts section header with shortcuts library affordance
    /// when real shortcuts overflow the visible grid,
    /// or when the Add Shortcut tile is displaced by a full visible grid.
    private func shouldShowSectionHeader(siteCount: Int? = nil,
                                         numberOfRows: Int? = nil,
                                         numberOfTilesPerRow: Int? = nil) -> Bool {
        let siteCount = siteCount ?? state.topSitesData.count
        let maxVisibleTileCount = (numberOfRows ?? state.numberOfRows)
            * (numberOfTilesPerRow ?? state.numberOfTilesPerRow)
        guard maxVisibleTileCount > 0 else { return false }

        return siteCount > maxVisibleTileCount ||
            (state.shouldShowAddShortcutTile && siteCount >= maxVisibleTileCount)
    }
}
