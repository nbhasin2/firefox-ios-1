// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import XCTest

@testable import Client

/// Replaces `MessageCardMiddlewareTests` and `MessageCardStateTests`.
@MainActor
final class MessageCardViewModelTests: XCTestCase {
    private var messagingManager: MockGleanPlumbMessageManagerProtocol!

    override func setUp() {
        super.setUp()
        DependencyHelperMock().bootstrapDependencies()
        messagingManager = MockGleanPlumbMessageManagerProtocol()
    }

    override func tearDown() {
        messagingManager = nil
        DependencyHelperMock().reset()
        super.tearDown()
    }

    // MARK: - Loading

    func test_viewDidLoad_withAMessage_publishesTheConfiguration() {
        let message = createMessage()
        messagingManager.message = message
        let subject = createSubject()
        var received: [MessageCardConfiguration?] = []
        subject.onConfigurationChange = { received.append($0) }

        subject.viewDidLoad()

        XCTAssertEqual(subject.configuration?.title, message.title)
        XCTAssertEqual(subject.configuration?.description, message.text)
        XCTAssertEqual(subject.configuration?.buttonLabel, message.buttonLabel)
        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(messagingManager.onMessageDisplayedCalled, 1)
    }

    func test_viewDidLoad_withNoMessage_publishesNothing() {
        messagingManager.message = nil
        let subject = createSubject()

        subject.viewDidLoad()

        XCTAssertNil(subject.configuration)
        XCTAssertEqual(messagingManager.onMessageDisplayedCalled, 0)
    }

    // MARK: - Interaction

    func test_tappedOnActionButton_pressesTheMessageAndDismissesTheCard() {
        messagingManager.message = createMessage()
        let subject = createSubject()
        subject.viewDidLoad()

        subject.tappedOnActionButton()

        XCTAssertEqual(messagingManager.onMessagePressedCalled, 1)
        // Dismissing the card is what clearing the configuration used to mean.
        XCTAssertNil(subject.configuration)
    }

    func test_tappedOnCloseButton_dismissesTheMessageAndTheCard() {
        messagingManager.message = createMessage()
        let subject = createSubject()
        subject.viewDidLoad()

        subject.tappedOnCloseButton()

        XCTAssertEqual(messagingManager.onMessageDismissedCalled, 1)
        XCTAssertNil(subject.configuration)
    }

    func test_tapWithoutAMessage_doesNothing() {
        messagingManager.message = nil
        let subject = createSubject()
        subject.viewDidLoad()

        subject.tappedOnActionButton()
        subject.tappedOnCloseButton()

        XCTAssertEqual(messagingManager.onMessagePressedCalled, 0)
        XCTAssertEqual(messagingManager.onMessageDismissedCalled, 0)
    }

    // MARK: - Private Helpers

    /// The mock only returns a message whose surface matches the requested one.
    private func createMessage() -> GleanPlumbMessage {
        let metadata = GleanPlumbMessageMetaData(id: "",
                                                 impressions: 0,
                                                 dismissals: 0,
                                                 isExpired: false)
        return GleanPlumbMessage(id: "12345",
                                 data: MockMessageData(surface: .newTabCard),
                                 action: "",
                                 triggerIfAll: [],
                                 exceptIfAny: [],
                                 style: MockStyleDataProtocol(),
                                 metadata: metadata)
    }

    private func createSubject() -> MessageCardViewModel {
        let subject = MessageCardViewModel(
            windowUUID: .XCTestDefaultUUID,
            messagingManager: messagingManager
        )
        trackForMemoryLeaks(subject)
        return subject
    }
}
