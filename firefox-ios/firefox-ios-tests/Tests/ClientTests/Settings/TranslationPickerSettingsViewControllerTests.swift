// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import UIKit
import XCTest

@testable import Client

@MainActor
final class TranslationPickerSettingsViewControllerTests: XCTestCase {
    private var service: MockTranslationSettingsService!

    override func setUp() async throws {
        try await super.setUp()
        DependencyHelperMock().bootstrapDependencies()
        service = MockTranslationSettingsService()
    }

    override func tearDown() async throws {
        service = nil
        DependencyHelperMock().reset()
        try await super.tearDown()
    }

    // MARK: - Init

    func test_init_setsTitle() {
        let subject = createSubject().viewController
        XCTAssertEqual(subject.title, .Settings.Translation.Title)
    }

    // MARK: - Rendering

    func test_render_withTranslationsEnabled_doesNotCrash() {
        let (subject, viewModel) = createSubject()
        subject.loadViewIfNeeded()
        service.saveResult = (
            [
                PreferredLanguageDetails(code: "en", mainText: "English", subtitleText: "Device Language"),
                PreferredLanguageDetails(code: "fr", mainText: "français", subtitleText: "French")
            ],
            ["de"]
        )

        viewModel.saveLanguages(["en", "fr"])
    }

    func test_render_withTranslationsDisabled_doesNotCrash() {
        let (subject, viewModel) = createSubject()
        subject.loadViewIfNeeded()

        viewModel.toggleTranslationsEnabled(newValue: false)

        XCTAssertFalse(viewModel.state.isTranslationsEnabled)
    }

    // MARK: - collectionView delegate

    func test_shouldSelectItem_returnsFalse() {
        let subject = createSubject().viewController
        subject.loadViewIfNeeded()
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let result = subject.collectionView(collectionView, shouldSelectItemAt: IndexPath(item: 0, section: 0))
        XCTAssertFalse(result)
    }

    // MARK: - Helpers

    private func createSubject() -> (viewController: TranslationPickerSettingsViewController,
                                     viewModel: TranslationSettingsViewModel) {
        let viewModel = TranslationSettingsViewModel(service: service)
        let subject = TranslationPickerSettingsViewController(
            windowUUID: .XCTestDefaultUUID,
            viewModel: viewModel
        )
        trackForMemoryLeaks(subject)
        return (subject, viewModel)
    }
}
