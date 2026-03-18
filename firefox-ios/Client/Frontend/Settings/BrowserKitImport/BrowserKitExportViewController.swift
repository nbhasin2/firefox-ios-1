// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import BrowserKit
import Common
import Storage
import UIKit

@available(iOS 26.4, *)
final class BrowserKitExportViewController: UIViewController {
    private let token: UUID
    private let profile: Profile
    // windowUUID is held for future Themeable adoption
    private let windowUUID: WindowUUID
    private var exportManager: BEBrowserDataExportManager?

    // MARK: - Init

    init(token: UUID, profile: Profile, windowUUID: WindowUUID) {
        self.token = token
        self.profile = profile
        self.windowUUID = windowUUID
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Lifecycle

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard let scene = view.window?.windowScene else { return }
        // IMPORTANT: SDK uses BEBrowserDataExportManager(scene:) with UIWindowScene
        // (Apple docs incorrectly say UIWindow — use UIWindowScene, non-nullable, unwrap first)
        exportManager = BEBrowserDataExportManager(scene: scene)
        Task { await startExport() }
    }

    // MARK: - Export flow

    private func startExport() async {
        // TODO: Query profile.places for real counts before shipping
        // IMPORTANT: parameter label is supportForExportToFiles (not supportingExportToFiles as docs say)
        let metadata = BEExportMetadata(
            supportForExportToFiles: false,
            bookmarksCount: 0,
            readingListCount: 0,
            historyCount: 0,
            extensionsCount: 0
        )

        guard let options = try? await requestExport(metadata: metadata) else { return }

        if options.dataTypes.contains(.bookmarks)   { await streamBookmarks() }
        if options.dataTypes.contains(.history)     { await streamHistory() }
        if options.dataTypes.contains(.readingList) { await streamReadingList() }

        await withCheckedContinuation { continuation in
            exportManager?.exportFinished { _ in continuation.resume() }
        }
    }

    private func requestExport(metadata: BEExportMetadata) async throws -> BEExportOptions {
        try await withCheckedThrowingContinuation { continuation in
            exportManager?.requestExport(for: metadata, token: token) { options, error in
                if let error { continuation.resume(throwing: error) }
                else if let options { continuation.resume(returning: options) }
            }
        }
    }

    // MARK: - Data streaming stubs (Task 16)

    private func streamBookmarks() async {
        // TODO (Task 16): Query profile.places.getBookmarksTree(rootGUID: BookmarkRoots.MobileFolderGUID, recursive: true)
        // Walk tree, call exportManager?.exportBrowserData() for each node
    }

    private func streamHistory() async {
        // TODO (Task 16): Query profile.places history
        // Create BEBrowserDataHistoryVisit per entry
        // Call exportManager?.exportBrowserData() for each
    }

    private func streamReadingList() async {
        // TODO (Task 16): Query profile.readingList.getAvailableRecords()
        // Create BEBrowserDataReadingListItem per record
        // Call exportManager?.exportBrowserData() for each
    }
}
