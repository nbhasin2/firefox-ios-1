// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Foundation
import Redux
import Shared

import struct MozillaAppServices.Device
import struct Storage.ClientAndTabs

/// Replaces `RemoteTabsPanelState`'s reducer and `RemoteTabsPanelMiddleware`.
///
/// `RemoteTabsPanelState` stays a plain struct because the panel and its table controller both
/// take one; only its Redux conformance goes.
///
/// The middleware was a sync-state machine written as five actions round-tripping through the
/// store — begin, succeed, fail, sync-began, devices-changed. All five were announcements this
/// screen made to itself, so they are state transitions on the view model. What still dispatches
/// is what leaves the screen: `TabTrayActionType.firefoxAccountChanged`, and the three commands
/// `TabManagerMiddleware` performs (open, close, flush).
@MainActor
final class RemoteTabsPanelViewModel: Notifiable {
    private(set) var state: RemoteTabsPanelState {
        didSet { onChange?(state) }
    }

    var onChange: ((RemoteTabsPanelState) -> Void)?

    private let windowUUID: WindowUUID
    private let profile: Profile
    let notificationCenter: NotificationProtocol

    var hasSyncableAccount: Bool {
        return profile.hasSyncableAccount()
    }

    init(windowUUID: WindowUUID,
         profile: Profile = AppContainer.shared.resolve(),
         notificationCenter: NotificationProtocol = NotificationCenter.default,
         initialState: RemoteTabsPanelState? = nil) {
        self.windowUUID = windowUUID
        self.profile = profile
        self.notificationCenter = notificationCenter
        self.state = initialState ?? RemoteTabsPanelState(windowUUID: windowUUID)
        startObservingNotifications(
            withNotificationCenter: notificationCenter,
            forObserver: self,
            observing: [.FirefoxAccountChanged, .ProfileDidFinishSyncing, .constellationStateUpdate]
        )
    }

    nonisolated func handleNotifications(_ notification: Notification) {
        let name = notification.name
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch name {
            case .FirefoxAccountChanged, .ProfileDidFinishSyncing:
                self.announceAccountChange()
            case .constellationStateUpdate:
                self.remoteDevicesChanged()
            default: break
            }
        }
    }

    // MARK: - Intents

    func panelDidAppear() {
        refresh()
        announceAccountChange()
    }

    func refresh(useCache: Bool = false) {
        // Ensure we do not already have a refresh in progress
        guard state.refreshState != .refreshing else { return }

        guard hasSyncableAccount else {
            refreshDidFail(reason: .notLoggedIn)
            return
        }
        guard profile.prefs.boolForKey(PrefsKeys.TabSyncEnabled) == true else {
            refreshDidFail(reason: .syncDisabledByUser)
            return
        }

        // Pull-to-refresh shouldn't trigger a new update while one is running.
        state = state.copy(refreshState: .refreshing)
        fetchTabsAndDevices(useCache: useCache)
    }

    func syncDidBegin() {
        guard state.refreshState == .idle else { return }
        state = state
            .copy(refreshState: .syncingTabs)
            .copy(allowsRefresh: false)
    }

    // MARK: - Private

    private func fetchTabsAndDevices(useCache: Bool) {
        let completion: @Sendable ([ClientAndTabs]?) -> Void = { result in
            ensureMainThread {
                MainActor.assumeIsolated { [weak self] in
                    guard let self else { return }
                    guard let clientAndTabs = result else {
                        self.refreshDidFail(reason: .failedToSync)
                        return
                    }
                    self.refreshDidSucceed(clientAndTabs: clientAndTabs, devices: self.refreshedDevices())
                }
            }
        }

        if useCache {
            profile.getCachedClientsAndTabs(completion: completion)
        } else {
            profile.getClientsAndTabs(completion: completion)
        }
    }

    private func refreshedDevices() -> [Device]? {
        guard let constellation = profile.rustFxA.accountManager?.deviceConstellation() else { return nil }
        constellation.refreshState()
        return constellation.state()?.remoteDevices
    }

    private func refreshDidSucceed(clientAndTabs: [ClientAndTabs], devices: [Device]?) {
        state = state
            .copy(refreshState: .idle)
            .copy(allowsRefresh: true)
            .copy(clientAndTabs: clientAndTabs)
            .copy(showingEmptyState: nil)
            .copy(devices: devices ?? state.devices)
    }

    private func refreshDidFail(reason: RemoteTabsPanelEmptyStateReason) {
        state = state
            .copy(refreshState: .idle)
            .copy(allowsRefresh: reason.allowsRefresh)
            .copy(showingEmptyState: reason)
    }

    private func remoteDevicesChanged() {
        guard let devices = refreshedDevices() else { return }
        state = state
            .copy(refreshState: .idle)
            .copy(devices: devices)
    }

    /// Leaves the screen: `TabTrayState` reduces this and the tab tray has not migrated.
    private func announceAccountChange() {
        store.dispatch(
            TabTrayAction(hasSyncableAccount: hasSyncableAccount,
                          windowUUID: windowUUID,
                          actionType: TabTrayActionType.firefoxAccountChanged)
        )
    }
}
