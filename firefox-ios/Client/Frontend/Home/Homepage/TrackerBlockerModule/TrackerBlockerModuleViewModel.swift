// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Foundation

/// Replaces `TrackerBlockerModuleMiddleware` and `TrackerBlockerModuleState`.
///
/// Feeds the homepage tracker-blocker module its lifetime blocked-tracker count from the persisted
/// `TrackerBlockStatsStore`. The count is recomputed whenever the homepage is shown or the app
/// returns to the foreground, since blocking happens off the homepage while the user browses.
///
/// Fully synchronous, as the middleware was.
@MainActor
final class TrackerBlockerModuleViewModel {
    private static let minReportableFigures = 4
    private static let maxReportableFigures = 8

    private(set) var shouldShowSection: Bool
    private(set) var blockedTrackerCount = 0

    var onChange: (() -> Void)?

    private let statsStore: TrackerBlockStatsStore
    private let telemetry: TrackerBlockerTelemetry
    private let featureFlagsProvider: FeatureFlagProviding

    init(statsStore: TrackerBlockStatsStore? = nil,
         telemetry: TrackerBlockerTelemetry = TrackerBlockerTelemetry(),
         userPreferences: UserFeaturePreferring = AppContainer.shared.resolve(),
         featureFlagsProvider: FeatureFlagProviding = AppContainer.shared.resolve()) {
        if let statsStore {
            self.statsStore = statsStore
        } else {
            let prefs = (AppContainer.shared.resolve() as Profile).prefs
            self.statsStore = DefaultTrackerBlockStatsStoreUtility(prefs: prefs)
        }
        self.telemetry = telemetry
        self.featureFlagsProvider = featureFlagsProvider
        self.shouldShowSection = featureFlagsProvider.isEnabled(.homepageTrackerBlockerModule)
            && userPreferences.getPreferenceFor(.homepageTrackerBlockerModule)
    }

    // MARK: - Intents

    /// Called on homepage initialize, view-did-appear, and app foreground — the three points the
    /// middleware recomputed on.
    func refreshBlockedCount() {
        let count = statsStore.lifetimeTotal()
        recordThresholdCrossings(for: count)
        guard count != blockedTrackerCount else { return }
        blockedTrackerCount = count
        onChange?()
    }

    func setSectionEnabled(_ isEnabled: Bool) {
        let newValue = featureFlagsProvider.isEnabled(.homepageTrackerBlockerModule) ? isEnabled : false
        guard newValue != shouldShowSection else { return }
        shouldShowSection = newValue
        onChange?()
    }

    // MARK: - Private

    /// Fires a telemetry event for each digit-count boundary (4...8 figures) the lifetime total has
    /// newly crossed, then persists the high-water mark so no boundary is reported more than once.
    private func recordThresholdCrossings(for count: Int) {
        guard count > 0 else { return }
        let figures = String(count).count
        guard figures >= Self.minReportableFigures else { return }

        let cappedFigures = min(figures, Self.maxReportableFigures)
        let alreadyReported = statsStore.highestReportedFigures()
        guard cappedFigures > alreadyReported else { return }

        let firstToReport = max(Self.minReportableFigures, alreadyReported + 1)
        for boundary in firstToReport...cappedFigures {
            telemetry.lifetimeThresholdReached(figures: boundary)
        }
        statsStore.setHighestReportedFigures(cappedFigures)
    }
}
