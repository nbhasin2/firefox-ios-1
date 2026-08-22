// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common

typealias ShortcutsLibrarySection = ShortcutsLibraryDiffableDataSource.Section
typealias ShortcutsLibraryItem = ShortcutsLibraryDiffableDataSource.Item

@MainActor
final class ShortcutsLibraryDiffableDataSource:
    UICollectionViewDiffableDataSource<ShortcutsLibrarySection, ShortcutsLibraryItem> {
    // MARK: - Enums
    enum Section: Hashable {
        case shortcuts
    }

    enum Item: Hashable {
        case shortcut(TopSiteConfiguration)
        case addShortcutTile

        static var cellTypes: [ReusableCell.Type] {
            return [
                TopSiteCell.self,
            ]
        }

        var canHandleLongPress: Bool {
            switch self {
            case .addShortcutTile:
                return false
            case .shortcut:
                return true
            }
        }
    }

    // MARK: - Private constants
    private let maxShortcutsToShow = 16

    func updateSnapshot(viewModel: ShortcutsLibraryViewModel) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()

        if let shortcuts = getShortcuts(with: viewModel) {
            snapshot.appendSections([.shortcuts])
            snapshot.appendItems(shortcuts, toSection: .shortcuts)
        }

        apply(snapshot, animatingDifferences: true)
    }

    private func getShortcuts(with viewModel: ShortcutsLibraryViewModel) -> [ShortcutsLibraryDiffableDataSource.Item]? {
        let shouldShowAddShortcutTile = viewModel.shouldShowAddShortcutTile
        let numberOfShortcutsToShow = shouldShowAddShortcutTile ? max(maxShortcutsToShow - 1, 0) : maxShortcutsToShow
        let visibleShortcuts: [Item] = viewModel.shortcuts.prefix(numberOfShortcutsToShow).compactMap { .shortcut($0) }
        let visibleItems = shouldShowAddShortcutTile ? visibleShortcuts + [.addShortcutTile] : visibleShortcuts
        guard !visibleItems.isEmpty else { return nil }
        return visibleItems
    }
}
