// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Foundation

/// Replaces `WallpaperState`'s reducer and `WallpaperMiddleware`.
///
/// `WallpaperState` stays a plain struct because `WallpaperBackgroundView` takes one; only its
/// Redux conformance goes.
///
/// The wallpaper picker lives in Settings and has no ownership path to the homepage, but it does
/// not need a new notification either: `WallpaperManager.setCurrentWallpaper` already posts
/// `.WallpaperDidChange`, so this observes that and re-reads the manager. That is one hop shorter
/// than the middleware, which listened for a dispatched action the picker sent *in addition to*
/// the notification it was already posting.
@MainActor
final class WallpaperViewModel: Notifiable {
    private(set) var state: WallpaperState {
        didSet {
            guard state != oldValue else { return }
            onChange?(state, oldValue)
        }
    }

    /// Carries the previous value because the view controller animates the snapshot differently
    /// when only the available height changed.
    var onChange: ((_ state: WallpaperState, _ previous: WallpaperState) -> Void)?

    private let wallpaperManager: WallpaperManagerInterface
    let notificationCenter: NotificationProtocol

    init(wallpaperManager: WallpaperManagerInterface = WallpaperManager(),
         notificationCenter: NotificationProtocol = NotificationCenter.default,
         initialState: WallpaperState? = nil) {
        self.wallpaperManager = wallpaperManager
        self.notificationCenter = notificationCenter
        self.state = initialState ?? WallpaperState(
            wallpaperConfiguration: WallpaperConfiguration(wallpaper: wallpaperManager.currentWallpaper)
        )
        startObservingNotifications(
            withNotificationCenter: notificationCenter,
            forObserver: self,
            observing: [.WallpaperDidChange]
        )
    }

    nonisolated func handleNotifications(_ notification: Notification) {
        guard notification.name == .WallpaperDidChange else { return }
        Task { @MainActor [weak self] in
            self?.refreshConfiguration()
        }
    }

    // MARK: - Intents

    func refreshConfiguration() {
        state = state.copy(
            wallpaperConfiguration: WallpaperConfiguration(wallpaper: wallpaperManager.currentWallpaper)
        )
    }

    /// `BrowserViewController` owns the geometry these describe; see `WallpaperState`.
    func updateAvailableHeights(content: CGFloat, wallpaper: CGFloat) {
        state = state
            .copy(availableContentHeight: content)
            .copy(availableWallpaperHeight: wallpaper)
    }
}
