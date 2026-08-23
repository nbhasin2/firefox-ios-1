// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import XCTest

@testable import Redux

/// The round trip the bus exists for: a view dispatches a command, a service hears it, does the
/// work and announces the result, and whoever is watching hears the announcement.
///
/// This replaced a state-tree test — a view controller subscribed to `FakeReduxState` and asserted
/// on the value the reducer produced. There is no state in the store to subscribe to now, so what
/// is verified is the delivery: that the follow-up action arrives, in order, after the command.
@MainActor
final class ReduxIntegrationTests: XCTestCase {
    let initialCountValue = 8

    private var store: BrowserEventBus!
    private var handler: FakeReduxActionHandler!
    private var observer: MockActionObserver!

    override func setUp() async throws {
        try await super.setUp()

        store = BrowserEventBus()
        observer = MockActionObserver()
        handler = FakeReduxActionHandler()
        handler.generateInitialCountValue = { [initialCountValue] in initialCountValue }

        // The observer stands in for a view model: `.state` tier, so it is told before the service.
        observer.observe(store, tier: .state)
        handler.register(on: store)
    }

    override func tearDown() async throws {
        store = nil
        handler = nil
        observer = nil
        try await super.tearDown()
    }

    // MARK: - Legacy actions

    func testDispatchStore_IncreaseCounter() {
        store.dispatch(action(.increaseCounter))

        XCTAssertEqual(handler.counter, 1)
        XCTAssertEqual(observer.receivedActions.compactMap { $0 as? FakeReduxActionType },
                       [.increaseCounter, .counterIncreased])
    }

    func testDispatchStore_DecreaseCounter() {
        store.dispatch(action(.decreaseCounter))

        XCTAssertEqual(handler.counter, -1)
        XCTAssertEqual(observer.receivedActions.compactMap { $0 as? FakeReduxActionType },
                       [.decreaseCounter, .counterDecreased])
    }

    func testDispatchStore_RequestInitialValue() {
        store.dispatch(action(.requestInitialValue))

        XCTAssertEqual(handler.counter, initialCountValue)
        XCTAssertEqual(observer.receivedActions.compactMap { $0 as? FakeReduxActionType },
                       [.requestInitialValue, .initialValueLoaded])
    }

    func testDispatchStore_SetPrivateMode() {
        store.dispatch(FakeReduxAction(privateMode: true,
                                       windowUUID: windowUUID,
                                       actionType: FakeReduxActionType.setPrivateModeTo))

        XCTAssertTrue(handler.isInPrivateMode)
    }

    /// The queue: the follow-up the service dispatches mid-delivery lands after the action that
    /// caused it, not interleaved with it.
    func testDispatchStore_MultipleCommands_areDeliveredInOrder() {
        store.dispatch(action(.increaseCounter))
        store.dispatch(action(.increaseCounter))

        XCTAssertEqual(handler.counter, 2)
        XCTAssertEqual(observer.receivedActions.compactMap { $0 as? FakeReduxActionType },
                       [.increaseCounter, .counterIncreased, .increaseCounter, .counterIncreased])
    }

    // MARK: - Modern actions

    func testDispatchStore_IncreaseCounter_modernAction() {
        store.dispatch(FakeReduxModernAction.increaseCounter, forWindowUUID: windowUUID)

        XCTAssertEqual(handler.counter, 1)
        XCTAssertEqual(observer.receivedModernActions.compactMap { $0.0 as? FakeReduxModernAction },
                       [.increaseCounter, .counterIncreased(counterValue: 1)])
    }

    func testDispatchStore_DecreaseCounter_modernAction() {
        store.dispatch(FakeReduxModernAction.decreaseCounter, forWindowUUID: windowUUID)

        XCTAssertEqual(handler.counter, -1)
        XCTAssertEqual(observer.receivedModernActions.compactMap { $0.0 as? FakeReduxModernAction },
                       [.decreaseCounter, .counterDecreased(counterValue: -1)])
    }

    func testDispatchStore_SetPrivateMode_modernAction() {
        store.dispatch(FakeReduxModernAction.setPrivateModeTo(isPrivate: true), forWindowUUID: windowUUID)

        XCTAssertTrue(handler.isInPrivateMode)
    }

    func testDispatchStore_modernAction_carriesItsWindow() throws {
        store.dispatch(FakeReduxModernAction.increaseCounter, forWindowUUID: windowUUID)

        let received = try XCTUnwrap(observer.receivedModernActions.first)
        XCTAssertEqual(received.1, windowUUID)
    }

    // MARK: - Helpers

    private func action(_ type: FakeReduxActionType) -> FakeReduxAction {
        return FakeReduxAction(windowUUID: windowUUID, actionType: type)
    }
}
