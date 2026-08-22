// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Shared
import UIKit

// MARK: - Coordinator Delegate

@MainActor
protocol TranslationPickerSettingsDelegate: AnyObject {
    func showLanguagePicker(availableLanguages: [String], onSelect: @escaping @MainActor (String) -> Void)
}

// MARK: - ViewController

final class TranslationPickerSettingsViewController: UIViewController,
                                               Themeable,
                                               UICollectionViewDelegate {

    private lazy var collectionView: UICollectionView = {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        return collectionView
    }()

    private lazy var dataSource: TranslationSettingsDiffableDataSource = makeDataSource()

    // MARK: - Navigation bar items

    private lazy var editButton = UIBarButtonItem(
        barButtonSystemItem: .edit,
        target: self,
        action: #selector(didTapEdit)
    )

    private lazy var doneButton: UIBarButtonItem = {
        let theme = themeManager.getCurrentTheme(for: windowUUID)
        guard #available(iOS 26.0, *), theme.isNova else {
            return UIBarButtonItem(
                barButtonSystemItem: .done,
                target: self,
                action: #selector(didTapDone)
            )
        }
        let button = UIBarButtonItem(
            image: UIImage(named: StandardImageIdentifiers.Large.checkmark)?
                .withTintColor(theme.colors.iconInverted, renderingMode: .alwaysOriginal),
            style: .prominent,
            target: self,
            action: #selector(didTapDone)
        )
        button.tintColor = theme.colors.actionPrimary
        button.accessibilityLabel = .AppSettingsDone
        return button
    }()

    private lazy var cancelButton = UIBarButtonItem(
        barButtonSystemItem: .cancel,
        target: self,
        action: #selector(didTapCancel)
    )

    // MARK: - Themeable

    var themeManager: ThemeManager
    var themeListenerCancellable: Any?
    var notificationCenter: NotificationProtocol

    var currentWindowUUID: WindowUUID? { return windowUUID }

    weak var coordinator: TranslationPickerSettingsDelegate?

    let windowUUID: WindowUUID
    private var state: TranslationSettingsState
    private let viewModel: TranslationSettingsViewModel

    init(windowUUID: WindowUUID,
         themeManager: ThemeManager = AppContainer.shared.resolve(),
         notificationCenter: NotificationCenter = NotificationCenter.default,
         viewModel: TranslationSettingsViewModel? = nil) {
        self.windowUUID = windowUUID
        self.viewModel = viewModel
            ?? TranslationSettingsViewModel(service: TranslationSettingsService(windowUUID: windowUUID))
        self.themeManager = themeManager
        self.notificationCenter = notificationCenter
        state = TranslationSettingsState()
        super.init(nibName: nil, bundle: nil)
        title = .Settings.Translation.Title
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCollectionView()
        listenForThemeChanges(withNotificationCenter: notificationCenter)
        applyTheme()
        bindViewModel()
        viewModel.viewDidLoad()
    }

    // MARK: - View model

    private func bindViewModel() {
        viewModel.onStateChange = { [weak self] state in
            self?.render(state)
        }
    }

    private func render(_ state: TranslationSettingsState) {
        let wasEnabled = self.state.isTranslationsEnabled
        let wasEditing = self.state.isEditing
        self.state = state
        if wasEnabled && !state.isTranslationsEnabled {
            collectionView.cancelInteractiveMovement()
        }
        if wasEditing != state.isEditing {
            collectionView.isEditing = state.isEditing
            setEditing(state.isEditing, animated: true)
        }
        updateNavBar()
        updateDoneButton()
        // Defer snapshot apply to avoid a deadlock when newState is triggered
        // from inside a UIKit snapshot apply (e.g. the swipe-to-delete handler).
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.dataSource.applySnapshot(state: self.state, animated: true)
        }
    }

    // MARK: - Setup

    private func setupCollectionView() {
        collectionView.delegate = self
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func makeLayout(backgroundColor: UIColor? = nil) -> UICollectionViewCompositionalLayout {
        var config = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        config.headerMode = .supplementary
        config.footerMode = .supplementary
        config.backgroundColor = backgroundColor
        return UICollectionViewCompositionalLayout.list(using: config)
    }

    // MARK: - Data source

    private func makeDataSource() -> TranslationSettingsDiffableDataSource {
        let toggleReg = UICollectionView.CellRegistration<
            TranslationToggleCell, TranslationSettingsItem
        > { [weak self] cell, _, _ in
            guard let self else { return }
            cell.configure(
                title: .Settings.Translation.ToggleTitle,
                isOn: state.isTranslationsEnabled,
                accessibilityIdentifier: AccessibilityIdentifiers.Settings.Translation.toggleSwitch,
                target: self,
                action: #selector(didToggleTranslations(_:)),
                theme: themeManager.getCurrentTheme(for: windowUUID)
            )
        }

        let autoTranslateReg = UICollectionView.CellRegistration<
            TranslationToggleCell, TranslationSettingsItem
        > { [weak self] cell, _, _ in
            guard let self else { return }
            cell.configure(
                title: .Settings.Translation.AutoTranslate.Title,
                isOn: state.isAutoTranslateEnabled,
                accessibilityIdentifier: AccessibilityIdentifiers.Settings.Translation.autoTranslateSwitch,
                target: self,
                action: #selector(didToggleAutoTranslate(_:)),
                theme: themeManager.getCurrentTheme(for: windowUUID)
            )
        }

        let languageReg = makeLanguageCellRegistration()

        let addLanguageReg = UICollectionView.CellRegistration<
            TranslationAddLanguageCell, TranslationSettingsItem
        > { [weak self] cell, _, _ in
            guard let self else { return }
            cell.configure(theme: themeManager.getCurrentTheme(for: windowUUID))
        }

        let dataSource = TranslationSettingsDiffableDataSource(
            collectionView: collectionView
        ) { collectionView, indexPath, item in
            switch item {
            case .enableToggle:
                return collectionView.dequeueConfiguredReusableCell(
                    using: toggleReg, for: indexPath, item: item)
            case .autoTranslate:
                return collectionView.dequeueConfiguredReusableCell(
                    using: autoTranslateReg, for: indexPath, item: item)
            case .language:
                return collectionView.dequeueConfiguredReusableCell(
                    using: languageReg, for: indexPath, item: item)
            case .addLanguage:
                return collectionView.dequeueConfiguredReusableCell(
                    using: addLanguageReg, for: indexPath, item: item)
            }
        }

        let headerReg = dataSource.makeHeaderRegistration()
        let footerReg = dataSource.makeFooterRegistration()
        dataSource.supplementaryViewProvider = { collectionView, kind, indexPath in
            switch kind {
            case UICollectionView.elementKindSectionHeader:
                return collectionView.dequeueConfiguredReusableSupplementary(
                    using: headerReg, for: indexPath)
            case UICollectionView.elementKindSectionFooter:
                return collectionView.dequeueConfiguredReusableSupplementary(
                    using: footerReg, for: indexPath)
            default:
                return nil
            }
        }

        dataSource.reorderingHandlers.canReorderItem = { [weak self] item in
            guard let self, state.isTranslationsEnabled else { return false }
            if case .language = item { return true }
            return false
        }

        dataSource.reorderingHandlers.didReorder = { [weak self] transaction in
            guard let self else { return }
            let newItems = transaction.finalSnapshot.itemIdentifiers(inSection: .preferredLanguages)
            let reorderedLanguages = newItems.compactMap { item -> PreferredLanguageDetails? in
                if case .language(let details) = item { return details }
                return nil
            }
            if state.isEditing {
                viewModel.reorderLanguages(reorderedLanguages)
            } else {
                viewModel.saveLanguages(reorderedLanguages.map { $0.code })
            }
        }

        return dataSource
    }

    private func makeLanguageCellRegistration(
    ) -> UICollectionView.CellRegistration<TranslationLanguageCell, TranslationSettingsItem> {
        UICollectionView.CellRegistration { [weak self] cell, _, item in
            guard let self, case let .language(details) = item else { return }
            cell.configure(with: details, theme: themeManager.getCurrentTheme(for: windowUUID))
            if details.isDeviceLanguage {
                cell.accessories = [.reorder(displayed: .always)]
            } else {
                let deleteActionHandler = { [weak self] in
                    guard let self else { return }
                    viewModel.removeLanguage(code: details.code)
                }
                cell.accessories = [
                    .delete(displayed: .whenEditing, actionHandler: deleteActionHandler),
                    .reorder(displayed: .always)
                ]
                cell.accessibilityCustomActions = [
                    UIAccessibilityCustomAction(
                        name: .Settings.Translation.PreferredLanguages.RemoveLanguageA11yAction,
                        actionHandler: { _ in
                            deleteActionHandler()
                            return true
                        }
                    )
                ]
            }
        }
    }

    // MARK: - Toggle actions

    @objc private func didToggleTranslations(_ sender: UISwitch) {
        guard !state.isEditing else {
            sender.setOn(state.isTranslationsEnabled, animated: false)
            return
        }
        viewModel.toggleTranslationsEnabled()
    }

    @objc private func didToggleAutoTranslate(_ sender: UISwitch) {
        guard !state.isEditing else {
            sender.setOn(state.isAutoTranslateEnabled, animated: false)
            return
        }
        viewModel.toggleAutoTranslate()
    }

    // MARK: - Nav bar

    private func updateNavBar() {
        if state.isEditing {
            navigationItem.leftBarButtonItem = cancelButton
            navigationItem.rightBarButtonItem = doneButton
        } else {
            navigationItem.leftBarButtonItem = nil
            let languages = state.preferredLanguages
            navigationItem.rightBarButtonItem = (state.isTranslationsEnabled && languages.count > 1) ? editButton : nil
        }
    }

    // MARK: - Edit mode

    @objc private func didTapEdit() {
        viewModel.enterEditMode()
    }

    @objc private func didTapDone() {
        guard let pendingLanguages = state.pendingLanguages else { return }
        viewModel.saveLanguages(pendingLanguages.map { $0.code })
        viewModel.cancelEditMode()
    }

    @objc private func didTapCancel() {
        viewModel.cancelEditMode()
    }

    private func updateDoneButton() {
        guard state.isEditing, let pendingLanguages = state.pendingLanguages else { return }
        doneButton.isEnabled = pendingLanguages != state.preferredLanguages
    }

    // MARK: - Theming

    func applyTheme() {
        let theme = themeManager.getCurrentTheme(for: windowUUID)
        view.backgroundColor = theme.colors.layer1
        collectionView.setCollectionViewLayout(makeLayout(backgroundColor: theme.colors.layer1), animated: false)
        navigationController?.navigationBar.tintColor = theme.colors.actionPrimary
        if #available(iOS 26.0, *), theme.isNova {
            doneButton.tintColor = theme.colors.actionPrimary
            doneButton.image = UIImage(named: StandardImageIdentifiers.Large.checkmark)?
                .withTintColor(theme.colors.iconInverted, renderingMode: .alwaysOriginal)
        }
        collectionView.visibleCells.forEach { ($0 as? ThemeApplicable)?.applyTheme(theme: theme) }
    }

    // MARK: - UICollectionViewDelegate

    func collectionView(
        _ collectionView: UICollectionView,
        targetIndexPathForMoveFromItemAt originalIndexPath: IndexPath,
        toProposedIndexPath proposedIndexPath: IndexPath
    ) -> IndexPath {
        guard proposedIndexPath.section == originalIndexPath.section,
              dataSource.itemIdentifier(for: proposedIndexPath) != .addLanguage else {
            return originalIndexPath
        }
        return proposedIndexPath
    }

    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        return dataSource.itemIdentifier(for: indexPath) == .addLanguage
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard dataSource.itemIdentifier(for: indexPath) == .addLanguage else { return }
        coordinator?.showLanguagePicker(availableLanguages: state.availableLanguages) { [weak self] code in
            self?.viewModel.addLanguage(code: code)
        }
    }
}
