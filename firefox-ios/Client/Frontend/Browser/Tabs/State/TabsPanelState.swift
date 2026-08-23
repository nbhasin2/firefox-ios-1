// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Foundation
import ModifiedCopy

@Copyable
struct TabsPanelState: Equatable {
    struct ScrollState: Equatable {
        let toIndex: Int
        let withAnimation: Bool
    }

    var windowUUID: WindowUUID
    var isPrivateMode: Bool
    var tabs: [TabModel]
    var scrollState: ScrollState?
    var didTapAddTab: Bool
    var urlRequest: URLRequest?

    var isPrivateTabsEmpty: Bool {
        guard isPrivateMode else { return true }
        return tabs.isEmpty
    }

    init(windowUUID: WindowUUID, isPrivateMode: Bool = false) {
        self.init(
            windowUUID: windowUUID,
            isPrivateMode: isPrivateMode,
            tabs: [TabModel](),
            toastType: nil,
            scrollState: nil,
            didTapAddTab: false,
            urlRequest: nil)
    }

    init(windowUUID: WindowUUID,
         isPrivateMode: Bool,
         tabs: [TabModel],
         toastType: ToastType? = nil,
         scrollState: ScrollState?,
         didTapAddTab: Bool,
         urlRequest: URLRequest?) {
        self.isPrivateMode = isPrivateMode
        self.tabs = tabs
        self.windowUUID = windowUUID
        self.scrollState = scrollState
        self.didTapAddTab = didTapAddTab
        self.urlRequest = urlRequest
    }

    static func createTabScrollBehavior(
        forState state: TabsPanelState,
        withScrollBehavior scrollBehavior: TabScrollBehavior
    ) -> TabsPanelState.ScrollState? {
        guard !state.tabs.isEmpty else { return nil }

        if case .scrollToSelectedTab(let shouldAnimate) = scrollBehavior {
            if let selectedTabIndex = state.tabs.firstIndex(where: { $0.isSelected }) {
                return ScrollState(toIndex: selectedTabIndex, withAnimation: shouldAnimate)
            } else if !state.tabs.isEmpty {
                // If the user switches between the normal and private tab panels, there's a chance this subset of tabs does
                // not contain a selected tab. In that case, we should scroll to the bottom of the panel.
                // Note: Could optimize further by scrolling to the most recent tab if we had `lastExecutedTime` in our model
                return ScrollState(toIndex: state.tabs.count - 1, withAnimation: shouldAnimate)
            }
        } else if case .scrollToTab(let tabUUID, let shouldAnimate) = scrollBehavior {
            if let tabIndex = state.tabs.firstIndex(where: { $0.tabUUID == tabUUID }) {
                return ScrollState(toIndex: tabIndex, withAnimation: shouldAnimate)
            } else {
                // This can happen if the user closes a tab, switches to a different tab panel, and then taps "undo"
                return nil
            }
        }

        // This can happen if the user changes tab panels and one of the panels is empty (nothing to scroll to)
        return nil
    }
}
