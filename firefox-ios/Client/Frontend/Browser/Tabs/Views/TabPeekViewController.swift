// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import UIKit
import Common
import WebKit

final class TabPeekViewController: UIViewController {
    var tabPeekState: TabPeekState { return viewModel.state }
    private let windowUUID: WindowUUID
    private let viewModel: TabPeekViewModel

    private var tabModel: TabModel

    // MARK: - Lifecycle methods

    init(tab: TabModel, windowUUID: WindowUUID, viewModel: TabPeekViewModel? = nil) {
        self.tabModel = tab
        self.windowUUID = windowUUID
        self.viewModel = viewModel ?? TabPeekViewModel(tabUUID: tab.tabUUID, windowUUID: windowUUID)
        super.init(nibName: nil, bundle: nil)

        self.viewModel.onChange = { [weak self] _ in
            self?.setupWithScreenshot()
        }
        self.viewModel.viewDidLoad()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func contextActions(defaultActions: [UIMenuElement]) -> UIMenu {
        return makeMenuActions()
    }

    // MARK: - Private helper methods

    private func setupWithScreenshot() {
        let imageView: UIImageView = .build { imageView in
            imageView.image = self.tabPeekState.screenshot
        }
        imageView.contentMode = .scaleAspectFill
        view.addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: view.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        imageView.accessibilityLabel = tabPeekState.previewAccessibilityLabel
    }

    private func makeMenuActions() -> UIMenu {
        var actions = [UIAction]()

        if tabPeekState.showAddToBookmarks {
            actions.append(UIAction(title: .TabPeekAddToBookmarks,
                                    image: UIImage.templateImageNamed(StandardImageIdentifiers.Large.bookmark),
                                    identifier: nil) { [weak self] _ in
                self?.viewModel.addToBookmarks()
            })
        }
        if tabPeekState.showRemoveBookmark {
            actions.append(UIAction(title: .TabPeekRemoveBookmark,
                                    image: UIImage.templateImageNamed(StandardImageIdentifiers.Large.bookmarkFill),
                                    identifier: nil) { [weak self] _ in
                self?.viewModel.removeBookmark()
            })
        }
        if tabPeekState.showCopyURL {
            actions.append(UIAction(title: .TabPeekCopyUrl,
                                    image: UIImage.templateImageNamed(StandardImageIdentifiers.Large.link),
                                    identifier: nil) { [weak self] _ in
                self?.viewModel.copyURL()
            })
        }
        if tabPeekState.showCloseTab {
            actions.append(UIAction(title: .TabPeekCloseTab,
                                    image: UIImage.templateImageNamed(StandardImageIdentifiers.Large.cross),
                                    identifier: nil) { [weak self] _ in
                self?.viewModel.closeTab()
            })
        }

        return UIMenu(title: "", children: actions)
    }
}
