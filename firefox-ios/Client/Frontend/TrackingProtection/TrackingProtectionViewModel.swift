// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Foundation
import Redux

@MainActor
protocol TrackingProtectionViewModelDelegate: AnyObject {
    func trackingProtectionViewModelDidRequestBlockedTrackers()
    func trackingProtectionViewModelDidRequestProtectionDetails()
    func trackingProtectionViewModelDidRequestClearCookiesAlert()
    func trackingProtectionViewModelDidRequestSettings()
    func trackingProtectionViewModelDidRequestDismiss()
    func trackingProtectionViewModelDidUpdateBlockedTrackers()
    func trackingProtectionViewModelDidUpdateConnectionStatus()
}

/// Replaces `TrackingProtectionMiddleware` and `TrackingProtectionState`.
///
/// The Redux layer here was a navigation command bus: a tap dispatched an action, the middleware
/// re-dispatched it with telemetry, the reducer stored a `navigateTo`/`displayView` flag, and
/// `newState` immediately turned that flag back into a push, pop, or present. The flags carried no
/// information the caller did not already have, so they are delegate calls now.
///
/// The two refresh signals that arrive from outside the module — from `TabContentBlocker` and
/// `BrowserViewController` — were the only genuinely stateful part. Unlike the navigation intents
/// they have no caller holding a reference to this screen, and they are browser-level events, so
/// they stay on the bus (D-017).
@MainActor
final class TrackingProtectionViewModel {
    weak var delegate: TrackingProtectionViewModelDelegate?

    private let windowUUID: WindowUUID
    private let telemetry: TrackingProtectionTelemetry
    /// The bus holds observers weakly and sweeps dead ones, so there is nothing to unregister.
    private let bus: (any ActionObserving)?

    init(windowUUID: WindowUUID,
         telemetry: TrackingProtectionTelemetry = TrackingProtectionTelemetry(),
         bus: (any ActionObserving)? = browserEventBus) {
        self.windowUUID = windowUUID
        self.telemetry = telemetry
        self.bus = bus
        observeRefreshSignals()
    }

    // MARK: - Intents

    func tappedShowBlockedTrackers() {
        telemetry.showBlockedTrackersDetails()
        delegate?.trackingProtectionViewModelDidRequestBlockedTrackers()
    }

    func tappedShowTrackingProtectionDetails() {
        telemetry.showTrackingProtectionDetails()
        delegate?.trackingProtectionViewModelDidRequestProtectionDetails()
    }

    func tappedShowClearCookiesAlert() {
        telemetry.showClearCookiesAlert()
        delegate?.trackingProtectionViewModelDidRequestClearCookiesAlert()
    }

    func tappedShowSettings() {
        telemetry.tappedShowSettings()
        delegate?.trackingProtectionViewModelDidRequestSettings()
    }

    /// Called once the user confirms the clear-cookies alert, which closes the screen behind it.
    func didClearCookiesAndSiteData() {
        telemetry.clearCookiesAndSiteData()
        delegate?.trackingProtectionViewModelDidRequestDismiss()
    }

    // MARK: - Refresh signals

    private func observeRefreshSignals() {
        bus?.addActionObserver(self) { [weak self] action in
            guard let self, action.windowUUID == self.windowUUID else { return }
            switch action.actionType {
            case GeneralBrowserActionType.blockedTrackersDidChange:
                self.delegate?.trackingProtectionViewModelDidUpdateBlockedTrackers()
            case GeneralBrowserActionType.connectionStatusDidChange:
                self.delegate?.trackingProtectionViewModelDidUpdateConnectionStatus()
            default:
                break
            }
        }
    }
}
