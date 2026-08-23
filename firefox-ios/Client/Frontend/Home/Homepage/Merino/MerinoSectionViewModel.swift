// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Foundation
import Shared

/// Replaces `MerinoMiddleware` and `MerinoState`.
///
/// The middleware fetched stories in an unstructured `Task` with no cancellation and dispatched
/// from inside it. Here the fetch is owned by a stored `Task` that is cancelled on the next
/// refresh and on deinit.
@MainActor
final class MerinoSectionViewModel {
    struct Constants {
        static var sectionHeaderConfiguration: SectionHeaderConfiguration {
            // Computed because feature flag configuration can change after launch
            return SectionHeaderConfiguration(
                title: .FirefoxHomepage.Pocket.NewsSectionTitle,
                a11yIdentifier: AccessibilityIdentifiers.FirefoxHomepage.SectionTitles.merino,
                style: .newsAffordance
            )
        }
        static let footerURL = SupportUtils.URLForPocketLearnMore
    }

    private(set) var merinoData = MerinoStoryResponse()
    private(set) var hasMerinoResponseContent = false
    private(set) var shouldShowSection: Bool

    var onChange: (() -> Void)?

    var availableCategories: [MerinoCategoryConfiguration] {
        (merinoData.categories ?? []).filter { !$0.recommendations.isEmpty }
    }

    private let merinoManager: MerinoManagerProvider
    private let telemetry: HomepageTelemetry
    private let logger: Logger
    /// The user's preference, kept separately: `shouldShowSection` also depends on whether the
    /// response had content, and the reducer folded the two together on every update.
    private var isSectionPreferenceEnabled: Bool
    private var loadTask: Task<Void, Never>?

    init(profile: Profile = AppContainer.shared.resolve(),
         merinoManager: MerinoManagerProvider = AppContainer.shared.resolve(),
         telemetry: HomepageTelemetry = HomepageTelemetry(),
         logger: Logger = DefaultLogger.shared,
         initialResponse: MerinoStoryResponse? = nil) {
        self.merinoManager = merinoManager
        self.telemetry = telemetry
        self.logger = logger
        let userPrefs = profile.prefs.boolForKey(PrefsKeys.UserFeatureFlagPrefs.ASPocketStories) ?? true
        let isLocaleSupported = MerinoProvider.isLocaleSupported(Locale.current.identifier)
        self.isSectionPreferenceEnabled = userPrefs && isLocaleSupported
        self.shouldShowSection = userPrefs && isLocaleSupported
        if let initialResponse { apply(initialResponse) }
    }

    deinit {
        loadTask?.cancel()
    }

    // MARK: - Intents

    func visibleStories(selectedNewsfeedCategoryID: String?) -> [MerinoStoryConfiguration] {
        if !availableCategories.isEmpty {
            if let selectedNewsfeedCategoryID {
                return availableCategories
                    .first(where: { $0.feedID == selectedNewsfeedCategoryID })?.recommendations ?? []
            }
            return availableCategories.flatMap(\.recommendations)
        }
        return merinoData.stories ?? []
    }

    /// Called on homepage initialize, app foreground, and when the setting is toggled.
    func refreshStories() {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            let response = await self.merinoManager.getMerinoItems(source: .homepage)
            guard !Task.isCancelled else { return }
            self.apply(response)
        }
    }

    func setSectionEnabled(_ isEnabled: Bool) {
        isSectionPreferenceEnabled = isEnabled
        shouldShowSection = isEnabled
        onChange?()
        refreshStories()
    }

    func tapOnStory(position: Int, isZeroSearch: Bool) {
        telemetry.sendTapOnPocketStoryCounter(position: position, isZeroSearch: isZeroSearch)
    }

    func sectionViewed() {
        telemetry.sendPocketSectionCounter()
    }

    func openedInPrivateTab() {
        telemetry.sendOpenInPrivateTabEventForPocket()
    }

    // MARK: - Private

    private func apply(_ response: MerinoStoryResponse) {
        let categoriesContainStories = response.categories?.contains { !$0.recommendations.isEmpty } == true
        let contentExists = !(response.stories?.isEmpty ?? true) || categoriesContainStories

        merinoData = response
        hasMerinoResponseContent = contentExists
        shouldShowSection = contentExists && isSectionPreferenceEnabled
        onChange?()
    }
}
