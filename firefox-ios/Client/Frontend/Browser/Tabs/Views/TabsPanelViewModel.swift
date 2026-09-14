// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Foundation
import Redux

/// Replaces `TabsPanelState`'s reducer and the panel half of `TabManagerActionHandler`.
///
/// `TabsPanelState` stays a plain struct because the display view and its layout both take one;
/// only its Redux conformance goes.
@MainActor
final class TabsPanelViewModel {
    private(set) var state: TabsPanelState {
        didSet {
            guard state != oldValue else { return }
            onChange?(state)
        }
    }

    var onChange: ((TabsPanelState) -> Void)?

    private let panelType: TabTrayPanelType
    /// Exposed so the tab peek presented from a cell can close through the same service.
    let service: TabsPanelService

    private var isPrivate: Bool { return panelType == .privateTabs }

    private let windowUUID: WindowUUID
    /// The store holds observers weakly and sweeps dead ones, so there is nothing to unregister.
    private let bus: (any ActionObserving)?

    init(windowUUID: WindowUUID,
         panelType: TabTrayPanelType,
         service: TabsPanelService,
         bus: (any ActionObserving)? = browserEventBus,
         initialState: TabsPanelState? = nil) {
        self.windowUUID = windowUUID
        self.panelType = panelType
        self.service = service
        self.bus = bus
        self.state = initialState ?? TabsPanelState(windowUUID: windowUUID,
                                                    isPrivateMode: panelType == .privateTabs)
        service.addObserver(self) { [weak self] isPrivate in
            // Each panel only cares about its own mode.
            guard let self, isPrivate == self.isPrivate else { return }
            self.refreshTabs(isPrivate: isPrivate)
        }
        service.onPrivateTabsExhausted = { [weak self] in
            self?.didLoad()
        }
        observeScreenshots()
    }

    /// A screenshot landing is browser-level — the tab manager takes it, not the tray — so it
    /// arrives on the bus (D-016). The panel rebinds so the cell shows the new image.
    private func observeScreenshots() {
        bus?.addActionObserver(self) { [weak self] action in
            guard let self, action.windowUUID == self.windowUUID || action.windowUUID == .unavailable,
                  action is ScreenshotAction else { return }
            switch action.actionType {
            case ScreenshotActionType.screenshotTaken, ScreenshotActionType.screenshotRestored:
                self.refreshTabs(isPrivate: self.isPrivate)
            default:
                break
            }
        }
    }

    // MARK: - Lifecycle

    func didLoad() {
        apply(service.tabDisplayModel(isPrivate: isPrivate),
              scrollBehavior: .scrollToSelectedTab(shouldAnimate: false))
    }

    func willAppear() {
        apply(service.tabDisplayModel(isPrivate: isPrivate),
              scrollBehavior: .scrollToSelectedTab(shouldAnimate: false))
    }

    /// The tray switched panels; the tabs come from the panel being switched to.
    func didChangePanel(isPrivate: Bool) {
        let model = service.tabDisplayModel(isPrivate: isPrivate)
        state = state
            .copy(isPrivateMode: model.isPrivateMode)
            .copy(tabs: model.tabs)
            .copy(scrollState: nil)
    }

    func scrollToTab(_ behavior: TabScrollBehavior) {
        state = state.copy(
            scrollState: TabsPanelState.createTabScrollBehavior(forState: state, withScrollBehavior: behavior)
        )
    }

    // MARK: - Intents

    func addNewTab(with urlRequest: URLRequest?) {
        service.newTabButtonTapped(panelType: panelType)
        service.addNewTab(with: urlRequest, isPrivate: isPrivate, showOverlay: true)
    }

    func moveTab(_ moveTabData: MoveTabData) {
        service.moveTab(moveTabData)
    }

    func closeTab(_ tabUUID: TabUUID) {
        service.closeTab(tabUUID, isPrivate: isPrivate)
    }

    func cancelCloseAllTabs() {
        service.cancelCloseAllTabs(isPrivate: isPrivate)
    }

    func confirmCloseAllTabs() {
        service.closeAllTabs(isPrivate: state.isPrivateMode)
    }

    func deleteTabsOlderThan(_ period: TabsDeletionPeriod) {
        service.deleteNormalTabsOlderThan(period)
    }

    func selectTab(_ tabUUID: TabUUID, at index: Int?) {
        service.selectTab(tabUUID, panelType: panelType, selectedTabIndex: index)
    }

    func didTapLearnMoreAboutPrivate(with urlRequest: URLRequest) {
        service.didTapLearnMoreAboutPrivate(with: urlRequest)
    }

    func prefetchScreenshot(for tabUUID: TabUUID) {
        service.prefetchScreenshot(for: tabUUID)
    }

    // MARK: - Private

    private func refreshTabs(isPrivate: Bool) {
        state = state
            .copy(tabs: service.tabDisplayModel(isPrivate: isPrivate).tabs)
            .copy(scrollState: nil)
    }

    private func apply(_ model: TabDisplayModel, scrollBehavior: TabScrollBehavior) {
        let withTabs = state
            .copy(isPrivateMode: model.isPrivateMode)
            .copy(tabs: model.tabs)
        state = withTabs.copy(
            scrollState: TabsPanelState.createTabScrollBehavior(forState: withTabs,
                                                                withScrollBehavior: scrollBehavior)
        )
    }
}
