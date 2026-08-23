// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Foundation
import Shared

protocol QuickAnswersStore {
    /// Whether the Quick Answers feature flag is enabled and the user preference for it is enabled.
    var isQuickAnswersEnabled: Bool { get }
}

/// Whether the Quick Answers entry point should be shown.
///
/// This was `QuickAnswersMiddleware`, which was already a service in all but name: `HeaderState`
/// default-constructed one as its `QuickAnswersStore` (D-015). The middleware half only translated
/// homepage lifecycle actions into an action the header's reducer consumed, which the header's
/// view model now reads directly.
final class QuickAnswersService: QuickAnswersStore {
    private let featureFlagsProvider: FeatureFlagProviding
    private let userPreferences: UserFeaturePreferring

    var isQuickAnswersEnabled: Bool {
        return featureFlagsProvider.isEnabled(.quickAnswers) && userPreferences.getPreferenceFor(.quickAnswers)
    }

    init(featureFlagsProvider: FeatureFlagProviding = AppContainer.shared.resolve(),
         userPreferences: UserFeaturePreferring = AppContainer.shared.resolve()) {
        self.featureFlagsProvider = featureFlagsProvider
        self.userPreferences = userPreferences
    }
}
