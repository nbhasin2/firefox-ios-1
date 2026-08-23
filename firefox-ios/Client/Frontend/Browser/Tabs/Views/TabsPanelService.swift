// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Foundation
import Redux
import Shared

/// The tab-manager operations `TabManagerActionHandler` performed for the tab tray.
///
/// Every one of them was a command — add a tab, move one, close one, close them all, select one —
/// that the middleware ran against `TabManager` and then announced by dispatching a refresh. The
/// commands are methods here; the announcement is `onTabsChange`, and the two things that genuinely
/// leave the tab tray (dismissing it, showing the browser overlay) stay dispatches because the
/// homepage and the browser observe them.
@MainActor
final class TabsPanelService {
    private struct ObserverBox {
        weak var observer: AnyObject?
        let handler: (_ isPrivate: Bool) -> Void
    }

    /// Held weakly and swept before each delivery. One service per window, but three panels and
    /// the tray all watch it, so a single callback would not do.
    private var observers: [ObjectIdentifier: ObserverBox] = [:]

    /// Called when the last private tab goes, so the panel reloads from scratch.
    var onPrivateTabsExhausted: (() -> Void)?

    private let windowUUID: WindowUUID
    private let windowManager: WindowManager
    private let telemetry: TabsPanelTelemetry
    private let logger: Logger
    private let isTabTrayUIExperimentsEnabled: Bool

    init(windowUUID: WindowUUID,
         windowManager: WindowManager = AppContainer.shared.resolve(),
         telemetry: TabsPanelTelemetry? = nil,
         featureFlagsProvider: FeatureFlagProviding = AppContainer.shared.resolve(),
         logger: Logger = DefaultLogger.shared) {
        self.windowUUID = windowUUID
        self.windowManager = windowManager
        self.telemetry = telemetry ?? TabsPanelTelemetry(gleanWrapper: DefaultGleanWrapper(), logger: logger)
        self.logger = logger
        self.isTabTrayUIExperimentsEnabled = featureFlagsProvider.isEnabled(.tabTrayUIExperiments)
            && UIDevice.current.userInterfaceIdiom != .pad
    }

    // MARK: - Observing

    func addObserver(_ observer: AnyObject, handler: @escaping (_ isPrivate: Bool) -> Void) {
        observers[ObjectIdentifier(observer)] = ObserverBox(observer: observer, handler: handler)
    }

    func removeObserver(_ observer: AnyObject) {
        observers.removeValue(forKey: ObjectIdentifier(observer))
    }

    // MARK: - Reads

    func tabDisplayModel(isPrivate: Bool) -> TabDisplayModel {
        return TabDisplayModel(
            isPrivateMode: isPrivate,
            tabs: tabModels(isPrivate: isPrivate),
            normalTabsCount: normalTabsCount,
            privateTabsCount: privateTabsCount,
            enableDeleteTabsButton: hasTabs(isPrivate: isPrivate)
        )
    }

    func tabTrayModel(for panelType: TabTrayPanelType) -> TabTrayModel {
        let isPrivate = panelType == .privateTabs
        return TabTrayModel(isPrivateMode: isPrivate,
                            selectedPanel: panelType,
                            normalTabsCount: normalTabsCount,
                            privateTabsCount: privateTabsCount,
                            hasSyncableAccount: false,
                            enableDeleteTabsButton: hasTabs(isPrivate: isPrivate))
    }

    /// The panel the tray should open on when none was requested.
    var activePanelType: TabTrayPanelType {
        return (tabManager?.selectedTab?.isPrivate ?? false) ? .privateTabs : .tabs
    }

    // MARK: - Commands

    func addNewTab(with urlRequest: URLRequest?, isPrivate: Bool, showOverlay: Bool) {
        MainActor.assertIsolated("Expected to be called only on main actor.")
        // TODO: Legacy class has a guard to cancel adding new tab if dragging was enabled,
        // check if change is still needed
        guard let tabManager else { return }
        let tab = tabManager.addTab(urlRequest, isPrivate: isPrivate)
        tabManager.selectTab(tab)

        dismissTabTray()

        if !isTabTrayUIExperimentsEnabled {
            store.dispatch(
                GeneralBrowserAction(showOverlay: showOverlay,
                                     windowUUID: windowUUID,
                                     actionType: GeneralBrowserActionType.showOverlay)
            )
        }
    }

    func moveTab(_ moveTabData: MoveTabData) {
        TelemetryWrapper.recordEvent(category: .action, method: .drop, object: .tab, value: .tabTray)
        tabManager?.reorderTabs(isPrivate: moveTabData.isPrivate,
                                fromIndex: moveTabData.originIndex,
                                toIndex: moveTabData.destinationIndex)
        notifyTabsChanged(isPrivate: moveTabData.isPrivate)
    }

    /// Closing the last tab dismisses the tray, and exhausting the private tabs sends the panel
    /// back to a fresh load.
    func closeTab(_ tabUUID: TabUUID, isPrivate: Bool) {
        guard let tabManager else { return }
        telemetry.tabClosed(mode: isPrivate ? .private : .normal)

        // In non-private mode, if:
        //      A) the last normal active tab is closed, or
        //      B) the last of ALL normal tabs are closed (i.e. all tabs are inactive and closed at once),
        // then we want to close the tray.
        let wasLastTab = isPrivate ? tabManager.privateTabs.count == 1 : tabManager.normalTabs.count == 1
        tabManager.removeTab(tabUUID)
        notifyTabsChanged(isPrivate: isPrivate)

        if isPrivate && tabManager.privateTabs.isEmpty {
            onPrivateTabsExhausted?()
        } else if wasLastTab {
            dismissTabTray()
            addNewNormalTabIfSelectedIsPrivate()
        }
    }

    func closeAllTabs(isPrivate: Bool) {
        telemetry.closeAllTabsSheetOptionSelected(option: .all, mode: isPrivate ? .private : .normal)
        tabManager?.removeAllTabs(isPrivateMode: isPrivate)
        notifyTabsChanged(isPrivate: isPrivate)

        if !isPrivate {
            addNewNormalTabIfSelectedIsPrivate()
            dismissTabTray()
        }
    }

    func cancelCloseAllTabs(isPrivate: Bool) {
        telemetry.closeAllTabsSheetOptionSelected(option: .cancel, mode: isPrivate ? .private : .normal)
    }

    func deleteNormalTabsOlderThan(_ period: TabsDeletionPeriod) {
        telemetry.deleteNormalTabsSheetOptionSelected(period: period)
        tabManager?.removeNormalTabsOlderThan(period: period, currentDate: .now)
        // The tray stays open, so the panel needs refreshing.
        notifyTabsChanged(isPrivate: false)
    }

    func selectTab(_ tabUUID: TabUUID, panelType: TabTrayPanelType, selectedTabIndex: Int?) {
        guard let tab = tabManager?.getTabForUUID(uuid: tabUUID) else { return }
        tabManager?.selectTab(tab)
        telemetry.tabSelected(at: selectedTabIndex, mode: panelType.modeForTelemetry)
        dismissTabTray()
    }

    func didTapLearnMoreAboutPrivate(with urlRequest: URLRequest) {
        addNewTab(with: urlRequest, isPrivate: true, showOverlay: false)
    }

    /// Asks the tab manager to load the screenshot for an upcoming visible cell. The
    /// tab manager will no-op if the tab's screenshot is already in memory.
    func prefetchScreenshot(for tabUUID: TabUUID) {
        guard let tabManager, let tab = tabManager.getTabForUUID(uuid: tabUUID) else { return }
        tabManager.restoreScreenshot(for: tab)
    }

    func preserveTabs() {
        tabManager?.preserveTabs()
    }

    func changePanelTelemetry(_ panel: TabTrayPanelType) {
        telemetry.tabModeSelected(mode: panel.modeForTelemetry)
    }

    func doneButtonTapped(panelType: TabTrayPanelType?) {
        telemetry.doneButtonTapped(mode: panelType?.modeForTelemetry ?? .normal)
    }

    func newTabButtonTapped(panelType: TabTrayPanelType?) {
        telemetry.newTabButtonTapped(mode: panelType?.modeForTelemetry ?? .normal)
    }

    // MARK: - Private

    private func notifyTabsChanged(isPrivate: Bool) {
        observers = observers.filter { $0.value.observer != nil }
        observers.values.forEach { $0.handler(isPrivate) }
    }

    private var tabManager: TabManager? {
        guard windowUUID != .unavailable, let tabManager = windowManager.tabManager(for: windowUUID) else {
            assertionFailure()
            logger.log("Unexpected or unavailable window UUID for requested TabManager.", level: .fatal, category: .tabs)
            return nil
        }
        return tabManager
    }

    private var normalTabsCount: String {
        return tabManager?.normalTabs.count.description ?? ""
    }

    private var privateTabsCount: String {
        return tabManager?.privateTabs.count.description ?? ""
    }

    private func hasTabs(isPrivate: Bool) -> Bool {
        guard let tabManager else { return false }
        return (isPrivate ? tabManager.privateTabs.count : tabManager.normalTabs.count) > 0
    }

    private func tabModels(isPrivate: Bool) -> [TabModel] {
        guard let tabManager else { return [] }
        let selectedTab = tabManager.selectedTab
        let tabs = isPrivate ? tabManager.privateTabs : tabManager.normalTabs
        return tabs.map { tab in
            TabModel(tabUUID: tab.tabUUID,
                     isSelected: tab.tabUUID == selectedTab?.tabUUID,
                     isPrivate: tab.isPrivate,
                     isFxHomeTab: tab.isFxHomeTab,
                     tabTitle: tab.displayTitle,
                     url: tab.url,
                     screenshot: tab.screenshot,
                     hasHomeScreenshot: tab.hasHomeScreenshot,
                     hasScreenshotOnDisk: tab.screenshotUUID != nil)
        }
    }

    /// Adds a new non-private tab if the currently selected tab is private.
    /// Used to ensure a normal tab exists when exiting or exhausting private tabs.
    private func addNewNormalTabIfSelectedIsPrivate() {
        if let selectedTab = tabManager?.selectedTab, selectedTab.isPrivate {
            tabManager?.addTab(nil, isPrivate: false)
        }
    }

    /// Browser-level: the homepage observes this on the bus to refresh jump back in, and the tray
    /// itself listens for it to dismiss.
    private func dismissTabTray() {
        store.dispatch(
            TabTrayAction(windowUUID: windowUUID, actionType: TabTrayActionType.dismissTabTray)
        )
    }
}
