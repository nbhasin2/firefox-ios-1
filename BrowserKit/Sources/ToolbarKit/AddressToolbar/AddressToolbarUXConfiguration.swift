// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import UIKit

public struct AddressToolbarUXConfiguration {
    let style: AddressToolbarStyle
    private(set) var toolbarCornerRadius: CGFloat
    let browserActionsAddressBarDividerWidth: CGFloat
    let isLocationTextCentered: Bool
    let hasAlternativeLocationColor: Bool
    let locationTextFieldTrailingPadding: CGFloat
    let shouldBlur: Bool
    let backgroundAlpha: CGFloat
    let isAddressBarMinimized: Bool

    private init(style: AddressToolbarStyle,
                 backgroundAlpha: CGFloat,
                 isAddressBarMinimized: Bool,
                 shouldBlur: Bool,
                 hasAlternativeLocationColor: Bool) {
        self.style = style
        self.toolbarCornerRadius = style.toolbarCornerRadius
        self.browserActionsAddressBarDividerWidth = style.browserActionsAddressBarDividerWidth
        self.isLocationTextCentered = style.isLocationTextCentered
        self.locationTextFieldTrailingPadding = style.locationTextFieldTrailingPadding
        self.hasAlternativeLocationColor = hasAlternativeLocationColor
        self.shouldBlur = shouldBlur
        self.backgroundAlpha = backgroundAlpha
        self.isAddressBarMinimized = isAddressBarMinimized
    }

    public static func make(style: AddressToolbarStyle,
                            backgroundAlpha: CGFloat = 1.0,
                            isAddressBarMinimized: Bool = false,
                            shouldBlur: Bool = false,
                            hasAlternativeLocationColor: Bool = false) -> AddressToolbarUXConfiguration {
        AddressToolbarUXConfiguration(style: style,
                                      backgroundAlpha: backgroundAlpha,
                                      isAddressBarMinimized: isAddressBarMinimized,
                                      shouldBlur: shouldBlur,
                                      hasAlternativeLocationColor: hasAlternativeLocationColor)
    }

    public static func experiment(backgroundAlpha: CGFloat = 1.0,
                                  isAddressBarMinimized: Bool = false,
                                  shouldBlur: Bool = false,
                                  hasAlternativeLocationColor: Bool = false) -> AddressToolbarUXConfiguration {
        make(style: .standard,
             backgroundAlpha: backgroundAlpha,
             isAddressBarMinimized: isAddressBarMinimized,
             shouldBlur: shouldBlur,
             hasAlternativeLocationColor: hasAlternativeLocationColor)
    }

    public static func `default`(backgroundAlpha: CGFloat = 1.0,
                                 isAddressBarMinimized: Bool = false,
                                 shouldBlur: Bool = false,
                                 hasAlternativeLocationColor: Bool = false) -> AddressToolbarUXConfiguration {
        make(style: .legacy,
             backgroundAlpha: backgroundAlpha,
             isAddressBarMinimized: isAddressBarMinimized,
             shouldBlur: shouldBlur,
             hasAlternativeLocationColor: hasAlternativeLocationColor)
    }

    func addressToolbarBackgroundColor(theme: some Theme) -> UIColor {
        let backgroundColor = isLocationTextCentered ? theme.colors.layerSurfaceLow : theme.colors.layer1
        if shouldBlur {
            return backgroundColor.withAlphaComponent(backgroundAlpha)
        }

        return backgroundColor
    }

    func locationContainerBackgroundColor(theme: some Theme) -> UIColor {
        guard !isAddressBarMinimized else { return .clear }

        let alternativeLocationColor = theme.isNova ? theme.colors.layerSurfaceMedium : theme.colors.layerSurfaceMediumAlt

        if hasAlternativeLocationColor {
            return isLocationTextCentered ? alternativeLocationColor : theme.colors.layerEmphasis
        } else {
            return isLocationTextCentered ? theme.colors.layerSurfaceMedium : theme.colors.layerEmphasis
        }
    }

    public func locationViewVerticalPaddings(addressBarPosition: AddressToolbarPosition) -> (top: CGFloat, bottom: CGFloat) {
        return switch addressBarPosition {
        case .top:
            (top: 8, bottom: 8)
        case .bottom:
            (top: 8, bottom: 8)
        }
    }
}
