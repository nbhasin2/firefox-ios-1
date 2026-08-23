// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import XCTest

@testable import Client

/// Replaces `PasswordGeneratorStateTests` and covers what `PasswordGeneratorMiddleware`
/// did without tests: generation, caching per origin, and filling the field.
@MainActor
final class PasswordGeneratorViewModelTests: XCTestCase {
    private var evaluator: MockPasswordGeneratorScriptEvaluator!
    private var storage: MockGeneratedPasswordStorage!
    private var rulesProvider: MockPasswordRulesProvider!

    override func setUp() async throws {
        try await super.setUp()
        await DependencyHelperMock().bootstrapDependencies()
        evaluator = MockPasswordGeneratorScriptEvaluator()
        storage = MockGeneratedPasswordStorage()
        rulesProvider = MockPasswordRulesProvider()
    }

    override func tearDown() async throws {
        evaluator = nil
        storage = nil
        rulesProvider = nil
        DependencyHelperMock().reset()
        try await super.tearDown()
    }

    // MARK: - Showing the sheet

    func test_showPasswordGenerator_generatesAndStoresAPassword() async {
        evaluator.resultToReturn = "generated-password"
        let subject = createSubject()

        await subject.showPasswordGenerator()

        XCTAssertEqual(subject.state.password, "generated-password")
        XCTAssertEqual(storage.getPasswordForOrigin(origin: "https://example.com"), "generated-password")
        XCTAssertEqual(evaluator.evaluateScriptCalled, 1)
    }

    func test_showPasswordGenerator_reusesTheStoredPasswordForTheOrigin() async {
        storage.setPasswordForOrigin(origin: "https://example.com", password: "already-generated")
        let subject = createSubject()

        await subject.showPasswordGenerator()

        XCTAssertEqual(subject.state.password, "already-generated")
        XCTAssertEqual(evaluator.evaluateScriptCalled, 0, "Expected no second generation for a known origin")
    }

    func test_showPasswordGenerator_withoutAnOrigin_doesNothing() async {
        let subject = createSubject(origin: nil)

        await subject.showPasswordGenerator()

        XCTAssertEqual(subject.state.password, "")
        XCTAssertEqual(evaluator.evaluateScriptCalled, 0)
    }

    func test_showPasswordGenerator_appliesTheSiteSpecificRule() async {
        rulesProvider.ruleToReturn = "{\"domain\":\"example.com\"}"
        evaluator.resultToReturn = "pw"
        let subject = createSubject()

        await subject.showPasswordGenerator()

        XCTAssertEqual(rulesProvider.requestedHosts, ["example.com"])
        XCTAssertEqual(
            evaluator.lastEvaluatedScript,
            "window.__firefox__.logins.generatePassword({\"domain\":\"example.com\"})"
        )
    }

    func test_showPasswordGenerator_withoutASiteRule_callsTheDefaultGenerator() async {
        evaluator.resultToReturn = "pw"
        let subject = createSubject()

        await subject.showPasswordGenerator()

        XCTAssertEqual(evaluator.lastEvaluatedScript, "window.__firefox__.logins.generatePassword()")
    }

    func test_showPasswordGenerator_whenJavascriptFails_leavesTheDraftEmpty() async {
        evaluator.errorToReturn = TestError.evaluation
        let subject = createSubject()

        await subject.showPasswordGenerator()

        XCTAssertEqual(subject.state.password, "")
        XCTAssertNil(storage.getPasswordForOrigin(origin: "https://example.com"))
    }

    // MARK: - Refresh

    func test_refreshPassword_replacesTheStoredPassword() async {
        storage.setPasswordForOrigin(origin: "https://example.com", password: "old")
        evaluator.resultToReturn = "new"
        let subject = createSubject()

        await subject.refreshPassword()

        XCTAssertEqual(subject.state.password, "new")
        XCTAssertEqual(storage.getPasswordForOrigin(origin: "https://example.com"), "new")
    }

    // MARK: - Use password

    func test_usePassword_fillsTheFieldWithAJSONEscapedPassword() async {
        evaluator.resultToReturn = "pa\"ss"
        let subject = createSubject()
        await subject.showPasswordGenerator()

        await subject.usePassword()

        XCTAssertEqual(
            evaluator.lastEvaluatedScript,
            "window.__firefox__.logins.fillGeneratedPassword(\"pa\\\"ss\")"
        )
    }

    // MARK: - Visibility

    func test_hideAndShowPassword_togglesTheDraft() {
        let subject = createSubject()

        subject.hidePassword()
        XCTAssertTrue(subject.state.passwordHidden)

        subject.showPassword()
        XCTAssertFalse(subject.state.passwordHidden)
    }

    // MARK: - State publishing

    func test_onStateChange_firesWhenThePasswordArrives() async {
        evaluator.resultToReturn = "generated"
        let subject = createSubject()
        var received: [PasswordGeneratorState] = []
        subject.onStateChange = { received.append($0) }

        await subject.showPasswordGenerator()

        XCTAssertEqual(received.map(\.password), ["generated"])
    }

    func test_onStateChange_doesNotFireWhenNothingChanged() {
        let subject = createSubject()
        var callCount = 0
        subject.onStateChange = { _ in callCount += 1 }

        subject.showPassword()

        XCTAssertEqual(callCount, 0, "Expected no notification when the value is unchanged")
    }

    // MARK: - Private Helpers

    private enum TestError: Error {
        case evaluation
    }

    private func createSubject(origin: String? = "https://example.com") -> PasswordGeneratorViewModel {
        let frameContext = PasswordGeneratorFrameContext(
            origin: origin,
            host: "example.com",
            scriptEvaluator: evaluator,
            frameInfo: nil
        )
        let subject = PasswordGeneratorViewModel(
            frameContext: frameContext,
            generatedPasswordStorage: storage,
            rulesProvider: rulesProvider
        )
        trackForMemoryLeaks(subject)
        return subject
    }
}

final class MockGeneratedPasswordStorage: GeneratedPasswordStorageProtocol {
    private var originToPassword: [String: String] = [:]

    func setPasswordForOrigin(origin: String, password: String) {
        originToPassword[origin] = password
    }

    func deletePasswordForOrigin(origin: String) {
        originToPassword[origin] = nil
    }

    func getPasswordForOrigin(origin: String) -> String? {
        return originToPassword[origin]
    }
}

@MainActor
final class MockPasswordRulesProvider: PasswordRulesProviding {
    var ruleToReturn: String?
    var requestedHosts: [String] = []

    func rule(for host: String) async -> String? {
        requestedHosts.append(host)
        return ruleToReturn
    }
}
