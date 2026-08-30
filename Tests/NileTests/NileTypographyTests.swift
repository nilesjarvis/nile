import UIKit
import XCTest
@testable import Nile

final class NileTypographyTests: XCTestCase {
    func testAndroidRobotoVariableFontRegistersAllUsedWeights() {
        for postScriptName in [
            "Roboto-Regular",
            "Roboto-Medium",
            "Roboto-SemiBold",
            "Roboto-Bold",
        ] {
            let font = UIFont(name: postScriptName, size: 14)
            XCTAssertNotNil(
                font,
                "Missing embedded Android font instance \(postScriptName)"
            )
            XCTAssertEqual(font?.familyName, "Roboto")
        }
    }

    func testTypographyUsesNativeSpacingWithoutComposeCorrections() {
        let styles = [
            NileTypography.bodyLargeStyle,
            NileTypography.bodyMediumStyle,
            NileTypography.bodySmallStyle,
            NileTypography.labelMediumStyle,
            NileTypography.titleLargeStyle,
            NileTypography.titleMediumStyle,
            NileTypography.materialLabelLargeStyle,
        ]

        for style in styles {
            XCTAssertEqual(style.additionalLineSpacing, 0)
            XCTAssertEqual(style.renderedTracking, 0)
        }
    }

    func testBodyMediumResolvedFontUsesDeclaredSizeAtDefaultDynamicType() {
        let style = NileTypography.bodyMediumStyle
        let resolved = style.scaledUIFont(for: .large)

        XCTAssertEqual(style.fontSize, 13)
        XCTAssertEqual(resolved.pointSize, style.fontSize, accuracy: 0.001)
    }
}
