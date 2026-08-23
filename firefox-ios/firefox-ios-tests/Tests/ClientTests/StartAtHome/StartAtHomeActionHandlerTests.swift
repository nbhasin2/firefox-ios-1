// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Redux
import Shared
import XCTest

@testable import Client

final class StartAtHomeActionHandlerTests: XCTestCase, BusTestUtility {
    private var mockProfile: MockProfile!
    private var mockTabManager: MockTabManager!
    private var mockWindowManager: MockWindowManager!
    private var mockBus: MockBrowserEventBus!

    override func setUp() async throws {
        try await super.setUp()
        mockProfile = MockProfile()
        mockTabManager = MockTabManager()
        mockTabManager.tabRestoreHasFinished = true
        mockWindowManager = MockWindowManager(
            wrappedManager: WindowManagerImplementation(),
            tabManager: mockTabManager
        )
        mockWindowManager.overrideWindows = true
        // Inject the mock profile so that `UserFeaturePreferring` resolved from the
        // AppContainer reads from `mockProfile.prefs` (which the tests configure).
        DependencyHelperMock().bootstrapDependencies(
            injectedProfile: mockProfile,
            injectedWindowManager: mockWindowManager,
        )
        setupBus()
    }

    override func tearDown() async throws {
        mockProfile = nil
        mockWindowManager = nil
        DependencyHelperMock().reset()
        resetBus()
        try await super.tearDown()
    }

    func test_didBrowserBecomeActiveAction_withAfterFourHours_returnsTrueStartAtHomeCheck() throws {
        mockProfile.prefs.setString(StartAtHome.afterFourHours.rawValue, forKey: PrefsKeys.FeatureFlags.StartAtHome)
        let subject = createSubject(with: mockProfile)
        let action = StartAtHomeAction(
            windowUUID: .XCTestDefaultUUID,
            actionType: StartAtHomeActionType.didBrowserBecomeActive
        )

        let expectation = XCTestExpectation(description: "Start At Home action should be dispatched")

        mockBus.dispatchCalled = {
            expectation.fulfill()
        }

        subject.handle(action)

        wait(for: [expectation])

        let actionCalled = try XCTUnwrap(mockBus.dispatchedActions.first as? StartAtHomeAction)
        let actionType = try XCTUnwrap(actionCalled.actionType as? StartAtHomeMiddlewareActionType)

        XCTAssertEqual(mockBus.dispatchedActions.count, 1)
        XCTAssertEqual(actionType, StartAtHomeMiddlewareActionType.startAtHomeCheckCompleted)
        XCTAssertEqual(actionCalled.shouldStartAtHome, true)
    }

    func test_didBrowserBecomeActiveAction_withAlways_returnsTrueStartAtHomeCheck() throws {
        mockProfile.prefs.setString(StartAtHome.always.rawValue, forKey: PrefsKeys.FeatureFlags.StartAtHome)
        let subject = createSubject(with: mockProfile)
        let action = StartAtHomeAction(
            windowUUID: .XCTestDefaultUUID,
            actionType: StartAtHomeActionType.didBrowserBecomeActive
        )

        let expectation = XCTestExpectation(description: "Start At Home action should be dispatched")

        mockBus.dispatchCalled = {
            expectation.fulfill()
        }

        subject.handle(action)

        wait(for: [expectation])

        let actionCalled = try XCTUnwrap(mockBus.dispatchedActions.first as? StartAtHomeAction)
        let actionType = try XCTUnwrap(actionCalled.actionType as? StartAtHomeMiddlewareActionType)

        XCTAssertEqual(mockBus.dispatchedActions.count, 1)
        XCTAssertEqual(actionType, StartAtHomeMiddlewareActionType.startAtHomeCheckCompleted)
        XCTAssertEqual(actionCalled.shouldStartAtHome, true)
    }

    func test_didBrowserBecomeActiveAction_withDisabled_returnsFalseStartAtHomeCheck() throws {
        mockProfile.prefs.setString(StartAtHome.disabled.rawValue, forKey: PrefsKeys.FeatureFlags.StartAtHome)
        let subject = createSubject(with: mockProfile)
        let action = StartAtHomeAction(
            windowUUID: .XCTestDefaultUUID,
            actionType: StartAtHomeActionType.didBrowserBecomeActive
        )

        let expectation = XCTestExpectation(description: "Start At Home action should be dispatched")

        mockBus.dispatchCalled = {
            expectation.fulfill()
        }

        subject.handle(action)

        wait(for: [expectation])

        let actionCalled = try XCTUnwrap(mockBus.dispatchedActions.first as? StartAtHomeAction)
        let actionType = try XCTUnwrap(actionCalled.actionType as? StartAtHomeMiddlewareActionType)

        XCTAssertEqual(mockBus.dispatchedActions.count, 1)
        XCTAssertEqual(actionType, StartAtHomeMiddlewareActionType.startAtHomeCheckCompleted)
        XCTAssertEqual(actionCalled.shouldStartAtHome, false)
    }

    // MARK: - Helpers
    private func createSubject(with mockProfile: Profile = MockProfile()) -> StartAtHomeActionHandler {
        /// 9 Sep 2001 8:00 pm GMT + 0
        let testDate = Date(timeIntervalSince1970: 1_000_065_600)
        let lastSessionDate = Calendar.current.date(
            byAdding: .hour,
            value: -5,
            to: testDate
        )!
        UserDefaults.standard.setValue(lastSessionDate, forKey: "LastActiveTimestamp")
        return StartAtHomeActionHandler(
            profile: mockProfile,
            windowManager: mockWindowManager,
            dateProvider: MockDateProvider(fixedDate: testDate))
    }

    // MARK: BusTestUtility

    func setupBus() {
        mockBus = MockBrowserEventBus()
        BusTestUtilityHelper.setupBus(with: mockBus)
    }

    func resetBus() {
        BusTestUtilityHelper.resetBus()
    }
}
