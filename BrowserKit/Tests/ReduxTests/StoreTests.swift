// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import XCTest
@testable import Redux

@MainActor
final class StoreTests: XCTestCase {
    var observer = MockActionObserver()

    override func setUp() async throws {
        try await super.setUp()
        observer = MockActionObserver()
    }

    private func createStore() -> Store {
        let store = Store()
        observer.observe(store)
        return store
    }

    func testDispatchBasicAction_mainThread() {
        let store = createStore()

        let action = FakeReduxAction(
            windowUUID: UUID(),
            actionType: FakeReduxActionType.counterIncreased)

        store.dispatch(action)

        XCTAssertEqual(observer.receivedActions[0] as? FakeReduxActionType, FakeReduxActionType.counterIncreased)
    }

    func testDispatchMultipleActions_mainThread() {
        let store = createStore()

        let action1 = FakeReduxAction(
            windowUUID: UUID(),
            actionType: FakeReduxActionType.counterIncreased)
        store.dispatch(action1)

        let action2 = FakeReduxAction(
            windowUUID: UUID(),
            actionType: FakeReduxActionType.counterDecreased)
        store.dispatch(action2)

        let action3 = FakeReduxAction(
            windowUUID: UUID(),
            actionType: FakeReduxActionType.increaseCounter)
        store.dispatch(action3)

        XCTAssertEqual(observer.receivedActions[0] as? FakeReduxActionType, FakeReduxActionType.counterIncreased)
        XCTAssertEqual(observer.receivedActions[1] as? FakeReduxActionType, FakeReduxActionType.counterDecreased)
        XCTAssertEqual(observer.receivedActions[2] as? FakeReduxActionType, FakeReduxActionType.increaseCounter)
    }

    func testDispatchBasicAction_backgroundThread() async {
        let expectation = expectation(description: "Wait for actions to run")

        let store = createStore()

        let action = FakeReduxAction(
            windowUUID: UUID(),
            actionType: FakeReduxActionType.counterIncreased)

        Task.detached(priority: .background) {
            await MainActor.run {
                store.dispatch(action)
                expectation.fulfill()
            }
        }

        await fulfillment(of: [expectation])

        XCTAssertEqual(observer.receivedActions[0] as? FakeReduxActionType, FakeReduxActionType.counterIncreased)
    }

    func testDispatchMultipleActions_mixThread() async {
        let expectation = expectation(description: "Wait for actions to run")

        let store = createStore()

        Task.detached(priority: .background) {
            let action1 = FakeReduxAction(
                windowUUID: UUID(),
                actionType: FakeReduxActionType.counterIncreased)
            await MainActor.run {
                store.dispatch(action1)
                expectation.fulfill()
            }
        }

        let action2 = FakeReduxAction(
            windowUUID: UUID(),
            actionType: FakeReduxActionType.counterDecreased)
        store.dispatch(action2)

        let action3 = FakeReduxAction(
            windowUUID: UUID(),
            actionType: FakeReduxActionType.increaseCounter)
        store.dispatch(action3)

        await fulfillment(of: [expectation])

        XCTAssertEqual(observer.receivedActions[0] as? FakeReduxActionType, FakeReduxActionType.counterDecreased)
        XCTAssertEqual(observer.receivedActions[1] as? FakeReduxActionType, FakeReduxActionType.increaseCounter)
        XCTAssertEqual(observer.receivedActions[2] as? FakeReduxActionType, FakeReduxActionType.counterIncreased)
    }

    func testDispatchAction_withMidReduceActions() {
        let store = createStore()

        observer.midDeliveryActions = {
            let action2 = FakeReduxAction(
                windowUUID: UUID(),
                actionType: FakeReduxActionType.increaseCounter)
            store.dispatch(action2)

            let action3 = FakeReduxAction(
                windowUUID: UUID(),
                actionType: FakeReduxActionType.decreaseCounter)
            store.dispatch(action3)
        }
        let action = FakeReduxAction(
            windowUUID: UUID(),
            actionType: FakeReduxActionType.counterIncreased)

        store.dispatch(action)

        XCTAssertEqual(observer.receivedActions[0] as? FakeReduxActionType, FakeReduxActionType.counterIncreased)
        XCTAssertEqual(observer.receivedActions[1] as? FakeReduxActionType, FakeReduxActionType.increaseCounter)
        XCTAssertEqual(observer.receivedActions[2] as? FakeReduxActionType, FakeReduxActionType.decreaseCounter)
    }
}
