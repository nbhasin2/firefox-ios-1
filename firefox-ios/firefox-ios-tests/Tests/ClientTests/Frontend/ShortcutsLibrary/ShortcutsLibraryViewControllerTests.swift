// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import XCTest

@testable import Client

@MainActor
final class ShortcutsLibraryViewControllerTests: XCTestCase {
    private var mockGleanWrapper: MockGleanWrapper!

    override func setUp() async throws {
        try await super.setUp()
        await DependencyHelperMock().bootstrapDependencies()
        mockGleanWrapper = MockGleanWrapper()
    }

    override func tearDown() async throws {
        mockGleanWrapper = nil
        DependencyHelperMock().reset()
        try await super.tearDown()
    }

    /// The lifecycle dispatches are gone; the controller drives the view model, which records the
    /// telemetry the middleware used to.
    func test_viewDidAppear_recordsTheViewedEvent() {
        let subject = createSubject()

        subject.viewDidAppear(false)

        XCTAssertEqual(mockGleanWrapper.recordEventNoExtraCalled, 1)
    }

    func test_viewDidDisappear_recordsTheClosedEvent() {
        let subject = createSubject()

        subject.viewDidDisappear(false)

        XCTAssertEqual(mockGleanWrapper.recordEventNoExtraCalled, 1)
    }

    func test_viewDidDisappear_afterDeeplinkDismissal_recordsNothing() {
        let subject = createSubject()

        subject.willBeDismissed(reason: .deeplink)
        subject.viewDidDisappear(false)

        XCTAssertEqual(mockGleanWrapper.recordEventNoExtraCalled, 0)
    }

    private func createSubject() -> ShortcutsLibraryViewController {
        let viewModel = ShortcutsLibraryViewModel(
            windowUUID: .XCTestDefaultUUID,
            topSitesService: TopSitesService(topSitesManager: MockTopSitesManager()),
            featureFlagsProvider: MockNimbusFeatureFlags(),
            telemetry: ShortcutsLibraryTelemetry(gleanWrapper: mockGleanWrapper)
        )
        let subject = ShortcutsLibraryViewController(windowUUID: .XCTestDefaultUUID, viewModel: viewModel)
        trackForMemoryLeaks(subject)
        return subject
    }
}
