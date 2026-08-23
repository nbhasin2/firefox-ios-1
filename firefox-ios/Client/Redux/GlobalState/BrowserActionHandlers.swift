// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import Redux

// In order for us to mock and test the services easier,
// we change the store to be instantiated as a variable.
// For non testing builds, we leave the store as a constant.
#if TESTING
@MainActor
var store: any DefaultDispatchStore = Store()
#else
@MainActor
let store: any DefaultDispatchStore = Store()
#endif

/// The six services that were middlewares. None of them has a screen or a state — each reacts to
/// browser events and performs work or announces another event, which is what the bus is for
/// (D-016). They register on the `.effects` tier — the middleware position — because several of
/// them read state a view model owns, and they keep the relative order the middleware array had
/// them in, because some react to what an earlier one dispatches.
///
/// Held for the app's lifetime: the store keeps observers weakly.
@MainActor
final class BrowserActionHandlers {
    static let shared = BrowserActionHandlers()

    private let microsurveyPrompt = MicrosurveyPromptActionHandler()
    private let tabManager = TabManagerActionHandler()
    private let toolbar = ToolbarActionHandler()
    private let startAtHome = StartAtHomeActionHandler()
    private let summarizer = SummarizerActionHandler()
    private let translations = TranslationsActionHandler()

    private var isRegistered = false

    func register(on bus: any ActionObserving = store) {
        guard !isRegistered else { return }
        isRegistered = true

        bus.addActionObserver(microsurveyPrompt, tier: .effects) { [microsurveyPrompt] in microsurveyPrompt.handle($0) }
        bus.addActionObserver(tabManager, tier: .effects) { [tabManager] in tabManager.handle($0) }
        bus.addActionObserver(toolbar, tier: .effects) { [toolbar] in toolbar.handle($0) }
        bus.addActionObserver(startAtHome, tier: .effects) { [startAtHome] in startAtHome.handle($0) }
        bus.addActionObserver(summarizer, tier: .effects) { [summarizer] in summarizer.handle($0) }
        bus.addActionObserver(translations, tier: .effects) { [translations] in translations.handle($0) }
    }
}
