// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Foundation

extension Notification.Name {
    /// The blocked-tracker count for a window changed. Posted by `TabContentBlocker`, replacing
    /// `TrackingProtectionActionType.updateBlockedTrackerStats`.
    public static let trackingProtectionBlockedTrackersDidChange =
        Notification.Name("trackingProtectionBlockedTrackersDidChange")
    /// A page's secure-content status changed. Posted by `BrowserViewController`, replacing
    /// `TrackingProtectionActionType.updateConnectionStatus`.
    public static let trackingProtectionConnectionStatusDidChange =
        Notification.Name("trackingProtectionConnectionStatusDidChange")
}

enum TrackingProtectionNotification {
    /// `WindowUUID` of the window whose tracking protection changed.
    static let windowUUIDKey = "windowUUID"

    @MainActor
    static func post(_ name: Notification.Name,
                     windowUUID: WindowUUID,
                     notificationCenter: NotificationProtocol = NotificationCenter.default) {
        notificationCenter.post(name: name, withObject: nil, withUserInfo: [windowUUIDKey: windowUUID])
    }
}

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
/// `BrowserViewController` — were the only genuinely stateful part. They become notifications,
/// because unlike the navigation intents they have no caller holding a reference to this screen.
@MainActor
final class TrackingProtectionViewModel: Notifiable {
    weak var delegate: TrackingProtectionViewModelDelegate?

    private let windowUUID: WindowUUID
    private let telemetry: TrackingProtectionTelemetry
    private let notificationCenter: NotificationProtocol

    init(windowUUID: WindowUUID,
         telemetry: TrackingProtectionTelemetry = TrackingProtectionTelemetry(),
         notificationCenter: NotificationProtocol = NotificationCenter.default) {
        self.windowUUID = windowUUID
        self.telemetry = telemetry
        self.notificationCenter = notificationCenter
        startObservingNotifications(
            withNotificationCenter: notificationCenter,
            forObserver: self,
            observing: [.trackingProtectionBlockedTrackersDidChange,
                        .trackingProtectionConnectionStatusDidChange]
        )
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

    /// `@objc` notification handlers cannot be actor-isolated, so hop back to the main actor before
    /// touching the delegate.
    nonisolated func handleNotifications(_ notification: Notification) {
        let name = notification.name
        let uuid = notification.userInfo?[TrackingProtectionNotification.windowUUIDKey] as? WindowUUID
        Task { @MainActor [weak self] in
            guard let self, uuid == self.windowUUID else { return }
            switch name {
            case .trackingProtectionBlockedTrackersDidChange:
                self.delegate?.trackingProtectionViewModelDidUpdateBlockedTrackers()
            case .trackingProtectionConnectionStatusDidChange:
                self.delegate?.trackingProtectionViewModelDidUpdateConnectionStatus()
            default:
                break
            }
        }
    }
}
