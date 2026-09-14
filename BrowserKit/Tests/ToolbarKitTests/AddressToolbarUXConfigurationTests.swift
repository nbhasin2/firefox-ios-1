// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Common
import Testing
import UIKit

@testable import ToolbarKit

@MainActor
@Suite
struct AddressToolbarUXConfigurationTests {
    private let alphaValues: [CGFloat] = [1.0, 0.85]
    private let boolValues = [false, true]

    // The corner radius of `.experiment` is not passed by the factory, so it falls back
    // to the stored property default, which forks on the OS version.
    private var expectedExperimentCornerRadius: CGFloat {
        if #available(iOS 26, *) {
            return 22
        } else {
            return 12
        }
    }

    // MARK: - Pinned defaults

    @Test
    func test_default_pinsCurrentValues() {
        let subject = AddressToolbarUXConfiguration.default()

        #expect(subject.toolbarCornerRadius == 8.0)
        #expect(subject.browserActionsAddressBarDividerWidth == 4.0)
        #expect(subject.isLocationTextCentered == false)
        #expect(subject.locationTextFieldTrailingPadding == 8.0)
        #expect(subject.shouldBlur == false)
        #expect(subject.backgroundAlpha == 1.0)
        #expect(subject.isAddressBarMinimized == false)
        #expect(subject.hasAlternativeLocationColor == false)
    }

    @Test
    func test_experiment_pinsCurrentValues() {
        let subject = AddressToolbarUXConfiguration.experiment()

        #expect(subject.toolbarCornerRadius == expectedExperimentCornerRadius)
        #expect(subject.browserActionsAddressBarDividerWidth == 0.0)
        #expect(subject.isLocationTextCentered == true)
        #expect(subject.locationTextFieldTrailingPadding == 0)
        #expect(subject.shouldBlur == false)
        #expect(subject.backgroundAlpha == 1.0)
        #expect(subject.isAddressBarMinimized == false)
        #expect(subject.hasAlternativeLocationColor == false)
    }

    // MARK: - Parameter round trip

    @Test
    func test_default_parametersRoundTripOntoMatchingFields() {
        let subject = AddressToolbarUXConfiguration.default(
            backgroundAlpha: 0.85,
            isAddressBarMinimized: true,
            shouldBlur: true,
            hasAlternativeLocationColor: true
        )

        #expect(subject.backgroundAlpha == 0.85)
        #expect(subject.isAddressBarMinimized == true)
        #expect(subject.shouldBlur == true)
        #expect(subject.hasAlternativeLocationColor == true)
    }

    @Test
    func test_experiment_parametersRoundTripOntoMatchingFields() {
        let subject = AddressToolbarUXConfiguration.experiment(
            backgroundAlpha: 0.85,
            isAddressBarMinimized: true,
            shouldBlur: true,
            hasAlternativeLocationColor: true
        )

        #expect(subject.backgroundAlpha == 0.85)
        #expect(subject.isAddressBarMinimized == true)
        #expect(subject.shouldBlur == true)
        #expect(subject.hasAlternativeLocationColor == true)
    }

    // MARK: - Style fixed fields are invariant under every parameter combination

    @Test
    func test_default_styleFixedFieldsAreInvariantAcrossAllParameterCombinations() {
        for alpha in alphaValues {
            for isMinimized in boolValues {
                for shouldBlur in boolValues {
                    for hasAlternativeLocationColor in boolValues {
                        let subject = AddressToolbarUXConfiguration.default(
                            backgroundAlpha: alpha,
                            isAddressBarMinimized: isMinimized,
                            shouldBlur: shouldBlur,
                            hasAlternativeLocationColor: hasAlternativeLocationColor
                        )

                        #expect(subject.toolbarCornerRadius == 8.0)
                        #expect(subject.browserActionsAddressBarDividerWidth == 4.0)
                        #expect(subject.isLocationTextCentered == false)
                        #expect(subject.locationTextFieldTrailingPadding == 8.0)
                    }
                }
            }
        }
    }

    @Test
    func test_experiment_styleFixedFieldsAreInvariantAcrossAllParameterCombinations() {
        for alpha in alphaValues {
            for isMinimized in boolValues {
                for shouldBlur in boolValues {
                    for hasAlternativeLocationColor in boolValues {
                        let subject = AddressToolbarUXConfiguration.experiment(
                            backgroundAlpha: alpha,
                            isAddressBarMinimized: isMinimized,
                            shouldBlur: shouldBlur,
                            hasAlternativeLocationColor: hasAlternativeLocationColor
                        )

                        #expect(subject.toolbarCornerRadius == expectedExperimentCornerRadius)
                        #expect(subject.browserActionsAddressBarDividerWidth == 0.0)
                        #expect(subject.isLocationTextCentered == true)
                        #expect(subject.locationTextFieldTrailingPadding == 0)
                    }
                }
            }
        }
    }

    // MARK: - Location view vertical paddings

    @Test
    func test_locationViewVerticalPaddings_areEightOnBothPositions() {
        for subject in [AddressToolbarUXConfiguration.default(), AddressToolbarUXConfiguration.experiment()] {
            let top = subject.locationViewVerticalPaddings(addressBarPosition: .top)
            let bottom = subject.locationViewVerticalPaddings(addressBarPosition: .bottom)

            #expect(top.top == 8)
            #expect(top.bottom == 8)
            #expect(bottom.top == 8)
            #expect(bottom.bottom == 8)
        }
    }

    // MARK: - Colors

    @Test
    func test_locationContainerBackgroundColor_whenAddressBarMinimized_isClear() {
        let theme = LightTheme()
        let defaultSubject = AddressToolbarUXConfiguration.default(isAddressBarMinimized: true)
        let experimentSubject = AddressToolbarUXConfiguration.experiment(isAddressBarMinimized: true)

        #expect(defaultSubject.locationContainerBackgroundColor(theme: theme) == UIColor.clear)
        #expect(experimentSubject.locationContainerBackgroundColor(theme: theme) == UIColor.clear)
    }

    @Test
    func test_locationContainerBackgroundColor_whenNotMinimized_isNotClear() {
        let theme = LightTheme()
        let defaultSubject = AddressToolbarUXConfiguration.default()
        let experimentSubject = AddressToolbarUXConfiguration.experiment()

        #expect(defaultSubject.locationContainerBackgroundColor(theme: theme) != UIColor.clear)
        #expect(experimentSubject.locationContainerBackgroundColor(theme: theme) != UIColor.clear)
    }

    @Test
    func test_addressToolbarBackgroundColor_whenShouldBlurIsFalse_keepsFullAlpha() {
        let theme = LightTheme()
        let defaultSubject = AddressToolbarUXConfiguration.default(backgroundAlpha: 0.85, shouldBlur: false)
        let experimentSubject = AddressToolbarUXConfiguration.experiment(backgroundAlpha: 0.85, shouldBlur: false)

        #expect(isAlpha(of: defaultSubject.addressToolbarBackgroundColor(theme: theme), equalTo: 1.0))
        #expect(isAlpha(of: experimentSubject.addressToolbarBackgroundColor(theme: theme), equalTo: 1.0))
    }

    @Test
    func test_addressToolbarBackgroundColor_whenShouldBlurIsTrue_appliesBackgroundAlpha() {
        let theme = LightTheme()
        let defaultSubject = AddressToolbarUXConfiguration.default(backgroundAlpha: 0.85, shouldBlur: true)
        let experimentSubject = AddressToolbarUXConfiguration.experiment(backgroundAlpha: 0.85, shouldBlur: true)

        #expect(isAlpha(of: defaultSubject.addressToolbarBackgroundColor(theme: theme), equalTo: 0.85))
        #expect(isAlpha(of: experimentSubject.addressToolbarBackgroundColor(theme: theme), equalTo: 0.85))
    }

    // MARK: - Helpers

    private func isAlpha(of color: UIColor, equalTo expected: CGFloat) -> Bool {
        return abs(color.cgColor.alpha - expected) < 0.0001
    }
}
