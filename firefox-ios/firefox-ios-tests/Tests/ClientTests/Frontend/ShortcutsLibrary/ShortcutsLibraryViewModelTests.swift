// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Glean
import XCTest

@testable import Client

/// Replaces `ShortcutsLibraryStateTests` and `ShortcutsLibraryMiddlewareTests`.
@MainActor
final class ShortcutsLibraryViewModelTests: XCTestCase {
    private var mockGleanWrapper: MockGleanWrapper!
    private var topSitesManager: MockTopSitesManager!

    override func setUp() async throws {
        try await super.setUp()
        await DependencyHelperMock().bootstrapDependencies()
        mockGleanWrapper = MockGleanWrapper()
        topSitesManager = MockTopSitesManager()
    }

    override func tearDown() async throws {
        mockGleanWrapper = nil
        topSitesManager = nil
        DependencyHelperMock().reset()
        try await super.tearDown()
    }

    // MARK: - Shortcuts

    /// This is what D-025 was waiting for: the shortcuts arrive from the service rather than from
    /// a `retrievedUpdatedSites` action the state reduced.
    func test_viewDidLoad_fetchesTheShortcuts() async {
        let service = createService()
        let subject = createSubject(service: service)

        subject.viewDidLoad()
        await waitForShortcuts(subject)

        XCTAssertEqual(subject.shortcuts.count, 30)
    }

    func test_retrievedShortcuts_publishTheChange() async {
        let service = createService()
        let subject = createSubject(service: service)
        var changes = 0
        subject.onChange = { changes += 1 }

        subject.viewDidLoad()
        await waitForShortcuts(subject)

        XCTAssertEqual(changes, 1)
    }

    // MARK: - Telemetry

    /// The viewed event fires once per presentation; the state carried this as
    /// `shouldRecordImpressionTelemetry`.
    func test_viewDidAppear_recordsTheViewedEventOnce() {
        let subject = createSubject(service: createService())

        subject.viewDidAppear()
        subject.viewDidAppear()

        XCTAssertEqual(mockGleanWrapper.recordEventNoExtraCalled, 1)
    }

    func test_viewDidDisappear_recordsTheClosedEvent() {
        let subject = createSubject(service: createService())

        subject.viewDidDisappear()

        XCTAssertEqual(mockGleanWrapper.recordEventNoExtraCalled, 1)
    }

    func test_shortcutTapped_recordsTheTappedEvent() {
        let subject = createSubject(service: createService())

        subject.shortcutTapped()

        XCTAssertEqual(mockGleanWrapper.recordEventNoExtraCalled, 1)
    }

    // MARK: - Private Helpers

    private func waitForShortcuts(_ subject: ShortcutsLibraryViewModel) async {
        await waitUntil { !subject.shortcuts.isEmpty }
    }

    private func createService() -> TopSitesService {
        return TopSitesService(topSitesManager: topSitesManager)
    }

    private func createSubject(service: TopSitesService) -> ShortcutsLibraryViewModel {
        let subject = ShortcutsLibraryViewModel(
            windowUUID: .XCTestDefaultUUID,
            topSitesService: service,
            featureFlagsProvider: MockNimbusFeatureFlags(),
            telemetry: ShortcutsLibraryTelemetry(gleanWrapper: mockGleanWrapper)
        )
        trackForMemoryLeaks(subject)
        return subject
    }
}
