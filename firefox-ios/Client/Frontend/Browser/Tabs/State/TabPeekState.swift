// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import ModifiedCopy
import UIKit

@Copyable
struct TabPeekState {
    let windowUUID: WindowUUID
    let showAddToBookmarks: Bool
    let showRemoveBookmark: Bool
    let showSendToDevice: Bool
    let showCopyURL: Bool
    let showCloseTab: Bool
    let previewAccessibilityLabel: String
    let screenshot: UIImage

    init(windowUUID: WindowUUID) {
        self.windowUUID = windowUUID
        self.showAddToBookmarks = false
        self.showRemoveBookmark = false
        self.showSendToDevice = false
        self.showCopyURL = true
        self.showCloseTab = true
        self.previewAccessibilityLabel = ""
        self.screenshot = UIImage()
    }

    init(windowUUID: WindowUUID,
         showAddToBookmarks: Bool,
         showRemoveBookmark: Bool,
         showSendToDevice: Bool,
         showCopyURL: Bool,
         showCloseTab: Bool,
         previewAccessibilityLabel: String,
         screenshot: UIImage) {
        self.windowUUID = windowUUID
        self.showAddToBookmarks = showAddToBookmarks
        self.showRemoveBookmark = showRemoveBookmark
        self.showSendToDevice = showSendToDevice
        self.showCopyURL = showCopyURL
        self.showCloseTab = showCloseTab
        self.previewAccessibilityLabel = previewAccessibilityLabel
        self.screenshot = screenshot
    }
}
