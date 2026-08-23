// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Storage
import XCTest

@testable import Client

/// Replaces `TopSitesSectionStateTests`.
@MainActor
final class TopSitesSectionViewModelTests: XCTestCase {
    private var topSitesManager: MockTopSitesManager!
    private var notificationCenter: MockNotificationCenter!

    override func setUp() async throws {
        try await super.setUp()
        await DependencyHelperMock().bootstrapDependencies()
        topSitesManager = MockTopSitesManager()
        notificationCenter = MockNotificationCenter()
    }

    override func tearDown() async throws {
        topSitesManager = nil
        notificationCenter = nil
        DependencyHelperMock().reset()
        try await super.tearDown()
    }

    // MARK: - Sites

    func test_retrievedSites_populatesTheSection() async {
        let service = createService()
        let subject = createSubject(service: service)

        service.refresh(for: .XCTestDefaultUUID)
        await waitForSites(subject)

        XCTAssertEqual(subject.state.topSitesData.count, 30)
    }

    func test_retrievedSites_withOverflow_showsTheSectionHeader() async {
        let service = createService()
        let subject = createSubject(service: service)
        subject.setNumberOfRows(1)
        subject.setNumberOfTilesPerRow(4)

        service.refresh(for: .XCTestDefaultUUID)
        await waitForSites(subject)

        XCTAssertTrue(subject.state.shouldShowSectionHeader)
    }

    func test_retrievedSites_withinTheVisibleGrid_hidesTheSectionHeader() async {
        let service = createService(siteCount: 4)
        let subject = createSubject(service: service)
        subject.setNumberOfRows(2)
        subject.setNumberOfTilesPerRow(4)

        service.refresh(for: .XCTestDefaultUUID)
        await waitForSites(subject)

        XCTAssertFalse(subject.state.shouldShowSectionHeader)
    }

    func test_retrievedSites_publishesTheChange() async {
        let service = createService()
        let subject = createSubject(service: service)
        var changes = 0
        subject.onChange = { changes += 1 }

        service.refresh(for: .XCTestDefaultUUID)
        await waitForSites(subject)

        XCTAssertEqual(changes, 1)
    }

    // MARK: - Settings

    func test_setNumberOfRows_recomputesTheSectionHeader() async {
        let service = createService(siteCount: 8)
        let subject = createSubject(service: service)
        subject.setNumberOfTilesPerRow(4)
        service.refresh(for: .XCTestDefaultUUID)
        await waitForSites(subject)

        subject.setNumberOfRows(1)

        XCTAssertEqual(subject.state.numberOfRows, 1)
        XCTAssertTrue(subject.state.shouldShowSectionHeader)
    }

    func test_setSectionEnabled_false_hidesTheSection() {
        let subject = createSubject(service: createService())

        subject.setSectionEnabled(false)

        XCTAssertFalse(subject.state.shouldShowSection)
    }

    func test_setNumberOfTilesPerRow_withTheSameValue_doesNotPublish() {
        let subject = createSubject(service: createService())
        subject.setNumberOfTilesPerRow(4)
        var changes = 0
        subject.onChange = { changes += 1 }

        subject.setNumberOfTilesPerRow(4)

        XCTAssertEqual(changes, 0)
    }

    // MARK: - Private Helpers

    private func waitForSites(_ subject: TopSitesSectionViewModel) async {
        await waitUntil { !subject.state.topSitesData.isEmpty }
    }

    private func createService(siteCount: Int = 30) -> TopSitesService {
        topSitesManager.siteCount = siteCount
        return TopSitesService(topSitesManager: topSitesManager)
    }

    private func createSubject(service: TopSitesService) -> TopSitesSectionViewModel {
        let subject = TopSitesSectionViewModel(
            windowUUID: .XCTestDefaultUUID,
            profile: MockProfile(),
            topSitesService: service,
            featureFlagsProvider: MockNimbusFeatureFlags(),
            notificationCenter: notificationCenter
        )
        trackForMemoryLeaks(subject)
        return subject
    }
}
