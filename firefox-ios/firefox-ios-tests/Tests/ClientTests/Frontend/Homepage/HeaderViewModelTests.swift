// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import XCTest

@testable import Client

/// Replaces `HeaderStateTests` and `QuickAnswersMiddlewareTests`.
@MainActor
final class HeaderViewModelTests: XCTestCase {
    private var quickAnswersStore: MockQuickAnswersStore!

    override func setUp() async throws {
        try await super.setUp()
        await DependencyHelperMock().bootstrapDependencies()
        quickAnswersStore = MockQuickAnswersStore()
    }

    override func tearDown() async throws {
        quickAnswersStore = nil
        DependencyHelperMock().reset()
        try await super.tearDown()
    }

    func test_initialState_isNotPrivate() {
        let subject = createSubject()

        XCTAssertFalse(subject.state.isPrivate)
    }

    func test_refresh_withQuickAnswersEnabled_showsTheButton() {
        quickAnswersStore.isQuickAnswersEnabled = true
        let subject = createSubject()

        subject.refresh()

        XCTAssertTrue(subject.state.showQuickAnswersButton)
    }

    func test_refresh_withQuickAnswersDisabled_hidesTheButton() {
        quickAnswersStore.isQuickAnswersEnabled = false
        let subject = createSubject()

        subject.refresh()

        XCTAssertFalse(subject.state.showQuickAnswersButton)
    }

    /// The middleware recomputed on `viewWillAppear` too, which is what makes the separate
    /// `didSettingsChange` dispatch unnecessary: the setting can only change from a screen
    /// presented over the homepage.
    func test_refresh_afterTheSettingChanges_picksUpTheNewValue() {
        quickAnswersStore.isQuickAnswersEnabled = false
        let subject = createSubject()
        subject.refresh()

        quickAnswersStore.isQuickAnswersEnabled = true
        subject.refresh()

        XCTAssertTrue(subject.state.showQuickAnswersButton)
    }

    func test_refresh_withAChange_publishesOnce() {
        quickAnswersStore.isQuickAnswersEnabled = false
        let subject = createSubject()
        var changes = 0
        subject.onChange = { changes += 1 }

        quickAnswersStore.isQuickAnswersEnabled = true
        subject.refresh()

        XCTAssertEqual(changes, 1)
    }

    func test_refresh_withNoChange_doesNotPublish() {
        quickAnswersStore.isQuickAnswersEnabled = true
        let subject = createSubject()
        subject.refresh()
        var changes = 0
        subject.onChange = { changes += 1 }

        subject.refresh()

        XCTAssertEqual(changes, 0)
    }

    private func createSubject() -> HeaderViewModel {
        let subject = HeaderViewModel(windowUUID: .XCTestDefaultUUID,
                                      quickAnswersStore: quickAnswersStore)
        trackForMemoryLeaks(subject)
        return subject
    }
}
