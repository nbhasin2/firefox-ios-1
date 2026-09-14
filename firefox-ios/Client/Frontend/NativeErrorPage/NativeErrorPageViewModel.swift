// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Foundation

/// Turns the error recorded for this window into the page's display model, and performs the
/// certificate bypass. Replaces `NativeErrorPageMiddleware` and the state's reducer.
///
/// `errorPageLoaded` and `receivedError` were two actions that both meant "re-read the current
/// error and rebuild the model"; here that is one `loadErrorModel()` the view calls when it
/// appears and the coordinator calls when a new error arrives for a page already on screen.
@MainActor
final class NativeErrorPageViewModel {
    private(set) var model: ErrorPageModel?

    var onModelChange: ((ErrorPageModel) -> Void)?

    private let windowUUID: WindowUUID
    private let errorStore: NativeErrorPageErrorStoring
    private let windowManager: WindowManager
    private let logger: Logger

    init(windowUUID: WindowUUID,
         errorStore: NativeErrorPageErrorStoring = NativeErrorPageErrorStore.shared,
         windowManager: WindowManager = AppContainer.shared.resolve(),
         logger: Logger = DefaultLogger.shared) {
        self.windowUUID = windowUUID
        self.errorStore = errorStore
        self.windowManager = windowManager
        self.logger = logger
    }

    // MARK: - Intents

    func loadErrorModel() {
        guard let helper = errorStore.helper(for: windowUUID) else { return }
        let model = helper.parseErrorDetails()
        self.model = model
        onModelChange?(model)
    }

    func bypassCertificateWarning() {
        let selectedTab: Tab? = windowManager.tabManager(for: windowUUID)?.selectedTab
        if selectedTab == nil {
            logger.log(
                "bypassCertificateWarning: Failed to fetch selected tab",
                level: .warning,
                category: .certificate
            )
        }

        guard
            let selectedTab = selectedTab,
            let webView = selectedTab.webView,
            let certDetails = errorStore.helper(for: windowUUID)?.getCertDetails()
        else {
            logger.log(
                "bypassCertificateWarning: Missing required data (tab, webView, cert)",
                level: .warning,
                category: .certificate
            )
            return
        }

        let origin = "\(certDetails.host):\(certDetails.failingURL.port ?? 443)"
        selectedTab.profile.certStore.addCertificate(certDetails.cert, forOrigin: origin)
        // Note: webview.reload will not change the error URL back to the original URL
        webView.replaceLocation(with: certDetails.failingURL)
    }
}
