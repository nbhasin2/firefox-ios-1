// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import BrowserKit
import Common
import UIKit

@available(iOS 26.4, *)
final class BrowserKitImportViewController: UIViewController, Themeable {
    // MARK: - Themeable / ThemeUUIDIdentifiable
    var themeManager: ThemeManager
    var themeListenerCancellable: Any?
    var notificationCenter: NotificationProtocol
    // windowUUID is stored non-optional; currentWindowUUID satisfies ThemeUUIDIdentifiable (optional)
    let windowUUID: WindowUUID
    var currentWindowUUID: WindowUUID? { windowUUID }

    // MARK: - ViewModel

    let viewModel: BrowserKitImportViewModel

    // MARK: - UI Elements

    private lazy var activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    private lazy var statusLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = UIFont.preferredFont(forTextStyle: .body)
        return label
    }()

    private lazy var progressLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.font = UIFont.preferredFont(forTextStyle: .caption1)
        return label
    }()

    // MARK: - Init

    init(viewModel: BrowserKitImportViewModel,
         windowUUID: WindowUUID,
         themeManager: ThemeManager = AppContainer.shared.resolve(),
         notificationCenter: NotificationProtocol = NotificationCenter.default) {
        self.viewModel = viewModel
        self.windowUUID = windowUUID
        self.themeManager = themeManager
        self.notificationCenter = notificationCenter
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = .Settings.General.ImportBrowsingData.Title
        setupLayout()
        listenForThemeChanges(withNotificationCenter: notificationCenter)
        applyTheme()
        bindViewModel()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard let scene = view.window?.windowScene else { return }
        activityIndicator.startAnimating()
        statusLabel.text = "Preparing import…"
        Task {
            await viewModel.requestImport(from: scene)
        }
    }

    // MARK: - Layout

    private func setupLayout() {
        let stack = UIStackView(arrangedSubviews: [activityIndicator, statusLabel, progressLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .center
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24)
        ])
    }

    // MARK: - ViewModel binding

    private func bindViewModel() {
        viewModel.onProgressUpdate = { [weak self] progress in
            DispatchQueue.main.async {
                self?.progressLabel.text = "Bookmarks: \(progress.bookmarks) · History: \(progress.history) · Reading list: \(progress.readingList)"
            }
        }
        viewModel.onComplete = { [weak self] in
            DispatchQueue.main.async {
                self?.activityIndicator.stopAnimating()
                self?.statusLabel.text = "Import complete"
                self?.progressLabel.isHidden = false
            }
        }
        viewModel.onError = { [weak self] error in
            DispatchQueue.main.async {
                self?.activityIndicator.stopAnimating()
                self?.statusLabel.text = "Import failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Themeable

    func applyTheme() {
        let theme = themeManager.getCurrentTheme(for: windowUUID)
        view.backgroundColor = theme.colors.layer1
        statusLabel.textColor = theme.colors.textPrimary
        progressLabel.textColor = theme.colors.textSecondary
        activityIndicator.color = theme.colors.textPrimary
    }
}
