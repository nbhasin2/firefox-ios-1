// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Redux

import struct MozillaAppServices.Device
import struct Storage.ClientAndTabs

/// Defines actions sent to Redux for Sync tab in tab tray
struct RemoteTabsPanelAction: Action, Sendable {
    let windowUUID: WindowUUID
    let actionType: ActionType
    let url: URL?
    let targetDeviceId: String?

    init(clientAndTabs: [ClientAndTabs]? = nil,
         url: URL? = nil,
         targetDeviceId: String? = nil,
         windowUUID: WindowUUID,
         actionType: ActionType) {
        self.windowUUID = windowUUID
        self.actionType = actionType
        self.url = url
        self.targetDeviceId = targetDeviceId
    }
}

enum RemoteTabsPanelActionType: ActionType {
    case openSelectedURL
    case closeSelectedRemoteURL
    case flushTabCommands
}
