// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import BrowserKit
import Common
import class MozillaAppServices.BookmarkFolderData
import class MozillaAppServices.BookmarkItemData
import class MozillaAppServices.BookmarkNodeData
import struct MozillaAppServices.VisitTransitionSet
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
        // Fetch real item counts so the system sheet can display accurate numbers.
        // IMPORTANT: parameter label is supportForExportToFiles (not supportingExportToFiles as docs say)
        async let bookmarkCount = fetchBookmarkCount()
        async let historyCount = fetchHistoryCount()
        async let readingListCount = fetchReadingListCount()
        let counts = await (bookmarks: bookmarkCount, history: historyCount, readingList: readingListCount)

        let metadata = BEExportMetadata(
            supportForExportToFiles: false,
            bookmarksCount: counts.bookmarks,
            readingListCount: counts.readingList,
            historyCount: counts.history,
            extensionsCount: 0   // Firefox iOS has no exportable extensions
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

    // MARK: - Count prefetch helpers

    private func fetchBookmarkCount() async -> Int {
        await withCheckedContinuation { continuation in
            profile.places.getBookmarksTree(
                rootGUID: BookmarkRoots.MobileFolderGUID,
                recursive: true
            ) { result in
                guard let root = try? result.get() as? BookmarkFolderData else {
                    continuation.resume(returning: 0)
                    return
                }
                continuation.resume(returning: countBookmarkNodes(root))
            }
        }
    }

    private func countBookmarkNodes(_ node: BookmarkNodeData) -> Int {
        if let folder = node as? BookmarkFolderData {
            return (folder.children ?? []).reduce(0) { $0 + countBookmarkNodes($1) }
        }
        return 1
    }

    private func fetchHistoryCount() async -> Int {
        // Use a large page to approximate total; exact count is not exposed directly.
        await withCheckedContinuation { continuation in
            profile.places.getSitesWithBound(
                limit: 10_000,
                offset: 0,
                excludedTypes: VisitTransitionSet(0)
            ).upon { result in
                continuation.resume(returning: result.successValue?.asArray().count ?? 0)
            }
        }
    }

    private func fetchReadingListCount() async -> Int {
        await withCheckedContinuation { continuation in
            profile.readingList.getAvailableRecords(completion: { records in
                continuation.resume(returning: records.count)
            })
        }
    }

    // MARK: - Data streaming

    private func streamBookmarks() async {
        await withCheckedContinuation { continuation in
            profile.places.getBookmarksTree(
                rootGUID: BookmarkRoots.MobileFolderGUID,
                recursive: true
            ) { [weak self] result in
                guard let self, let root = try? result.get() else {
                    continuation.resume()
                    return
                }
                Task {
                    await self.exportBookmarkNode(root)
                    continuation.resume()
                }
            }
        }
    }

    private func exportBookmarkNode(_ node: BookmarkNodeData) async {
        if let folder = node as? BookmarkFolderData {
            let data = BEBrowserDataBookmark()
            data.isFolder = true
            data.title = folder.title
            data.identifier = folder.guid
            data.parentIdentifier = folder.parentGUID
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                exportManager?.exportBrowserData(data) { _ in continuation.resume() }
            }
            for child in folder.children ?? [] {
                await exportBookmarkNode(child)
            }
        } else if let item = node as? BookmarkItemData {
            let data = BEBrowserDataBookmark()
            data.isFolder = false
            data.title = item.title
            data.url = URL(string: item.url)
            data.identifier = item.guid
            data.parentIdentifier = item.parentGUID
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                exportManager?.exportBrowserData(data) { _ in continuation.resume() }
            }
        }
    }

    private func streamHistory() async {
        await withCheckedContinuation { continuation in
            profile.places.getSitesWithBound(
                limit: 10_000,
                offset: 0,
                excludedTypes: VisitTransitionSet(0)
            ).upon { [weak self] result in
                guard let self else {
                    continuation.resume()
                    return
                }
                let sites = result.successValue?.asArray() ?? []
                Task {
                    for site in sites {
                        guard let url = URL(string: site.url),
                              let visit = site.latestVisit else { continue }
                        let data = BEBrowserDataHistoryVisit()
                        data.url = url
                        data.title = site.title
                        data.httpGet = visit.type == .link
                        // Visit.date is microseconds since epoch; BEBrowserDataHistoryVisit.dateOfLastVisit is Date
                        data.dateOfLastVisit = Date(timeIntervalSince1970: Double(visit.date) / 1_000_000)
                        data.loadedSuccessfully = true
                        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                            self.exportManager?.exportBrowserData(data) { _ in c.resume() }
                        }
                    }
                    continuation.resume()
                }
            }
        }
    }

    private func streamReadingList() async {
        await withCheckedContinuation { continuation in
            profile.readingList.getAvailableRecords { [weak self] records in
                guard let self else {
                    continuation.resume()
                    return
                }
                Task {
                    for record in records {
                        guard let url = URL(string: record.url) else { continue }
                        let data = BEBrowserDataReadingListItem()
                        data.url = url
                        data.title = record.title
                        data.sourceApplicationBundleIdentifier = record.addedBy
                        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                            self.exportManager?.exportBrowserData(data) { _ in c.resume() }
                        }
                    }
                    continuation.resume()
                }
            }
        }
    }
}
