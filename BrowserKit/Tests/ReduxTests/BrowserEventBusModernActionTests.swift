// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import XCTest
import Common
@testable import Redux

@MainActor
final class BrowserEventBusModernActionTests: XCTestCase {
    var observer = MockActionObserver()
    let fakeWindowUUID = UUID()

    override func setUp() async throws {
        try await super.setUp()
        observer = MockActionObserver()
    }

    private func createStore() -> BrowserEventBus {
        let store = BrowserEventBus()
        observer.observe(store)
        return store
    }

    func testDispatchBasicAction() throws {
        let store = createStore()

        let testAction = FakeReduxModernAction.counterIncreased(counterValue: 1)

        store.dispatch(testAction, forWindowUUID: fakeWindowUUID)

        guard observer.receivedModernActions.count == 1 else {
            XCTFail("Expected 1 action fired")
            return
        }

        let recordedAction = try XCTUnwrap(
            observer.receivedModernActions.first?.0 as? FakeReduxModernAction
        )
        let recordedActionWindowUUID = try XCTUnwrap(
            observer.receivedModernActions.first?.1
        )
        XCTAssertEqual(recordedAction, testAction)
        XCTAssertEqual(recordedActionWindowUUID, fakeWindowUUID)
    }

    func testDispatchMultipleActions() throws {
        let store = createStore()

        let testAction1 = FakeReduxModernAction.counterIncreased(counterValue: 13)
        let testAction2 = FakeReduxModernAction.counterDecreased(counterValue: 12)
        let testAction3 = FakeReduxModernAction.counterIncreased(counterValue: 11)

        store.dispatch(testAction1, forWindowUUID: fakeWindowUUID)
        store.dispatch(testAction2, forWindowUUID: fakeWindowUUID)
        store.dispatch(testAction3, forWindowUUID: fakeWindowUUID)

        guard observer.receivedModernActions.count == 3 else {
            XCTFail("Expected 3 actions fired")
            return
        }

        let recordedAction1 = try XCTUnwrap(
            observer.receivedModernActions[0].0 as? FakeReduxModernAction
        )
        let recordedAction1WindowUUID = try XCTUnwrap(
            observer.receivedModernActions[0].1
        )

        let recordedAction2 = try XCTUnwrap(
            observer.receivedModernActions[1].0 as? FakeReduxModernAction
        )
        let recordedAction2WindowUUID = try XCTUnwrap(
            observer.receivedModernActions[1].1
        )

        let recordedAction3 = try XCTUnwrap(
            observer.receivedModernActions[2].0 as? FakeReduxModernAction
        )
        let recordedAction3WindowUUID = try XCTUnwrap(
            observer.receivedModernActions[2].1
        )

        XCTAssertEqual(recordedAction1, testAction1)
        XCTAssertEqual(recordedAction2, testAction2)
        XCTAssertEqual(recordedAction3, testAction3)

        XCTAssertEqual(recordedAction1WindowUUID, fakeWindowUUID)
        XCTAssertEqual(recordedAction2WindowUUID, fakeWindowUUID)
        XCTAssertEqual(recordedAction3WindowUUID, fakeWindowUUID)
    }
}
