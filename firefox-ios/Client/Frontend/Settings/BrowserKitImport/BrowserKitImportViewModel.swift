// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import BrowserKit
import Common
import Foundation
import Glean
import MozillaAppServices
import Storage

@available(iOS 26.4, *)
@MainActor
final class BrowserKitImportViewModel {
    private let profile: Profile
    private let importManager = BEBrowserDataImportManager()

    // MARK: - Progress tracking callbacks

    var onProgressUpdate: ((ImportProgress) -> Void)?
    var onComplete: (() -> Void)?
    var onError: ((Error) -> Void)?

    struct ImportProgress {
        var bookmarks: Int = 0
        var history: Int = 0
        var readingList: Int = 0
        var extensions: Int = 0
    }

    private var progress = ImportProgress()
    private var guidMap: [String: String] = [:]
    private var pendingExtensions: [BEBrowserDataExtension] = []

    // Note: ViewModel does NOT need windowUUID — that's for the ViewController's Themeable.
    init(profile: Profile) {
        self.profile = profile
    }

    // MARK: - Step 1: Show system import sheet

    func requestImport(from scene: UIWindowScene) async {
        let metadata = BEImportMetadata(supportForImportFromFiles: false)
        do {
            let options = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<BEImportOptions, Error>) in
                importManager.requestImport(for: metadata) { options, error in
                    if let error { continuation.resume(throwing: error) }
                    else if let options { continuation.resume(returning: options) }
                }
            }
            if !options.importFromFiles {
                // browser-to-browser path — token arrives via NSUserActivity
                // nothing to do here; wait for the activity to call handleImport(token:)
            }
        } catch {
            onError?(error)
        }
    }

    // MARK: - Step 2: Receive token + stream data

    // importBrowserData(withToken:importBlock:) is marked NS_REFINED_FOR_SWIFT.
    // The Swift API is importBrowserData(token:) returning AsyncThrowingStream<BEBrowserData, Error>.
    func handleImport(token: UUID) async {
        GleanMetrics.BrowserKitImport.started.record()
        do {
            for try await data in importManager.importBrowserData(token: token) {
                await process(data)
                onProgressUpdate?(progress)
            }
            // After stream ends, prompt once for any collected extensions
            if !pendingExtensions.isEmpty {
                await promptForExtensions()
            }
            GleanMetrics.BrowserKitImport.completed.record(
                GleanMetrics.BrowserKitImport.CompletedExtra(
                    bookmarksCount: Int32(progress.bookmarks),
                    historyCount: Int32(progress.history),
                    readingListCount: Int32(progress.readingList)
                )
            )
            onComplete?()
        } catch {
            let nsError = error as NSError
            GleanMetrics.BrowserKitImport.failed.record(
                GleanMetrics.BrowserKitImport.FailedExtra(
                    errorCode: Int32(nsError.code),
                    errorDomain: nsError.domain
                )
            )
            onError?(error)
        }
    }

    // MARK: - Step 3: Route each BEBrowserData type to storage

    private func process(_ data: BEBrowserData) async {
        switch data {
        case let bookmark as BEBrowserDataBookmark:
            // Drop malformed items: non-folder bookmarks with no URL
            guard bookmark.isFolder || bookmark.url != nil else { break }
            await importBookmark(bookmark)
            progress.bookmarks += 1

        case let visit as BEBrowserDataHistoryVisit:
            // Skip failed loads and history older than 90 days
            let cutoff = Date().addingTimeInterval(-90 * 24 * 60 * 60)
            guard visit.loadedSuccessfully,
                  visit.dateOfLastVisit > cutoff else { break }
            await importHistoryVisit(visit)
            progress.history += 1

        case let item as BEBrowserDataReadingListItem:
            // Skip items never opened
            guard item.dateOfLastVisit != nil else { break }
            await importReadingListItem(item)
            progress.readingList += 1

        case let ext as BEBrowserDataExtension:
            // Collect all extensions; prompt once after stream ends (not per-item)
            pendingExtensions.append(ext)
            progress.extensions += 1

        default:
            break
        }
    }

    // MARK: - Storage writes

    private func importBookmark(_ bookmark: BEBrowserDataBookmark) async {
        if bookmark.isFolder {
            // Folders must use createFolder, not createBookmark
            let parentGUID = resolvedParentGUID(for: bookmark.parentIdentifier)
            await withCheckedContinuation { continuation in
                profile.places.createFolder(
                    parentGUID: parentGUID,
                    title: bookmark.title,
                    position: nil
                ) { [self] result in
                    // Store mapping: source identifier → new GUID for child resolution
                    // bookmark.identifier is NSString nonnull, bridged to non-optional String
                    if let guid = try? result.get() {
                        let sourceID = bookmark.identifier
                        self.guidMap[sourceID] = guid
                    }
                    continuation.resume()
                }
            }
        } else {
            guard let url = bookmark.url?.absoluteString else { return }
            let parentGUID = resolvedParentGUID(for: bookmark.parentIdentifier)
            await withCheckedContinuation { continuation in
                profile.places.createBookmark(
                    parentGUID: parentGUID,
                    url: url,
                    title: bookmark.title,
                    position: nil
                ) { _ in continuation.resume() }
            }
        }
    }

    private func importHistoryVisit(_ visit: BEBrowserDataHistoryVisit) async {
        // VisitObservation.at expects milliseconds since epoch
        let observation = VisitObservation(
            url: visit.url.absoluteString,
            visitType: visit.httpGet ? .link : .typed,
            at: Int64(visit.dateOfLastVisit.timeIntervalSince1970 * 1000)
        )
        await withCheckedContinuation { continuation in
            profile.places.applyObservation(
                visitObservation: observation
            ) { _ in continuation.resume() }
        }
    }

    private func importReadingListItem(_ item: BEBrowserDataReadingListItem) async {
        // addedBy identifies the source app; use bundle identifier for traceability
        let addedBy = item.sourceApplicationBundleIdentifier ?? "com.apple.mobilesafari"
        _ = await withCheckedContinuation { continuation in
            profile.readingList.createRecordWithURL(
                item.url.absoluteString,
                title: item.title,
                addedBy: addedBy
            ).upon { continuation.resume(returning: $0) }
        }
    }

    private func promptForExtensions() async {
        // BEBrowserDataExtension does not map to a Firefox storage layer.
        // After the stream ends, surface a post-import suggestion card for each
        // extension using ext.storeIdentifier to link to App Store product pages.
        // TODO: Implement extension suggestion UI (post-import card / notification)
        // pendingExtensions.forEach { ext in ... }
    }

    // MARK: - GUID resolution helper

    // Maps source app's bookmark identifiers to GUIDs created in RustPlaces
    private func resolvedParentGUID(for sourceIdentifier: String?) -> String {
        guard let sourceIdentifier,
              let mapped = guidMap[sourceIdentifier]
        else { return BookmarkRoots.MobileFolderGUID }
        return mapped
    }
}
