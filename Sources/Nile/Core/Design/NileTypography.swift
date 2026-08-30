import SwiftUI

enum NileTypography {
    static let bodyLarge = font(size: 14, relativeTo: .body)
    static let bodyMedium = font(size: 13, relativeTo: .subheadline)
    static let bodySmall = font(size: 11, relativeTo: .caption)
    static let labelMedium = font(
        size: 10,
        weight: .medium,
        relativeTo: .caption
    )
    static let titleLarge = font(
        size: 21,
        weight: .semibold,
        relativeTo: .title2
    )
    static let titleMedium = font(
        size: 14,
        weight: .semibold,
        relativeTo: .headline
    )

    static let bodyLargeStyle = TextStyle(
        font: bodyLarge,
        postScriptName: "Roboto-Regular",
        uiTextStyle: .body,
        fontSize: 14,
        rendererWeight: 400,
        targetLineHeight: 14 * 1.38,
        rendererTrackingCorrection: 0.025
    )
    static let bodyMediumStyle = TextStyle(
        font: bodyMedium,
        postScriptName: "Roboto-Regular",
        uiTextStyle: .body,
        fontSize: 13,
        rendererWeight: 400,
        targetLineHeight: 13 * 1.42,
        rendererTrackingCorrection: 0.025
    )
    static let bodyMediumSemiboldStyle = TextStyle(
        font: font(size: 13, weight: .semibold, relativeTo: .body),
        postScriptName: "Roboto-SemiBold",
        uiTextStyle: .body,
        fontSize: 13,
        rendererWeight: 600,
        targetLineHeight: 13 * 1.42,
        rendererTrackingCorrection: 0.025
    )
    static let monospaceBodyMediumStyle = TextStyle(
        font: .custom(
            "DroidSansMono",
            size: 13,
            relativeTo: .body
        ),
        postScriptName: "DroidSansMono",
        fontResourceName: "DroidSansMono",
        uiTextStyle: .body,
        fontSize: 13,
        rendererWeight: 400,
        targetLineHeight: 13 * 1.42
    )
    static let monospaceBodySmall = Font.custom(
        "DroidSansMono",
        size: 11,
        relativeTo: .caption
    )
    static let bodySmallStyle = TextStyle(
        font: bodySmall,
        postScriptName: "Roboto-Regular",
        uiTextStyle: .caption1,
        fontSize: 11,
        rendererWeight: 400,
        targetLineHeight: 11 * 1.4,
        rendererTrackingCorrection: 0.03
    )
    static let bodySmallMediumStyle = TextStyle(
        font: font(size: 11, weight: .medium, relativeTo: .caption),
        postScriptName: "Roboto-Medium",
        uiTextStyle: .caption1,
        fontSize: 11,
        rendererWeight: 500,
        targetLineHeight: 11 * 1.4,
        rendererTrackingCorrection: 0.03
    )
    static let materialLabelSmallStyle = TextStyle(
        font: font(size: 11, weight: .medium, relativeTo: .caption),
        postScriptName: "Roboto-Medium",
        uiTextStyle: .caption1,
        fontSize: 11,
        rendererWeight: 500,
        targetLineHeight: 16,
        tracking: 0.5,
        rendererLetterSpacing: .points(0.5)
    )
    static let labelMediumStyle = TextStyle(
        font: labelMedium,
        postScriptName: "Roboto-Medium",
        uiTextStyle: .caption2,
        fontSize: 10,
        rendererWeight: 500,
        tracking: 10 * 0.01,
        rendererLetterSpacing: .em(0.01),
        rendererTrackingCorrection: 0.025
    )
    static let titleLargeStyle = TextStyle(
        font: titleLarge,
        postScriptName: "Roboto-Medium",
        uiTextStyle: .title3,
        fontSize: 20,
        rendererWeight: 500,
        tracking: 20 * -0.015,
        rendererLetterSpacing: .em(-0.015),
        rendererTrackingCorrection: 0.05
    )
    static let titleLargeSemiboldStyle = TextStyle(
        font: font(size: 20, weight: .semibold, relativeTo: .title3),
        postScriptName: "Roboto-SemiBold",
        uiTextStyle: .title3,
        fontSize: 20,
        rendererWeight: 600,
        tracking: 20 * -0.015,
        rendererLetterSpacing: .em(-0.015),
        rendererTrackingCorrection: 0.05
    )
    static let titleMediumStyle = TextStyle(
        font: titleMedium,
        postScriptName: "Roboto-Medium",
        uiTextStyle: .headline,
        fontSize: 14,
        rendererWeight: 500,
        tracking: 14 * -0.01,
        rendererLetterSpacing: .em(-0.01),
        rendererTrackingCorrection: 0.05
    )
    static let markdownHeadingLargeStyle = TextStyle(
        font: font(size: 19, weight: .bold, relativeTo: .title3),
        postScriptName: "Roboto-Bold",
        uiTextStyle: .title3,
        fontSize: 19,
        rendererWeight: 700,
        minimumSingleLineHeight: 23.67
    )
    static let markdownHeadingMediumStyle = TextStyle(
        font: font(size: 17, weight: .bold, relativeTo: .headline),
        postScriptName: "Roboto-Bold",
        uiTextStyle: .headline,
        fontSize: 17,
        rendererWeight: 700,
        minimumSingleLineHeight: 23.67
    )
    static let markdownHeadingSmallStyle = TextStyle(
        font: font(size: 15, weight: .bold, relativeTo: .headline),
        postScriptName: "Roboto-Bold",
        uiTextStyle: .headline,
        fontSize: 15,
        rendererWeight: 700,
        minimumSingleLineHeight: 23.67
    )
    static let materialLabelLargeStyle = TextStyle(
        font: font(size: 14, weight: .medium, relativeTo: .body),
        postScriptName: "Roboto-Medium",
        uiTextStyle: .body,
        fontSize: 14,
        rendererWeight: 500,
        targetLineHeight: 20,
        tracking: 0.1,
        rendererLetterSpacing: .points(0.1),
        rendererTrackingCorrection: 0.04
    )
    static let brandStyle = TextStyle(
        font: font(size: 10, weight: .semibold),
        postScriptName: "Roboto-SemiBold",
        uiTextStyle: .caption2,
        fontSize: 10,
        rendererWeight: 600,
        tracking: 1.4,
        rendererLetterSpacing: .points(1.4)
    )

    static func font(
        size: CGFloat,
        weight: Font.Weight = .regular,
        relativeTo textStyle: Font.TextStyle = .body
    ) -> Font {
        .system(textStyle, design: .default, weight: weight)
    }
}
