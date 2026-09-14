// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import UIKit

/// The visual variant of the address toolbar. A style only carries values that are fixed for that
/// variant; values that change at runtime stay parameters on `AddressToolbarUXConfiguration`.
public enum AddressToolbarStyle {
    case standard
    case legacy
    /// Resolves to the same values as `.standard`; a later task gives it its own values.
    case liquidGlass

    var toolbarCornerRadius: CGFloat {
        switch self {
        case .standard, .liquidGlass:
            return if #available(iOS 26, *) { 22 } else { 12 }
        case .legacy:
            return 8.0
        }
    }

    var browserActionsAddressBarDividerWidth: CGFloat {
        switch self {
        case .standard, .liquidGlass:
            return 0.0
        case .legacy:
            return 4.0
        }
    }

    var isLocationTextCentered: Bool {
        switch self {
        case .standard, .liquidGlass:
            return true
        case .legacy:
            return false
        }
    }

    var locationTextFieldTrailingPadding: CGFloat {
        switch self {
        case .standard, .liquidGlass:
            return 0
        case .legacy:
            return 8.0
        }
    }
}
