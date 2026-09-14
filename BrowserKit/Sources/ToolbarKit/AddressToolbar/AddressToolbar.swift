// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import UIKit

/// Protocol representing an address toolbar.
///
/// Inherits `UIView` so a host can lay out, transform and theme a toolbar without naming a
/// concrete implementation. This is what allows more than one address bar UI to exist: a host
/// holds `any AddressToolbar` and the choice of implementation is made where it is built.
@MainActor
public protocol AddressToolbar: UIView, ThemeApplicable {
    /// Whether the unified search experience is active. Setting this re-configures the
    /// location view against the toolbar's current configuration.
    var isUnifiedSearchEnabled: Bool { get set }

    func configure(config: AddressToolbarConfiguration,
                   toolbarPosition: AddressToolbarPosition,
                   toolbarDelegate: any AddressToolbarDelegate,
                   leadingSpace: CGFloat,
                   trailingSpace: CGFloat,
                   isUnifiedSearchEnabled: Bool,
                   animated: Bool)

    /// Configures a toolbar that is displayed but never interacted with, such as the
    /// placeholder bars shown either side of the address bar while swiping between tabs.
    func configureNonInteractive(config: AddressToolbarConfiguration,
                                 leadingSpace: CGFloat,
                                 trailingSpace: CGFloat)

    func setAutocompleteSuggestion(_ suggestion: String?)
}
