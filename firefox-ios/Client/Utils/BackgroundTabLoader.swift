// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Foundation
import Storage
import Shared

/// `BackgroundTabLoader` loads tabs from users adding tabs to "Load in Background" via the share sheet.
/// In other words, the `ShareViewController` adds the tab to the `Profile.TabQueue`, and the
/// `BackgroundTabLoader` dequeues them to be added as tabs in the application.
protocol BackgroundTabLoader {
    /// Load the background tabs in the application using deeplinks
    func loadBackgroundTabs()
}

final class DefaultBackgroundTabLoader: BackgroundTabLoader, FeatureFlaggable, Sendable {
    private let tabQueue: TabQueue
    private let backgroundQueue: DispatchQueueInterface
    private let applicationHelper: ApplicationHelper

    init(tabQueue: TabQueue,
         applicationHelper: ApplicationHelper = DefaultApplicationHelper(),
         backgroundQueue: DispatchQueueInterface = DispatchQueue.global()) {
        self.tabQueue = tabQueue
        self.applicationHelper = applicationHelper
        self.backgroundQueue = backgroundQueue
    }

    func loadBackgroundTabs() {
        // Make sure we load queued tabs on a background thread
        backgroundQueue.async { [weak self] in
            guard let self else { return }
            self.dequeueQueuedTabs()
        }
    }

    private func dequeueQueuedTabs() {
        if featureFlagsProvider.isEnabled(.deferredRemoval) {
            Task { @MainActor [weak self] in
                guard let self,
                      let urls = try? await self.tabQueue.getQueuedTabs(),
                      !urls.isEmpty else { return }
                self.open(queuedTabs: urls)
                try? await self.tabQueue.clearQueuedTabs()
            }
            return
        }

        // Opens the database on a background thread
        tabQueue.getQueuedTabs { @MainActor [weak self] urls in
            guard let self = self else { return }
            // This assumes that the DB returns rows in a sane order.
            guard !urls.isEmpty else { return }

            self.open(queuedTabs: urls)

            // Clear after making an attempt to open. We're making a bet that
            // it's better to run the risk of perhaps opening twice on a crash,
            // rather than losing data.
            self.tabQueue.clearQueuedTabs()
        }
    }

    @MainActor
    private func open(queuedTabs: [ShareItem]) {
        let queuedURLs = queuedTabs.compactMap { $0.url.asURL }
        if !queuedURLs.isEmpty {
            open(urls: queuedURLs)
        }
    }

    @MainActor
    private func open(urls: [URL]) {
        for urlToOpen in urls {
            let urlString = URL.mozInternalScheme + "://open-url?url=\(urlToOpen)"
            guard let url = URL(string: urlString) else { continue }
            applicationHelper.open(url)
        }
    }
}
