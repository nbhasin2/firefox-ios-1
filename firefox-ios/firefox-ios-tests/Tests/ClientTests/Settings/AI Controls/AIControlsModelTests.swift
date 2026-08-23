// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import XCTest
import Shared

@testable import Client

class AIControlsModelTests: XCTestCase, BusTestUtility {
    private var mockBus: MockBrowserEventBus!
    var mockPrefs: MockProfilePrefs!
    var mockProfile: MockProfile!
    var mockGleanWrapper: MockGleanWrapper!

    override func setUp() async throws {
        try await super.setUp()
        mockProfile = MockProfile(databasePrefix: "test")
        mockPrefs = MockProfilePrefs(things: [
            PrefsKeys.Summarizer.summarizeContentFeature: true,
            PrefsKeys.Settings.translationsFeature: false,
            PrefsKeys.Settings.quickAnswersFeature: true,
            PrefsKeys.Settings.aiKillSwitchFeature: true
        ], prefix: "")
        mockProfile.prefs = mockPrefs
        DependencyHelperMock().bootstrapDependencies(injectedProfile: mockProfile)
        mockGleanWrapper = MockGleanWrapper()
        setupBus()
    }

    override func tearDown() async throws {
        resetBus()
        DependencyHelperMock().reset()
        try await super.tearDown()
    }

    @MainActor
    func testHeaderLinkInfo() throws {
        let aiControlsModel = createSubject(prefs: mockPrefs)
        XCTAssertEqual(aiControlsModel.headerLinkInfo.label, "Learn more")
        let actualURL = try XCTUnwrap(aiControlsModel.headerLinkInfo.url?.absoluteString)
        let expectedURL = try XCTUnwrap(SupportUtils.URLForTopic("ios-ai-controls", useMobilePath: true)?.absoluteString)
        XCTAssertEqual(actualURL, expectedURL)
    }

    @MainActor
    func testBlockAIEnhancementsLinkInfo() throws {
        let aiControlsModel = createSubject(prefs: mockPrefs)
        XCTAssertEqual(aiControlsModel.blockAIEnhancementsLinkInfo.label, "See what is and isn’t included")
        let actualURL = try XCTUnwrap(aiControlsModel.blockAIEnhancementsLinkInfo.url?.absoluteString)
        let expectedURL = try XCTUnwrap(SupportUtils.URLForTopic("ios-ai-controls", useMobilePath: true)?.absoluteString)
        XCTAssertEqual(actualURL, expectedURL)
    }

    @MainActor
    func testHasVisibleAIFeatures() {
        setupNimbusSentFromFirefoxTesting(
            isTranslationsEnabled: true,
            isSummariesEnabled: false,
            isQuickAnswersEnabled: false
        )
        let aiControlsModel1 = createSubject(prefs: mockPrefs)
        XCTAssertTrue(aiControlsModel1.hasVisibleAIFeatures)

        setupNimbusSentFromFirefoxTesting(
            isTranslationsEnabled: false,
            isSummariesEnabled: true,
            isQuickAnswersEnabled: false
        )
        let aiControlsModel2 = createSubject(prefs: mockPrefs)
        XCTAssertTrue(aiControlsModel2.hasVisibleAIFeatures)

        setupNimbusSentFromFirefoxTesting(
            isTranslationsEnabled: false,
            isSummariesEnabled: false,
            isQuickAnswersEnabled: true
        )
        let aiControlsModel3 = createSubject(prefs: mockPrefs)
        XCTAssertTrue(aiControlsModel3.hasVisibleAIFeatures)

        setupNimbusSentFromFirefoxTesting(
            isTranslationsEnabled: false,
            isSummariesEnabled: false,
            isQuickAnswersEnabled: false
        )
        let aiControlsModel4 = createSubject(
            prefs: mockPrefs,
            summarizeFeatureEnabled: false
        )
        XCTAssertFalse(aiControlsModel4.hasVisibleAIFeatures)
    }

    @MainActor
    func testInitialize() {
        setupNimbusSentFromFirefoxTesting(
            isTranslationsEnabled: true,
            isSummariesEnabled: true,
            isQuickAnswersEnabled: true
        )
        let aiControlsModel = createSubject(prefs: mockPrefs)
        XCTAssertTrue(aiControlsModel.killSwitchIsOn)
        XCTAssertTrue(aiControlsModel.pageSummariesEnabled)
        XCTAssertFalse(aiControlsModel.translationEnabled)
        XCTAssertTrue(aiControlsModel.quickAnswersEnabled)
    }

    @MainActor
    func testInitializeWithTranslationFeatureFlagDisabled() {
        setupNimbusSentFromFirefoxTesting(
            isTranslationsEnabled: false,
            isSummariesEnabled: true,
            isQuickAnswersEnabled: true
        )
        let aiControlsModel = createSubject(prefs: mockPrefs)
        XCTAssertTrue(aiControlsModel.pageSummariesVisible)
        XCTAssertTrue(aiControlsModel.quickAnswersVisible)
        XCTAssertFalse(aiControlsModel.translationsVisible)
    }

    @MainActor
    func testInitializeWithPageSummariesFeatureFlagDisabled() {
        setupNimbusSentFromFirefoxTesting(
            isTranslationsEnabled: true,
            isSummariesEnabled: false,
            isQuickAnswersEnabled: true
        )
        let aiControlsModel = createSubject(
            prefs: mockPrefs,
            summarizeFeatureEnabled: false
        )
        XCTAssertFalse(aiControlsModel.pageSummariesVisible)
        XCTAssertTrue(aiControlsModel.translationsVisible)
        XCTAssertTrue(aiControlsModel.quickAnswersVisible)
    }

    @MainActor
    func testInitializeWithQuickAnswersFeatureFlagDisabled() {
        setupNimbusSentFromFirefoxTesting(
            isTranslationsEnabled: true,
            isSummariesEnabled: true,
            isQuickAnswersEnabled: false
        )
        let aiControlsModel = createSubject(prefs: mockPrefs)
        XCTAssertTrue(aiControlsModel.pageSummariesVisible)
        XCTAssertTrue(aiControlsModel.translationsVisible)
        XCTAssertFalse(aiControlsModel.quickAnswersVisible)
    }

    @MainActor
    func testToggleKillSwitchOn() throws {
        mockPrefs = MockProfilePrefs(things: [
            PrefsKeys.Summarizer.summarizeContentFeature: true,
            PrefsKeys.Settings.translationsFeature: true,
            PrefsKeys.Settings.aiKillSwitchFeature: false,
            PrefsKeys.Settings.quickAnswersFeature: true
        ], prefix: "")
        mockProfile.prefs = mockPrefs
        DependencyHelperMock().bootstrapDependencies(injectedProfile: mockProfile)

        let aiControlsModel = createSubject(prefs: mockPrefs)
        aiControlsModel.toggleKillSwitch(to: true)

        XCTAssertFalse(aiControlsModel.pageSummariesEnabled)
        XCTAssertFalse(aiControlsModel.translationEnabled)
        XCTAssertFalse(aiControlsModel.quickAnswersEnabled)

        if let prefVal = mockPrefs.boolForKey(PrefsKeys.Settings.aiKillSwitchFeature) {
            XCTAssertTrue(prefVal)
        } else {
            XCTFail("No pref value for AI kill switch feature")
        }

        // Each settings event gets called twice for the legacy and new change event
        XCTAssertEqual(mockGleanWrapper.recordEventCalled, 2)
    }

    @MainActor
    func testToggleKillSwitchOnWithFeaturesOffLeavesThemOff() throws {
        mockPrefs = MockProfilePrefs(things: [
            PrefsKeys.Summarizer.summarizeContentFeature: false,
            PrefsKeys.Settings.translationsFeature: false,
            PrefsKeys.Settings.quickAnswersFeature: false,
            PrefsKeys.Settings.aiKillSwitchFeature: false
        ], prefix: "")
        mockProfile.prefs = mockPrefs
        DependencyHelperMock().bootstrapDependencies(injectedProfile: mockProfile)

        let aiControlsModel = createSubject(prefs: mockPrefs)
        aiControlsModel.toggleKillSwitch(to: true)

        XCTAssertFalse(aiControlsModel.pageSummariesEnabled)
        XCTAssertFalse(aiControlsModel.translationEnabled)
        XCTAssertFalse(aiControlsModel.quickAnswersEnabled)
    }

    @MainActor
    func testToggleKillSwitchOff() throws {
        mockPrefs = MockProfilePrefs(things: [
            PrefsKeys.Summarizer.summarizeContentFeature: false,
            PrefsKeys.Settings.translationsFeature: false,
            PrefsKeys.Settings.quickAnswersFeature: false,
            PrefsKeys.Settings.aiKillSwitchFeature: true
        ], prefix: "")
        mockProfile.prefs = mockPrefs
        DependencyHelperMock().bootstrapDependencies(injectedProfile: mockProfile)

        let aiControlsModel = createSubject(prefs: mockPrefs)
        aiControlsModel.toggleKillSwitch(to: false)

        XCTAssertTrue(aiControlsModel.pageSummariesEnabled)
        XCTAssertTrue(aiControlsModel.translationEnabled)
        XCTAssertTrue(aiControlsModel.quickAnswersEnabled)

        if let prefVal = mockPrefs.boolForKey(PrefsKeys.Settings.aiKillSwitchFeature) {
            XCTAssertFalse(prefVal)
        } else {
            XCTFail("No pref value for AI kill switch feature")
        }

        // Each settings event gets called twice for the legacy and new change event
        XCTAssertEqual(mockGleanWrapper.recordEventCalled, 2)
    }

    @MainActor
    func testToggleKillSwitchOffWithFeaturesOnLeavesThemOn() throws {
        mockPrefs = MockProfilePrefs(things: [
            PrefsKeys.Summarizer.summarizeContentFeature: true,
            PrefsKeys.Settings.translationsFeature: true,
            PrefsKeys.Settings.quickAnswersFeature: true,
            PrefsKeys.Settings.aiKillSwitchFeature: true
        ], prefix: "")
        mockProfile.prefs = mockPrefs
        DependencyHelperMock().bootstrapDependencies(injectedProfile: mockProfile)

        let aiControlsModel = createSubject(prefs: mockPrefs)
        aiControlsModel.toggleKillSwitch(to: false)

        XCTAssertTrue(aiControlsModel.pageSummariesEnabled)
        XCTAssertTrue(aiControlsModel.translationEnabled)
        XCTAssertTrue(aiControlsModel.quickAnswersEnabled)
    }

    @MainActor
    func testToggleTranslationsFeature() throws {
        let translationService = MockTranslationSettingsService()
        let aiControlsModel = createSubject(prefs: mockPrefs, translationSettingsService: translationService)

        aiControlsModel.toggleTranslationsFeature(to: true)

        let call = try XCTUnwrap(translationService.setTranslationsEnabledCalls.last)
        XCTAssertTrue(call.isEnabled)
        // AI Controls records its own telemetry, so the service must not record it again.
        XCTAssertTrue(call.viaAIControls)

        // Each settings event gets called twice for the legacy and new change event
        XCTAssertEqual(mockGleanWrapper.recordEventCalled, 2)
    }

    @MainActor
    func testTogglePageSummariesFeatureOn() {
        mockPrefs = MockProfilePrefs(things: [
            PrefsKeys.Summarizer.summarizeContentFeature: false,
            PrefsKeys.Settings.translationsFeature: false,
            PrefsKeys.Settings.quickAnswersFeature: true,
            PrefsKeys.Settings.aiKillSwitchFeature: true
        ], prefix: "")
        let aiControlsModel = createSubject(prefs: mockPrefs)
        aiControlsModel.togglePageSummariesFeature(to: true)

        if let prefVal = mockPrefs.boolForKey(PrefsKeys.Summarizer.summarizeContentFeature) {
            XCTAssertTrue(prefVal)
        } else {
            XCTFail("No pref value for translations feature")
        }

        // Each settings event gets called twice for the legacy and new change event
        XCTAssertEqual(mockGleanWrapper.recordEventCalled, 2)
    }

    @MainActor
    func testTogglePageSummariesFeatureOff() {
        mockPrefs = MockProfilePrefs(things: [
            PrefsKeys.Summarizer.summarizeContentFeature: true,
            PrefsKeys.Settings.translationsFeature: false,
            PrefsKeys.Settings.quickAnswersFeature: true,
            PrefsKeys.Settings.aiKillSwitchFeature: true
        ], prefix: "")
        let aiControlsModel = createSubject(prefs: mockPrefs)
        aiControlsModel.togglePageSummariesFeature(to: false)

        if let prefVal = mockPrefs.boolForKey(PrefsKeys.Summarizer.summarizeContentFeature) {
            XCTAssertFalse(prefVal)
        } else {
            XCTFail("No pref value for translations feature")
        }

        // Each settings event gets called twice for the legacy and new change event
        XCTAssertEqual(mockGleanWrapper.recordEventCalled, 2)
    }

    @MainActor
    func testToggleQuickAnswersFeatureOn() {
        let aiControlsModel = createSubject(prefs: mockPrefs)
        aiControlsModel.toggleQuickAnswersFeature(to: true)

        if let prefVal = mockPrefs.boolForKey(PrefsKeys.Settings.quickAnswersFeature) {
            XCTAssertTrue(prefVal)
        } else {
            XCTFail("No pref value for translations feature")
        }

        // Each settings event gets called twice for the legacy and new change event
        XCTAssertEqual(mockGleanWrapper.recordEventCalled, 2)
    }

    @MainActor
    func testToggleQuickAnswersFeatureOff() {
        let aiControlsModel = createSubject(prefs: mockPrefs)
        aiControlsModel.toggleQuickAnswersFeature(to: false)

        if let prefVal = mockPrefs.boolForKey(PrefsKeys.Settings.quickAnswersFeature) {
            XCTAssertFalse(prefVal)
        } else {
            XCTFail("No pref value for translations feature")
        }

        // Each settings event gets called twice for the legacy and new change event
        XCTAssertEqual(mockGleanWrapper.recordEventCalled, 2)
    }

    private func setupNimbusSentFromFirefoxTesting(
        isTranslationsEnabled: Bool,
        isSummariesEnabled: Bool,
        isQuickAnswersEnabled: Bool
    ) {
        FxNimbus.shared.features.translationsFeature.with { _, _ in
            return TranslationsFeature(enabled: isTranslationsEnabled)
        }

        FxNimbus.shared.features.hostedSummarizerFeature.with { _, _ in
            return HostedSummarizerFeature(enabled: isSummariesEnabled)
        }

        FxNimbus.shared.features.quickAnswersFeature.with { _, _ in
            return QuickAnswersFeature(enabled: isQuickAnswersEnabled)
        }
    }

    @MainActor
    private func createSubject(prefs: Prefs,
                               summarizeFeatureEnabled: Bool = true,
                               translationSettingsService: TranslationSettingsServicing? = nil) -> AIControlsModel {
        // Always inject a stub: the real service resolves remote-settings singletons that the
        // Redux middleware never touched under test, because `middlewares` is empty in unit tests.
        let translationService = translationSettingsService ?? MockTranslationSettingsService()
        let summarizeFeatureDefaultValue = prefs.boolForKey(
            PrefsKeys.Summarizer.summarizeContentFeature
        ) ?? true
        let subject = AIControlsModel(
            prefs: prefs,
            windowUUID: .XCTestDefaultUUID,
            summarizerConfiguration: MockNimbusUtils(
                summarizeFeatureToggledOn: summarizeFeatureDefaultValue,
                summarizeFeatureEnabled: summarizeFeatureEnabled
            ),
            settingsTelemetry: SettingsTelemetry(gleanWrapper: mockGleanWrapper),
            translationSettingsService: translationService
        )
        trackForMemoryLeaks(subject)
        return subject
    }

    func setupBus() {
        mockBus = MockBrowserEventBus()
        BusTestUtilityHelper.setupBus(with: mockBus)
    }

    func resetBus() {
        BusTestUtilityHelper.resetBus()
    }
}
