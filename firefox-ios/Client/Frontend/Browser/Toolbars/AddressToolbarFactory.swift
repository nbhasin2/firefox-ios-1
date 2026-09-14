// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import ToolbarKit

/// Which address bar UI to build.
enum AddressToolbarVariant {
    case standard
    case liquidGlass
}

/// Builds the address toolbar. This is the only place that decides which address bar UI the
/// app runs, so no toolbar implementation needs to know whether it is the selected one.
@MainActor
protocol AddressToolbarFactory {
    var variant: AddressToolbarVariant { get }

    func makeAddressToolbar() -> any AddressToolbar
}

@MainActor
struct DefaultAddressToolbarFactory: AddressToolbarFactory {
    private let featureFlagsProvider: FeatureFlagProviding

    init(featureFlagsProvider: FeatureFlagProviding = AppContainer.shared.resolve()) {
        self.featureFlagsProvider = featureFlagsProvider
    }

    var variant: AddressToolbarVariant {
        if #available(iOS 26.0, *), featureFlagsProvider.isEnabled(.liquidGlassAddressBar) {
            return .liquidGlass
        }
        return .standard
    }

    func makeAddressToolbar() -> any AddressToolbar {
        switch variant {
        case .standard, .liquidGlass:
            // The Liquid Glass toolbar does not exist yet, so every variant builds the
            // standard bar and the flag cannot change what the user sees. Adding it is a
            // new case here and nothing above this function changes.
            let toolbar: RegularBrowserAddressToolbar = .build()
            return toolbar
        }
    }
}
