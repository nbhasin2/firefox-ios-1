// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Foundation

/// Owns the in-progress "Report a Website Issue" draft and the effects that were previously
/// split between `WebCompatReporterMiddleware` and the state's reducer.
///
/// State changes are published synchronously through `onStateChange`, matching what
/// `StoreSubscriber.newState(state:)` used to guarantee. Preview and submit were transient
/// state fields only because Redux had no way to model a one-shot event; here they are callbacks.
@MainActor
final class WebCompatReporterViewModel {
    private(set) var state: WebCompatReporterState {
        didSet {
            guard state != oldValue else { return }
            onStateChange?(state)
        }
    }

    var onStateChange: ((WebCompatReporterState) -> Void)?
    var onPreviewReady: ((WebCompatReportPayload) -> Void)?
    var onSubmitted: (() -> Void)?

    private let windowUUID: WindowUUID
    private let windowManager: WindowManager
    private let recorder: WebCompatReportRecorder
    private let telemetry: WebCompatReporterTelemetry

    init(windowUUID: WindowUUID,
         windowManager: WindowManager = AppContainer.shared.resolve(),
         recorder: WebCompatReportRecorder = WebCompatReportRecorder(),
         telemetry: WebCompatReporterTelemetry = WebCompatReporterTelemetry()) {
        self.windowUUID = windowUUID
        self.windowManager = windowManager
        self.recorder = recorder
        self.telemetry = telemetry
        self.state = WebCompatReporterState()
    }

    // MARK: - Intents

    /// The presenting layer passes the current tab URL.
    func viewDidLoad(url: String?) {
        guard let url else { return }
        state.url = url
    }

    func editURL(_ url: String) {
        state.url = url
    }

    func selectCategory(_ category: WebCompatIssueCategory) {
        guard category != state.selectedCategory else { return }
        telemetry.reasonSelected(category: category)
        state.selectedCategory = category
        // A new category clears the previous sub-option.
        state.selectedSubOptionID = nil
    }

    func selectSubOption(id: String?) {
        state.selectedSubOptionID = id
    }

    func setAdditionalDetails(_ details: String) {
        state.additionalDetails = details
    }

    func toggleScreenshot(_ isIncluded: Bool? = nil) {
        state.includeScreenshot = isIncluded ?? !state.includeScreenshot
    }

    func toggleBlockedList(_ isIncluded: Bool? = nil) {
        state.includeBlockedList = isIncluded ?? !state.includeBlockedList
    }

    func preview() {
        guard state.isURLValid else { return }
        telemetry.previewed()
        onPreviewReady?(makeReport())
    }

    func submit() {
        guard state.isURLValid else { return }
        recorder.submit(makeReport())
        // The screenshot option is parked (FXIOS-16450) and no image is transported yet.
        telemetry.created(withBlockedTrackers: state.includeBlockedList, withScreenshot: false)
        onSubmitted?()
    }

    func cancel() {
        telemetry.cancelled()
    }

    func learnMoreTapped() {
        telemetry.learnMoreTapped()
    }

    // MARK: - Report assembly

    /// The only place a report is assembled, so the preview can't differ from what's sent.
    private func makeReport() -> WebCompatReportPayload {
        let payload = WebCompatReportPayload.make(from: state)
        guard let tab = windowManager.tabManager(for: windowUUID)?.selectedTab else { return payload }
        return WebCompatReportDataCollector.enrich(
            payload,
            tab: tab,
            includeBlockedList: state.includeBlockedList,
            includeTabSpecificInfo: isReporting(state.url, on: tab)
        )
    }

    /// Origin and path, as desktop does.
    private func isReporting(_ reportedURL: String, on tab: Tab) -> Bool {
        guard let reported = URL(string: reportedURL), let current = tab.url else { return false }
        return reported.scheme == current.scheme
            && reported.host == current.host
            && reported.port == current.port
            && reported.path == current.path
    }
}
