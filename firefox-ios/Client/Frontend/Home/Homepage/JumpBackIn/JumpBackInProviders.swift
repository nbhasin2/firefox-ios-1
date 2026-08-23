// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Foundation
import Storage

/// The homepage's two reads out of the tab layer, extracted from `TabManagerActionHandler` and
/// `RemoteTabsPanelMiddleware`.
///
/// Both middlewares did the same thing for jump back in: read something cheap and dispatch it for
/// `JumpBackInSectionState` to reduce. Neither read needed the store, and neither middleware
/// otherwise had anything to do with the homepage — `TabManagerActionHandler` even carried a
/// "FXIOS-11740 this should go to the homepage middleware" note on its half. The section's view
/// model calls these instead, which is what lets it migrate before Tabs does.
@MainActor
protocol RecentTabsProviding {
    func recentTabs(for windowUUID: WindowUUID) -> [Tab]
}

@MainActor
protocol SyncedTabProviding {
    func mostRecentSyncedTab() async -> RemoteTabConfiguration?
}

@MainActor
final class DefaultRecentTabsProvider: RecentTabsProviding {
    private let windowManager: WindowManager

    init(windowManager: WindowManager = AppContainer.shared.resolve()) {
        self.windowManager = windowManager
    }

    func recentTabs(for windowUUID: WindowUUID) -> [Tab] {
        return windowManager.tabManager(for: windowUUID)?.recentlyAccessedNormalTabs ?? []
    }
}

@MainActor
final class DefaultSyncedTabProvider: SyncedTabProviding {
    private let profile: Profile

    init(profile: Profile = AppContainer.shared.resolve()) {
        self.profile = profile
    }

    func mostRecentSyncedTab() async -> RemoteTabConfiguration? {
        let clientsAndTabs = await withCheckedContinuation { continuation in
            profile.getCachedClientsAndTabs { result in
                continuation.resume(returning: result)
            }
        }
        return Self.mostRecentDesktopTab(from: clientsAndTabs)
    }

    /// Retrieves the most recently used tab from a list of desktop clients tabs.
    static func mostRecentDesktopTab(from clientAndTabs: [ClientAndTabs]?) -> RemoteTabConfiguration? {
        let mostRecentTabsPerClient = clientAndTabs?
            .filter { !$0.tabs.isEmpty && ClientType.fromFxAType($0.client.type) == .Desktop }
            .compactMap { client in
                client.tabs
                    .max(by: { $0.lastUsed < $1.lastUsed })
                    .map { RemoteTabConfiguration(client: client.client, tab: $0) }
            }

        return mostRecentTabsPerClient?.max(by: { $0.tab.lastUsed < $1.tab.lastUsed })
    }
}
