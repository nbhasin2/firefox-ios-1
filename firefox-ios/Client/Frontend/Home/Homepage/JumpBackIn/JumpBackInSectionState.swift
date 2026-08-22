// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import ModifiedCopy
import Shared
import Storage

/// State for the jump back in section that is used in the homepage view
@Copyable
struct JumpBackInSectionState: Equatable, Hashable {
    let jumpBackInTabs: [JumpBackInTabConfiguration]
    let mostRecentSyncedTab: JumpBackInSyncedTabConfiguration?
    let shouldShowSection: Bool

    struct Constants {
        static let sectionHeaderConfiguration = SectionHeaderConfiguration(
            title: .FirefoxHomeJumpBackInSectionTitle,
            a11yIdentifier: AccessibilityIdentifiers.FirefoxHomepage.SectionTitles.jumpBackIn,
            isButtonHidden: false,
            buttonA11yIdentifier: AccessibilityIdentifiers.FirefoxHomepage.MoreButtons.jumpBackIn,
            buttonTitle: .BookmarksSavedShowAllText
        )
    }

    init(userPreferences: UserFeaturePreferring = AppContainer.shared.resolve()) {
        self.init(
            jumpBackInTabs: [],
            mostRecentSyncedTab: nil,
            shouldShowSection: userPreferences.getPreferenceFor(.homepageJumpBackinSectionDefault)
        )
    }

    /// Seeds a state directly, for tests and for the view model's `copy` chain.
    init(
        jumpBackInTabs: [JumpBackInTabConfiguration],
        mostRecentSyncedTab: JumpBackInSyncedTabConfiguration?,
        shouldShowSection: Bool
    ) {
        self.jumpBackInTabs = jumpBackInTabs
        self.mostRecentSyncedTab = mostRecentSyncedTab
        self.shouldShowSection = shouldShowSection
    }
}
