// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Foundation
import Shared

/// Replaces `TermsOfUseMiddleware` and `TermsOfUseState`.
///
/// The state was two booleans, `hasAccepted` and `wasDismissed`, whose only consumer was a
/// `newState` that called `coordinator?.dismissTermsFlow()`. The view controller already called the
/// coordinator directly from its button handlers — with a comment saying the Redux subscription was
/// unreliable — so the subscription was redundant before this change. The booleans are gone.
///
/// Everything here is synchronous: `Prefs` and Glean, no I/O.
@MainActor
final class TermsOfUseViewModel {
    private let prefs: Prefs
    private let telemetry: TermsOfUseTelemetry

    init(profile: Profile = AppContainer.shared.resolve(),
         telemetry: TermsOfUseTelemetry = TermsOfUseTelemetry()) {
        self.prefs = profile.prefs
        self.telemetry = telemetry
    }

    // MARK: - Intents

    func termsShown() {
        recordImpression()
    }

    func termsAccepted() {
        let acceptedDate = Date()
        prefs.setBool(true, forKey: PrefsKeys.TermsOfUseAccepted)
        prefs.setTimestamp(acceptedDate.toTimestamp(), forKey: PrefsKeys.TermsOfUseAcceptedDate)
        telemetry.termsOfUseAcceptButtonTapped(surface: .bottomSheet, acceptedDate: acceptedDate)
    }

    func remindMeLaterTapped() {
        recordDismissal()
        prefs.setTimestamp(Date.now(), forKey: PrefsKeys.TermsOfUseRemindMeLaterTapDate)
        telemetry.termsOfUseRemindMeLaterButtonTapped()
    }

    func gestureDismiss() {
        recordDismissal()
        telemetry.termsOfUseDismissed()
    }

    func linkTapped(_ linkType: TermsOfUseLinkType) {
        switch linkType {
        // `.here` shares the learn-more URL and event, as `TermsOfUseLinkType.actionType` did.
        case .learnMore, .here:
            prefs.setTimestamp(Date.now(), forKey: PrefsKeys.TermsOfUseLearnMoreTapDate)
            telemetry.termsOfUseLearnMoreButtonTapped()
        case .privacyNotice:
            prefs.setTimestamp(Date.now(), forKey: PrefsKeys.TermsOfUsePrivacyNoticeTapDate)
            telemetry.termsOfUsePrivacyNoticeLinkTapped()
        case .termsOfUse:
            prefs.setTimestamp(Date.now(), forKey: PrefsKeys.TermsOfUseTermsLinkTapDate)
            telemetry.termsOfUseTermsOfUseLinkTapped()
        }
    }

    // MARK: - Private

    private func recordDismissal() {
        prefs.setBool(false, forKey: PrefsKeys.TermsOfUseShownRecorded)
        incrementRemindersCount()
        prefs.setTimestamp(Date.now(), forKey: PrefsKeys.TermsOfUseDismissedDate)
    }

    private func recordImpression() {
        let hasShownFirstTime = prefs.boolForKey(PrefsKeys.TermsOfUseFirstShown) ?? false
        guard hasShownFirstTime else {
            prefs.setBool(true, forKey: PrefsKeys.TermsOfUseFirstShown)
            prefs.setBool(true, forKey: PrefsKeys.TermsOfUseShownRecorded)
            telemetry.termsOfUseDisplayed()
            return
        }

        let hasBeenDismissedBefore = prefs.timestampForKey(PrefsKeys.TermsOfUseDismissedDate) != nil
        let hasSeenTermsOfUse = prefs.boolForKey(PrefsKeys.TermsOfUseShownRecorded) ?? false
        if hasBeenDismissedBefore, !hasSeenTermsOfUse {
            prefs.setBool(true, forKey: PrefsKeys.TermsOfUseShownRecorded)
            telemetry.termsOfUseDisplayed()
        }
    }

    private func incrementRemindersCount() {
        // Only increment for reminders - after the first dismissal
        let hasBeenDismissedBefore = prefs.timestampForKey(PrefsKeys.TermsOfUseDismissedDate) != nil
        guard hasBeenDismissedBefore else { return }

        let currentCount = prefs.intForKey(PrefsKeys.TermsOfUseRemindersCount) ?? 0
        prefs.setInt(Int32(currentCount + 1), forKey: PrefsKeys.TermsOfUseRemindersCount)
    }
}
