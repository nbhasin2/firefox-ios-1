// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Foundation
import Redux
import UIKit
import XCTest

@testable import Client

final class TabManagerRestoreScreenshotTests: TabManagerTestsBase, BusTestUtility {
    var mockBus: MockBrowserEventBus!

    override func setUp() async throws {
        try await super.setUp()
        setIsDeeplinkOptimizationRefactorEnabled(true)
        setupBus()
    }

    override func tearDown() async throws {
        resetBus()
        mockBus = nil
        try await super.tearDown()
    }

    @MainActor
    func testRestoreScreenshot_doesNotDispatch_whenTabAlreadyHasScreenshot() {
        let tabs = generateTabs(count: 1)
        let tab = tabs[0]
        tab.setScreenshot(UIImage())
        let subject = createSubject(tabs: tabs)

        subject.restoreScreenshot(for: tab)

        XCTAssertTrue(
            mockBus.dispatchedActions.isEmpty,
            "restoreScreenshot must not dispatch any action when the tab's screenshot is already in memory."
        )
        XCTAssertTrue(
            mockDiskImageStore.getImageForKeyCalls.isEmpty,
            "The disk store should not be hit when the screenshot is already in memory."
        )
    }

    @MainActor
    func testRestoreScreenshot_dispatchesScreenshotRestored_whenTabHasNoScreenshot() {
        let tabs = generateTabs(count: 1)
        let tab = tabs[0]
        XCTAssertNil(tab.screenshot, "Precondition: tab starts with no in-memory screenshot.")
        let subject = createSubject(tabs: tabs)

        let expectation = XCTestExpectation(description: "screenshotRestored is dispatched after the disk load.")
        mockBus.dispatchCalled = { [weak mockBus] in
            let isScreenshotRestored: (Action) -> Bool = {
                ($0 as? ScreenshotAction)?.actionType as? ScreenshotActionType == .screenshotRestored
            }
            guard mockBus?.dispatchedActions.contains(where: isScreenshotRestored) == true else { return }
            expectation.fulfill()
        }

        subject.restoreScreenshot(for: tab)

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - BusTestUtility

    @MainActor
    func setupBus() {
        mockBus = MockBrowserEventBus()
        BusTestUtilityHelper.setupBus(with: mockBus)
    }

    @MainActor
    func resetBus() {
        BusTestUtilityHelper.resetBus()
    }
}
