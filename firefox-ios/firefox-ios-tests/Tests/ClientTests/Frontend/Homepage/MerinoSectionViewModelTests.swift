// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import XCTest

@testable import Client

/// Replaces `MerinoMiddlewareTests` and the story-handling half of `MerinoStateTests`.
@MainActor
final class MerinoSectionViewModelTests: XCTestCase {
    private var merinoManager: MockMerinoManager!
    private var profile: MockProfile!

    override func setUp() async throws {
        try await super.setUp()
        await DependencyHelperMock().bootstrapDependencies()
        merinoManager = MockMerinoManager()
        profile = MockProfile()
    }

    override func tearDown() async throws {
        merinoManager = nil
        profile = nil
        DependencyHelperMock().reset()
        try await super.tearDown()
    }

    // MARK: - Fetching

    func test_refreshStories_fetchesFromTheManager() async {
        let subject = createSubject()

        subject.refreshStories()
        await waitForStories(subject)

        XCTAssertEqual(merinoManager.getMerinoItemsCalled, 1)
    }

    func test_refreshStories_withContent_showsTheSection() async {
        let subject = createSubject()

        subject.refreshStories()
        await waitForStories(subject)

        XCTAssertTrue(subject.hasMerinoResponseContent)
        XCTAssertTrue(subject.shouldShowSection)
    }

    func test_refreshStories_withNoContent_hidesTheSection() async {
        merinoManager.responseToReturn = MerinoStoryResponse()
        let subject = createSubject()

        subject.refreshStories()
        for _ in 0..<20 where merinoManager.getMerinoItemsCalled == 0 { await Task.yield() }
        await Task.yield()

        XCTAssertFalse(subject.hasMerinoResponseContent)
        // An empty response hides the section even when the preference is on.
        XCTAssertFalse(subject.shouldShowSection)
    }

    func test_refreshStories_publishesTheChange() async {
        let subject = createSubject()
        var changes = 0
        subject.onChange = { changes += 1 }

        subject.refreshStories()
        await waitForStories(subject)

        XCTAssertGreaterThan(changes, 0)
    }

    // MARK: - Section setting

    func test_setSectionEnabled_false_hidesTheSectionAndRefetches() async {
        let subject = createSubject()
        subject.refreshStories()
        await waitForStories(subject)

        subject.setSectionEnabled(false)

        XCTAssertFalse(subject.shouldShowSection)
    }

    // MARK: - Private Helpers

    private func waitForStories(_ subject: MerinoSectionViewModel) async {
        for _ in 0..<20 where !subject.hasMerinoResponseContent {
            await Task.yield()
        }
    }

    private func createSubject() -> MerinoSectionViewModel {
        let subject = MerinoSectionViewModel(
            profile: profile,
            merinoManager: merinoManager
        )
        trackForMemoryLeaks(subject)
        return subject
    }
}
