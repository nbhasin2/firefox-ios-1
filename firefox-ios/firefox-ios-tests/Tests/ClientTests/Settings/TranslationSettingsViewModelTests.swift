// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import XCTest

@testable import Client

/// Replaces `TranslationSettingsStateTests` and the screen half of
/// `TranslationSettingsMiddlewareTests`. The effects live in `TranslationSettingsService`, so this
/// asserts state transitions and that the service is asked for the right thing.
@MainActor
final class TranslationSettingsViewModelTests: XCTestCase {
    private var service: MockTranslationSettingsService!

    override func setUp() async throws {
        try await super.setUp()
        await DependencyHelperMock().bootstrapDependencies()
        service = MockTranslationSettingsService()
    }

    override func tearDown() async throws {
        service = nil
        DependencyHelperMock().reset()
        try await super.tearDown()
    }

    // MARK: - Loading

    func test_viewDidLoad_showsPrefsBackedTogglesImmediately() {
        service.toggles = (isTranslationsEnabled: false, isAutoTranslateEnabled: true)
        let subject = createSubject()

        subject.viewDidLoad()

        // The language lists need remote settings; the toggles must not wait for them.
        XCTAssertFalse(subject.state.isTranslationsEnabled)
        XCTAssertTrue(subject.state.isAutoTranslateEnabled)
    }

    func test_viewDidLoad_appliesTheLoadedSnapshot() async {
        service.snapshot = TranslationSettingsSnapshot(
            isTranslationsEnabled: true,
            isAutoTranslateEnabled: false,
            preferredLanguages: [makeLanguage("fr")],
            supportedLanguages: ["fr", "de"],
            availableLanguages: ["de"]
        )
        let subject = createSubject()

        subject.viewDidLoad()
        await waitForLoad(subject)

        XCTAssertEqual(subject.state.preferredLanguages.map(\.code), ["fr"])
        XCTAssertEqual(subject.state.supportedLanguages, ["fr", "de"])
        XCTAssertEqual(subject.state.availableLanguages, ["de"])
    }

    // MARK: - Toggles

    func test_toggleTranslationsEnabled_flipsAndTellsTheService() {
        service.toggles = (isTranslationsEnabled: true, isAutoTranslateEnabled: false)
        let subject = createSubject()
        subject.viewDidLoad()

        subject.toggleTranslationsEnabled()

        XCTAssertFalse(subject.state.isTranslationsEnabled)
        XCTAssertEqual(service.setTranslationsEnabledCalls.map(\.isEnabled), [false])
        XCTAssertEqual(service.setTranslationsEnabledCalls.map(\.viaAIControls), [false])
    }

    func test_toggleTranslationsEnabled_withExplicitValue_usesIt() {
        let subject = createSubject()

        subject.toggleTranslationsEnabled(newValue: false, toggledViaAIControls: true)

        XCTAssertFalse(subject.state.isTranslationsEnabled)
        XCTAssertEqual(service.setTranslationsEnabledCalls.map(\.viaAIControls), [true])
    }

    func test_toggleAutoTranslate_takesTheServicesNewValue() {
        service.autoTranslateAfterToggle = true
        let subject = createSubject()

        subject.toggleAutoTranslate()

        XCTAssertTrue(subject.state.isAutoTranslateEnabled)
        XCTAssertEqual(service.toggleAutoTranslateCallCount, 1)
    }

    // MARK: - Languages

    func test_addLanguage_updatesPreferredAndAvailable() {
        service.addLanguageResult = ([makeLanguage("fr"), makeLanguage("de")], ["es"])
        let subject = createSubject()

        subject.addLanguage(code: "de")

        XCTAssertEqual(service.addedLanguages, ["de"])
        XCTAssertEqual(subject.state.preferredLanguages.map(\.code), ["fr", "de"])
        XCTAssertEqual(subject.state.availableLanguages, ["es"])
    }

    func test_saveLanguages_updatesPreferredAndAvailable() {
        service.saveResult = ([makeLanguage("de")], ["fr", "es"])
        let subject = createSubject()

        subject.saveLanguages(["de"])

        XCTAssertEqual(service.savedLanguages, [["de"]])
        XCTAssertEqual(subject.state.preferredLanguages.map(\.code), ["de"])
    }

    // MARK: - Edit mode

    func test_enterEditMode_seedsPendingFromPreferred() {
        service.snapshot = TranslationSettingsSnapshot(
            isTranslationsEnabled: true,
            isAutoTranslateEnabled: false,
            preferredLanguages: [makeLanguage("fr"), makeLanguage("de")],
            supportedLanguages: [],
            availableLanguages: []
        )
        let subject = createSubject()
        subject.saveLanguages([])
        service.saveResult = ([makeLanguage("fr"), makeLanguage("de")], [])
        subject.saveLanguages(["fr", "de"])

        subject.enterEditMode()

        XCTAssertTrue(subject.state.isEditing)
        XCTAssertEqual(subject.state.pendingLanguages?.map(\.code), ["fr", "de"])
    }

    func test_cancelEditMode_clearsPending() {
        let subject = createSubject()
        subject.enterEditMode()

        subject.cancelEditMode()

        XCTAssertFalse(subject.state.isEditing)
        XCTAssertNil(subject.state.pendingLanguages)
    }

    func test_reorderLanguages_storesTheNewOrderAsPending() {
        let subject = createSubject()
        let reordered = [makeLanguage("de"), makeLanguage("fr")]

        subject.reorderLanguages(reordered)

        XCTAssertEqual(subject.state.pendingLanguages?.map(\.code), ["de", "fr"])
    }

    func test_removeLanguage_dropsItFromPending() {
        let subject = createSubject()
        subject.reorderLanguages([makeLanguage("fr"), makeLanguage("de")])

        subject.removeLanguage(code: "fr")

        XCTAssertEqual(subject.state.pendingLanguages?.map(\.code), ["de"])
    }

    // MARK: - Publishing

    func test_onStateChange_doesNotFireWhenNothingChanged() {
        let subject = createSubject()
        subject.enterEditMode()
        var callCount = 0
        subject.onStateChange = { _ in callCount += 1 }

        subject.enterEditMode()

        XCTAssertEqual(callCount, 0)
    }

    // MARK: - Private Helpers

    private func makeLanguage(_ code: String) -> PreferredLanguageDetails {
        return PreferredLanguageDetails(code: code, mainText: code, subtitleText: nil)
    }

    /// `viewDidLoad` kicks off a detached load; yield until it lands.
    private func waitForLoad(_ subject: TranslationSettingsViewModel) async {
        for _ in 0..<10 where subject.state.supportedLanguages.isEmpty {
            await Task.yield()
        }
    }

    private func createSubject() -> TranslationSettingsViewModel {
        let subject = TranslationSettingsViewModel(service: service)
        trackForMemoryLeaks(subject)
        return subject
    }
}

@MainActor
final class MockTranslationSettingsService: TranslationSettingsServicing {
    var toggles: (isTranslationsEnabled: Bool, isAutoTranslateEnabled: Bool) = (true, false)
    var snapshot = TranslationSettingsSnapshot(
        isTranslationsEnabled: true,
        isAutoTranslateEnabled: false,
        preferredLanguages: [],
        supportedLanguages: [],
        availableLanguages: []
    )
    var autoTranslateAfterToggle = false
    var addLanguageResult: ([PreferredLanguageDetails], [String]) = ([], [])
    var saveResult: ([PreferredLanguageDetails], [String]) = ([], [])

    private(set) var setTranslationsEnabledCalls: [(isEnabled: Bool, viaAIControls: Bool)] = []
    private(set) var toggleAutoTranslateCallCount = 0
    private(set) var addedLanguages: [String] = []
    private(set) var savedLanguages: [[String]] = []

    func currentToggles() -> (isTranslationsEnabled: Bool, isAutoTranslateEnabled: Bool) {
        return toggles
    }

    func loadSettings() async -> TranslationSettingsSnapshot {
        return snapshot
    }

    func setTranslationsEnabled(_ isEnabled: Bool, toggledViaAIControls: Bool) {
        setTranslationsEnabledCalls.append((isEnabled, toggledViaAIControls))
    }

    func toggleAutoTranslate() -> Bool {
        toggleAutoTranslateCallCount += 1
        return autoTranslateAfterToggle
    }

    func addLanguage(_ code: String,
                     supportedLanguages: [String]) -> (preferred: [PreferredLanguageDetails],
                                                       available: [String]) {
        addedLanguages.append(code)
        return addLanguageResult
    }

    func save(languages: [String],
              supportedLanguages: [String]) -> (preferred: [PreferredLanguageDetails],
                                                available: [String]) {
        savedLanguages.append(languages)
        return saveResult
    }
}
