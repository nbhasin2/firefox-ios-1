// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import UIKit
import XCTest

@testable import Client

@MainActor
final class TranslationLanguagePickerViewControllerTests: XCTestCase {
    private var selectedLanguages: [String] = []

    override func setUp() async throws {
        try await super.setUp()
        DependencyHelperMock().bootstrapDependencies()
        selectedLanguages = []
    }

    override func tearDown() async throws {
        selectedLanguages = []
        DependencyHelperMock().reset()
        try await super.tearDown()
    }

    // MARK: - Init

    func test_init_setsTitle() {
        let subject = createSubject()
        XCTAssertEqual(subject.title, .Settings.Translation.LanguagePicker.NavTitle)
    }

    // MARK: - Row count

    func test_numberOfRows_withNoPreferred_equalsAllSupported() {
        let subject = createSubject(
            preferredLanguages: [],
            supportedLanguages: ["en", "fr", "de"]
        )
        subject.loadViewIfNeeded()

        XCTAssertEqual(subject.tableView(UITableView(), numberOfRowsInSection: 0), 3)
    }

    func test_numberOfRows_excludesAlreadyPreferredLanguages() {
        let subject = createSubject(
            preferredLanguages: ["en"],
            supportedLanguages: ["en", "fr", "de"]
        )
        subject.loadViewIfNeeded()

        XCTAssertEqual(subject.tableView(UITableView(), numberOfRowsInSection: 0), 2)
    }

    func test_numberOfRows_withAllLanguagesPreferred_returnsZero() {
        let subject = createSubject(
            preferredLanguages: ["en", "fr"],
            supportedLanguages: ["en", "fr"]
        )
        subject.loadViewIfNeeded()

        XCTAssertEqual(subject.tableView(UITableView(), numberOfRowsInSection: 0), 0)
    }

    // MARK: - Search filtering

    func test_updateSearchResults_withEmptyQuery_showsAllLanguages() {
        let subject = createSubject(
            preferredLanguages: [],
            supportedLanguages: ["en", "fr", "de"]
        )
        subject.loadViewIfNeeded()

        subject.updateSearchResults(for: UISearchController())

        XCTAssertEqual(subject.tableView(UITableView(), numberOfRowsInSection: 0), 3)
    }

    // MARK: - Selection

    func test_didSelectRow_reportsTheSelectedLanguage() {
        let subject = createSubject(
            preferredLanguages: [],
            supportedLanguages: ["fr", "de"]
        )
        subject.loadViewIfNeeded()

        subject.tableView(UITableView(), didSelectRowAt: IndexPath(row: 0, section: 0))

        XCTAssertEqual(selectedLanguages.count, 1)
    }

    func test_didSelectRow_afterSearchFilter_reportsTheCorrectLanguageCode() {
        let subject = createSubject(
            preferredLanguages: [],
            supportedLanguages: ["fr", "de", "es"]
        )
        subject.loadViewIfNeeded()

        let searchController = UISearchController()
        searchController.searchBar.text = "fr"
        subject.updateSearchResults(for: searchController)

        subject.tableView(UITableView(), didSelectRowAt: IndexPath(row: 0, section: 0))

        XCTAssertEqual(selectedLanguages, ["fr"])
    }

    func test_didSelectRow_deactivatesPickerSearchController() {
        let subject = createSubject(
            preferredLanguages: [],
            supportedLanguages: ["fr", "de"]
        )
        subject.loadViewIfNeeded()

        subject.tableView(UITableView(), didSelectRowAt: IndexPath(row: 0, section: 0))
        XCTAssertEqual(subject.navigationItem.searchController?.isActive, false)
    }

    // MARK: - Helpers

    private func createSubject(
        preferredLanguages: [String] = [],
        supportedLanguages: [String] = ["en", "fr"],
        localeCode: String = "en"
    ) -> TranslationLanguagePickerViewController {
        let preferred = Set(preferredLanguages)
        let available = supportedLanguages.filter { !preferred.contains($0) }
        let subject = TranslationLanguagePickerViewController(
            windowUUID: .XCTestDefaultUUID,
            languages: available,
            localeProvider: MockLocaleProvider(current: Locale(identifier: localeCode)),
            onSelectLanguage: { [weak self] code in self?.selectedLanguages.append(code) }
        )
        trackForMemoryLeaks(subject)
        return subject
    }
}
