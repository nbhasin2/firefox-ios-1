// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Foundation
import Redux

/// Replaces `TabTrayState`'s reducer and the tray half of `TabManagerActionHandler`.
///
/// The tray's own counters come from `TabsPanelService`. Two things reach it from elsewhere and
/// come off the bus (D-016): the synced-tabs panel announcing the account state, and anything in
/// the app asking the tray to dismiss — closing the last tab, selecting a tab, opening a new one.
@MainActor
final class TabTrayViewModel {
    private(set) var state: TabTrayState {
        didSet {
            guard state != oldValue else { return }
            onChange?(state)
        }
    }

    var onChange: ((TabTrayState) -> Void)?
    /// Fired when something asked the tray to close.
    var onDismiss: (() -> Void)?

    private let windowUUID: WindowUUID
    private let service: TabsPanelService
    /// The store holds observers weakly and sweeps dead ones, so there is nothing to unregister.
    private let bus: (any ActionObserving)?

    init(windowUUID: WindowUUID,
         service: TabsPanelService,
         bus: (any ActionObserving)? = store,
         initialState: TabTrayState? = nil) {
        self.windowUUID = windowUUID
        self.service = service
        self.bus = bus
        self.state = initialState ?? TabTrayState(windowUUID: windowUUID, panelType: .tabs)
        service.addObserver(self) { [weak self] isPrivate in
            self?.refreshCounts(isPrivate: isPrivate)
        }
        observeBus()
    }

    // MARK: - Lifecycle

    func didLoad(panelType: TabTrayPanelType?) {
        // If no panelType is provided then fallback to whichever tab is currently selected
        let panelType = panelType ?? service.activePanelType
        apply(service.tabTrayModel(for: panelType))
    }

    // MARK: - Intents

    func changePanel(_ panelType: TabTrayPanelType) {
        service.changePanelTelemetry(panelType)
        state = state
            .copy(isPrivateMode: panelType == .privateTabs)
            .copy(selectedPanel: panelType)
        guard panelType != .syncedTabs else { return }
        refreshCounts(isPrivate: panelType == .privateTabs)
    }

    func closePrivateTabsSettingToggled() {
        service.preserveTabs()
    }

    func doneButtonTapped() {
        service.doneButtonTapped(panelType: state.selectedPanel)
    }

    /// Transient: the confirmation sheet is presented by the view controller, not held in state.
    var onShowCloseConfirmation: (() -> Void)?

    func closeAllTabsTapped() {
        onShowCloseConfirmation?()
    }

    /// The tabs list changed underneath the tray, so its counters need recomputing.
    func refreshCounts(isPrivate: Bool) {
        let model = service.tabDisplayModel(isPrivate: isPrivate)
        state = state
            .copy(normalTabsCount: isPrivate ? state.normalTabsCount : model.normalTabsCount)
            .copy(privateTabsCount: model.privateTabsCount)
            .copy(enableDeleteTabsButton: model.enableDeleteTabsButton)
    }

    // MARK: - Private

    private func observeBus() {
        bus?.addActionObserver(self) { [weak self] action in
            guard let self, action.windowUUID == self.windowUUID || action.windowUUID == .unavailable else { return }
            switch action.actionType {
            case TabTrayActionType.dismissTabTray:
                self.onDismiss?()
            case TabTrayActionType.firefoxAccountChanged:
                guard let hasSyncableAccount = (action as? TabTrayAction)?.hasSyncableAccount else { return }
                self.state = self.state.copy(hasSyncableAccount: hasSyncableAccount)
            default:
                break
            }
        }
    }

    private func apply(_ model: TabTrayModel) {
        state = state
            .copy(isPrivateMode: model.isPrivateMode)
            .copy(selectedPanel: model.selectedPanel)
            .copy(normalTabsCount: model.normalTabsCount)
            .copy(privateTabsCount: model.privateTabsCount)
            .copy(hasSyncableAccount: model.hasSyncableAccount)
            .copy(enableDeleteTabsButton: model.enableDeleteTabsButton)
    }
}
