// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Foundation
import ModifiedCopy
import Shared

/// State for the top sites section that is used in the homepage
/// The state does not only contain the top sites list, but needs to also know about the number of rows
/// and tiles per row in order to only show a specific amount of the top sites data.
@Copyable
struct TopSitesSectionState: Equatable {
    let topSitesData: [TopSiteConfiguration]
    let numberOfRows: Int
    let numberOfTilesPerRow: Int
    let shouldShowSection: Bool
    let shouldShowSectionHeader: Bool
    let shouldShowAddShortcutTile: Bool

    struct Constants {
        static let sectionHeaderConfiguration = SectionHeaderConfiguration(
            title: .FirefoxHomepage.Shortcuts.SectionTitle,
            a11yIdentifier: AccessibilityIdentifiers.FirefoxHomepage.SectionTitles.topSites,
            isButtonHidden: false,
            buttonA11yIdentifier: AccessibilityIdentifiers.FirefoxHomepage.MoreButtons.shortcuts,
            buttonTitle: .BookmarksSavedShowAllText
        )
    }

    init(profile: Profile = AppContainer.shared.resolve(),
         shouldShowAddShortcutTile: Bool = false) {
        let preferredNumberOfRows = profile.prefs.intForKey(PrefsKeys.NumberOfTopSiteRows)
        let defaultNumberOfRows = TopSitesRowCountSettingsController.defaultNumberOfRows
        let numberOfRows = Int(preferredNumberOfRows ?? defaultNumberOfRows)
        let shouldShowSection = profile.prefs.boolForKey(PrefsKeys.UserFeatureFlagPrefs.TopSiteSection) ?? true

        self.init(
            topSitesData: [],
            numberOfRows: numberOfRows,
            numberOfTilesPerRow: TopSitesSectionLayoutProvider.UX.minCards,
            shouldShowSection: shouldShowSection,
            shouldShowSectionHeader: false,
            shouldShowAddShortcutTile: shouldShowAddShortcutTile
        )
    }

    /// Seeds a state directly, for tests and for the view model's `copy` chain.
    init(
        topSitesData: [TopSiteConfiguration],
        numberOfRows: Int,
        numberOfTilesPerRow: Int,
        shouldShowSection: Bool,
        shouldShowSectionHeader: Bool,
        shouldShowAddShortcutTile: Bool
    ) {
        self.topSitesData = topSitesData
        self.numberOfRows = numberOfRows
        self.numberOfTilesPerRow = numberOfTilesPerRow
        self.shouldShowSection = shouldShowSection
        self.shouldShowSectionHeader = shouldShowSectionHeader
        self.shouldShowAddShortcutTile = shouldShowAddShortcutTile
    }
}
