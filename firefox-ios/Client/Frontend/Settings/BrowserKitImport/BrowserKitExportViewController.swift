// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import BrowserKit
import Common
import class MozillaAppServices.BookmarkFolderData
import class MozillaAppServices.BookmarkItemData
import class MozillaAppServices.BookmarkNodeData
import enum MozillaAppServices.BookmarkRoots
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

        // exportBrowserData(_:) takes an AsyncStream<BEBrowserData> containing ALL items to export.
        // We build a single stream and pass it once; the system calls our continuation per item.
        let stream = buildExportStream(options: options)
        try? await exportManager?.exportBrowserData(stream)

        // Signal completion to the system (NS_REFINED_FOR_SWIFT — call via ObjC name with __)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            exportManager?.__exportFinished(completionHandler: { _ in continuation.resume() })
        }
    }

    private func requestExport(metadata: BEExportMetadata) async throws -> BEExportOptions {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<BEExportOptions, Error>) in
            exportManager?.requestExport(for: metadata, token: token) { options, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let options {
                    continuation.resume(returning: options)
                } else {
                    continuation.resume(throwing: NSError(domain: "BEExport", code: -1))
                }
            }
        }
    }

    // MARK: - AsyncStream builder

    /// Builds a single AsyncStream<BEBrowserData> combining bookmarks + history + reading list.
    /// The stream is passed as a whole to exportBrowserData(_:).
    private func buildExportStream(options: BEExportOptions) -> AsyncStream<BEBrowserData> {
        AsyncStream { continuation in
            Task {
                if options.dataTypes.contains(.bookmarks) {
                    await streamBookmarks(to: continuation)
                }
                if options.dataTypes.contains(.history) {
                    await streamHistory(to: continuation)
                }
                if options.dataTypes.contains(.readingList) {
                    await streamReadingList(to: continuation)
                }
                continuation.finish()
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
                continuation.resume(returning: self.countBookmarkNodes(root))
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
            profile.readingList.getAvailableRecords { records in
                continuation.resume(returning: records.count)
            }
        }
    }

    // MARK: - Data streaming into AsyncStream.Continuation

    private func streamBookmarks(to continuation: AsyncStream<BEBrowserData>.Continuation) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            profile.places.getBookmarksTree(
                rootGUID: BookmarkRoots.MobileFolderGUID,
                recursive: true
            ) { result in
                guard let root = try? result.get() else {
                    cont.resume()
                    return
                }
                Task {
                    await self.yieldBookmarkNode(root, to: continuation)
                    cont.resume()
                }
            }
        }
    }

    private func yieldBookmarkNode(_ node: BookmarkNodeData,
                                   to continuation: AsyncStream<BEBrowserData>.Continuation) async {
        if let folder = node as? BookmarkFolderData {
            let data = BEBrowserDataBookmark(
                isFolder: true,
                title: folder.title ?? "",
                identifier: folder.guid,
                url: nil,
                parentIdentifier: folder.parentGUID
            )
            continuation.yield(data)
            for child in folder.children ?? [] {
                await yieldBookmarkNode(child, to: continuation)
            }
        } else if let item = node as? BookmarkItemData {
            let data = BEBrowserDataBookmark(
                isFolder: false,
                title: item.title ?? "",
                identifier: item.guid,
                url: URL(string: item.url),
                parentIdentifier: item.parentGUID
            )
            continuation.yield(data)
        }
    }

    private func streamHistory(to continuation: AsyncStream<BEBrowserData>.Continuation) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            profile.places.getSitesWithBound(
                limit: 10_000,
                offset: 0,
                excludedTypes: VisitTransitionSet(0)
            ).upon { result in
                let sites = result.successValue?.asArray() ?? []
                Task {
                    for site in sites {
                        guard let url = URL(string: site.url),
                              let visit = site.latestVisit else { continue }
                        // Visit.date is microseconds since epoch; BEBrowserDataHistoryVisit.dateOfLastVisit is Date
                        let date = Date(timeIntervalSince1970: Double(visit.date) / 1_000_000)
                        let data = BEBrowserDataHistoryVisit(
                            url: url,
                            dateOfLastVisit: date,
                            title: site.title,
                            loadedSuccessfully: true,
                            httpGet: visit.type == .link,
                            redirectSourceURL: nil,
                            redirectSourceDateOfVisit: nil,
                            redirectDestinationURL: nil,
                            redirectDestinationDateOfVisit: nil,
                            visitCount: 1
                        )
                        continuation.yield(data)
                    }
                    cont.resume()
                }
            }
        }
    }

    private func streamReadingList(to continuation: AsyncStream<BEBrowserData>.Continuation) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            profile.readingList.getAvailableRecords { records in
                Task {
                    for record in records {
                        guard let url = URL(string: record.url) else { continue }
                        let data = BEBrowserDataReadingListItem(
                            title: record.title,
                            url: url,
                            dateOfLastVisit: nil
                        )
                        continuation.yield(data)
                    }
                    cont.resume()
                }
            }
        }
    }
}
