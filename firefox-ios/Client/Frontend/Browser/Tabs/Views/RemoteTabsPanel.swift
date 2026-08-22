// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import UIKit
import Common
import Redux

import enum MozillaAppServices.VisitType

protocol RemoteTabsPanelDelegate: AnyObject {
    @MainActor
    func presentFirefoxAccountSignIn()

    @MainActor
    func presentFxAccountSettings()
}

protocol RemoteTabsClientAndTabsDataSourceDelegate: AnyObject {
    @MainActor
    func remoteTabsClientAndTabsDataSourceDidSelectURL(_ url: URL, visitType: VisitType)
}

final class RemoteTabsPanel: UIViewController,
                       Themeable,
                       RemoteTabsClientAndTabsDataSourceDelegate,
                       RemoteTabsEmptyViewDelegate,
                       FeatureFlaggable,
                       TabTrayThemeable,
                       Notifiable {
    // MARK: - Properties

    private let viewModel: RemoteTabsPanelViewModel
    private(set) var state: RemoteTabsPanelState
    var tabsDisplayViewController: RemoteTabsViewController
    weak var remoteTabsDelegate: RemoteTabsPanelDelegate?

    var themeManager: ThemeManager
    var themeListenerCancellable: Any?
    var notificationCenter: NotificationProtocol
    private let windowUUID: WindowUUID
    private var isTabTrayUIExperimentsEnabled: Bool {
        return featureFlagsProvider.isEnabled(.tabTrayUIExperiments)
        && UIDevice.current.userInterfaceIdiom != .pad
    }

    private lazy var statusBarBackground: UIView = .build()

    // MARK: - Initializer

    init(windowUUID: WindowUUID,
         themeManager: ThemeManager = AppContainer.shared.resolve(),
         notificationCenter: NotificationProtocol = NotificationCenter.default,
         viewModel: RemoteTabsPanelViewModel? = nil
    ) {
        self.windowUUID = windowUUID
        let viewModel = viewModel ?? RemoteTabsPanelViewModel(windowUUID: windowUUID)
        self.viewModel = viewModel
        self.state = viewModel.state
        self.themeManager = themeManager
        self.notificationCenter = notificationCenter
        self.tabsDisplayViewController = RemoteTabsViewController(state: viewModel.state, windowUUID: windowUUID)

        super.init(nibName: nil, bundle: nil)

        self.tabsDisplayViewController.remoteTabsPanel = self

        self.viewModel.onChange = { [weak self] state in
            self?.applyState(state)
        }

        startObservingNotifications(
            withNotificationCenter: notificationCenter,
            forObserver: self,
            observing: [
                .ProfileDidStartSyncing,
                .ProfileDidFinishSyncing
            ]
        )
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var currentWindowUUID: UUID? { return windowUUID }

    // MARK: - Actions

    func tableViewControllerDidPullToRefresh() {
        refreshTabs()
    }

    /// The tab tray's sync button; it holds this panel as a child.
    func syncTabsTapped() {
        refreshTabs()
    }

    // MARK: - Internal Utilities

    private func refreshTabs(useCache: Bool = false) {
        viewModel.refresh(useCache: useCache)
    }

    // MARK: - View & Layout

    override func viewDidLoad() {
        super.viewDidLoad()

        setupLayout()
        viewModel.panelDidAppear()

        listenForThemeChanges(withNotificationCenter: notificationCenter)
        applyTheme()
    }

    private func setupLayout() {
        navigationController?.setNavigationBarHidden(true, animated: false)
        tabsDisplayViewController.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(tabsDisplayViewController)
        view.addSubview(tabsDisplayViewController.view)
        tabsDisplayViewController.didMove(toParent: self)

        if isTabTrayUIExperimentsEnabled {
            view.addSubview(statusBarBackground)

            NSLayoutConstraint.activate([
                tabsDisplayViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                tabsDisplayViewController.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                tabsDisplayViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                tabsDisplayViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),

                statusBarBackground.topAnchor.constraint(equalTo: view.topAnchor),
                statusBarBackground.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                statusBarBackground.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                statusBarBackground.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)
            ])
        } else {
            NSLayoutConstraint.activate([
                tabsDisplayViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                tabsDisplayViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
                tabsDisplayViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                tabsDisplayViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
        }
    }

    // MARK: - Themeable

    func applyTheme() {
        let theme = retrieveTheme()
        view.backgroundColor = theme.isNova ? theme.colors.layer1 : theme.colors.layer4
        tabsDisplayViewController.tableView.backgroundColor = theme.isNova ? theme.colors.layer1 : theme.colors.layer3
        tabsDisplayViewController.tableView.separatorColor = theme.colors.borderPrimary
        statusBarBackground.backgroundColor = theme.isNova ? theme.colors.layer1 : theme.colors.layer3
    }

    var shouldUsePrivateOverride: Bool {
        return true
    }

    var shouldBeInPrivateTheme: Bool {
        return false
    }

    // MARK: - TabTrayThemeable

    func retrieveTheme() -> Theme {
        if shouldUsePrivateOverride {
            return themeManager.resolvedTheme(with: false)
        } else {
            return themeManager.getCurrentTheme(for: windowUUID)
        }
    }

    func applyTheme(_ theme: Theme) {
        view.backgroundColor = theme.isNova ? theme.colors.layer1 : theme.colors.layer4
        tabsDisplayViewController.tableView.backgroundColor = theme.isNova ? theme.colors.layer1 : theme.colors.layer3
        tabsDisplayViewController.tableView.separatorColor = theme.colors.borderPrimary
        statusBarBackground.backgroundColor = theme.isNova ? theme.colors.layer1 : theme.colors.layer3
    }

    private func applyState(_ state: RemoteTabsPanelState) {
        self.state = state
        tabsDisplayViewController.newState(state: state)
    }

    // MARK: - RemoteTabsClientAndTabsDataSourceDelegate
    func remoteTabsClientAndTabsDataSourceDidSelectURL(_ url: URL, visitType: VisitType) {
        handleOpenSelectedURL(url)
    }

    func remoteTabsClientAndTabsDataSourceDidCloseURL(deviceId: String, url: URL) {
        handleCloseRemoteTab(deviceId, url: url)
    }

    func remoteTabsClientAndTabsDataSourceDidTabCommandsFlush(deviceId: String) {
        handleTabCommandsFlush(deviceId)
    }

    // MARK: - RemotePanelDelegate
    func remotePanelDidRequestToSignIn() {
        remoteTabsDelegate?.presentFirefoxAccountSignIn()
    }

    func presentFxAccountSettings() {
        remoteTabsDelegate?.presentFxAccountSettings()
    }

    func remotePanelDidRequestToOpenInNewTab(_ url: URL, isPrivate: Bool) {
        handleOpenSelectedURL(url)
    }

    private func handleOpenSelectedURL(_ url: URL) {
        let action = RemoteTabsPanelAction(url: url,
                                           windowUUID: windowUUID,
                                           actionType: RemoteTabsPanelActionType.openSelectedURL)
        store.dispatch(action)
    }

    private func handleCloseRemoteTab(_ deviceId: String, url: URL) {
        let action = RemoteTabsPanelAction(url: url,
                                           targetDeviceId: deviceId,
                                           windowUUID: windowUUID,
                                           actionType: RemoteTabsPanelActionType.closeSelectedRemoteURL)
        store.dispatch(action)
        // Once we add the tab to the command queue, the rust tab store will start removing it from
        // the list, so refresh the tabs
        refreshTabs(useCache: true)
    }

    private func handleTabCommandsFlush(_ deviceId: String) {
        let action = RemoteTabsPanelAction(targetDeviceId: deviceId,
                                           windowUUID: windowUUID,
                                           actionType: RemoteTabsPanelActionType.flushTabCommands)
        store.dispatch(action)

        refreshTabs(useCache: true)
    }

    // MARK: - Notifiable
    func handleNotifications(_ notification: Notification) {
        switch notification.name {
        case .ProfileDidStartSyncing:
            ensureMainThread {
                self.viewModel.syncDidBegin()
            }
        case .ProfileDidFinishSyncing:
            ensureMainThread {
                self.refreshTabs(useCache: true)
            }
        default: return
        }
    }
}
