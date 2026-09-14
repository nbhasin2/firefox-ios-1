// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Foundation
import ModifiedCopy

enum TabTrayLayoutType: Equatable {
    case regular // iPad
    case compact // iPhone
}

@Copyable
struct TabTrayState: Equatable {
    var windowUUID: WindowUUID
    var isPrivateMode: Bool
    var selectedPanel: TabTrayPanelType
    var normalTabsCount: String
    var privateTabsCount: String
    var hasSyncableAccount: Bool
    var shouldDismiss: Bool
    var toastType: ToastType?
    var showCloseConfirmation: Bool
    var enableDeleteTabsButton: Bool?

    var navigationTitle: String {
        return selectedPanel.navTitle
    }

    var isSyncTabsPanel: Bool {
        return selectedPanel == .syncedTabs
    }

    var isNormalTabsPanel: Bool {
        return selectedPanel == .tabs
    }

    init(windowUUID: WindowUUID) {
        self.init(windowUUID: windowUUID,
                  isPrivateMode: false,
                  selectedPanel: .tabs,
                  normalTabsCount: "0",
                  privateTabsCount: "0",
                  hasSyncableAccount: false,
                  shouldDismiss: false,
                  toastType: nil,
                  showCloseConfirmation: false,
                  enableDeleteTabsButton: nil)
    }

    init(windowUUID: WindowUUID, panelType: TabTrayPanelType) {
        self.init(windowUUID: windowUUID,
                  isPrivateMode: panelType == .privateTabs,
                  selectedPanel: panelType,
                  normalTabsCount: "0",
                  privateTabsCount: "0",
                  hasSyncableAccount: false,
                  shouldDismiss: false,
                  toastType: nil,
                  showCloseConfirmation: false,
                  enableDeleteTabsButton: nil)
    }

    init(windowUUID: WindowUUID,
         isPrivateMode: Bool,
         selectedPanel: TabTrayPanelType,
         normalTabsCount: String,
         privateTabsCount: String,
         hasSyncableAccount: Bool,
         shouldDismiss: Bool,
         toastType: ToastType?,
         showCloseConfirmation: Bool,
         enableDeleteTabsButton: Bool?) {
        self.windowUUID = windowUUID
        self.isPrivateMode = isPrivateMode
        self.selectedPanel = selectedPanel
        self.normalTabsCount = normalTabsCount
        self.privateTabsCount = privateTabsCount
        self.hasSyncableAccount = hasSyncableAccount
        self.shouldDismiss = shouldDismiss
        self.toastType = toastType
        self.showCloseConfirmation = showCloseConfirmation
        self.enableDeleteTabsButton = enableDeleteTabsButton
    }
}
