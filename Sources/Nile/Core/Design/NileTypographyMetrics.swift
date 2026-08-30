import SwiftUI
import UIKit

/// Immutable typography measurement metadata and the UIKit Dynamic Type bridge.
/// Visual role declarations remain in `NileTypography`.
extension NileTypography {
    struct TextStyle {
        enum RendererLetterSpacing {
            case none
            case em(Float)
            case points(Float)
        }

        let font: Font
        let postScriptName: String
        let fontResourceName: String
        let uiTextStyle: UIFont.TextStyle
        let fontSize: CGFloat
        let rendererWeight: Float
        let targetLineHeight: CGFloat?
        let minimumSingleLineHeight: CGFloat?
        let tracking: CGFloat
        let rendererLetterSpacing: RendererLetterSpacing
        let rendererTrackingCorrection: CGFloat

        init(
            font: Font,
            postScriptName: String,
            fontResourceName: String = "Roboto-Regular",
            uiTextStyle: UIFont.TextStyle,
            fontSize: CGFloat,
            rendererWeight: Float,
            targetLineHeight: CGFloat? = nil,
            minimumSingleLineHeight: CGFloat? = nil,
            tracking: CGFloat = 0,
            rendererLetterSpacing: RendererLetterSpacing = .none,
            rendererTrackingCorrection: CGFloat = 0
        ) {
            self.font = font
            self.postScriptName = postScriptName
            self.fontResourceName = fontResourceName
            self.uiTextStyle = uiTextStyle
            self.fontSize = fontSize
            self.rendererWeight = rendererWeight
            self.targetLineHeight = targetLineHeight
            self.minimumSingleLineHeight = minimumSingleLineHeight
            self.tracking = tracking
            self.rendererLetterSpacing = rendererLetterSpacing
            self.rendererTrackingCorrection =
                rendererTrackingCorrection
        }

        var additionalLineSpacing: CGFloat {
            0
        }

        var renderedTracking: CGFloat {
            0
        }

        func scaledUIFont(
            for dynamicTypeSize: DynamicTypeSize
        ) -> UIFont {
            let baseFont = UIFont.systemFont(
                ofSize: fontSize,
                weight: uiFontWeight
            )
            let traits = UITraitCollection(
                preferredContentSizeCategory:
                    dynamicTypeSize.uiContentSizeCategory
            )
            return UIFontMetrics(
                forTextStyle: uiTextStyle
            ).scaledFont(for: baseFont, compatibleWith: traits)
        }
    }
}

private extension NileTypography.TextStyle {
    var uiFontWeight: UIFont.Weight {
        switch rendererWeight {
        case 700...:
            .bold
        case 600...:
            .semibold
        case 500...:
            .medium
        default:
            .regular
        }
    }
}

extension DynamicTypeSize {
    var uiContentSizeCategory: UIContentSizeCategory {
        switch self {
        case .xSmall:
            return .extraSmall
        case .small:
            return .small
        case .medium:
            return .medium
        case .large:
            return .large
        case .xLarge:
            return .extraLarge
        case .xxLarge:
            return .extraExtraLarge
        case .xxxLarge:
            return .extraExtraExtraLarge
        case .accessibility1:
            return .accessibilityMedium
        case .accessibility2:
            return .accessibilityLarge
        case .accessibility3:
            return .accessibilityExtraLarge
        case .accessibility4:
            return .accessibilityExtraExtraLarge
        case .accessibility5:
            return .accessibilityExtraExtraExtraLarge
        @unknown default:
            return .large
        }
    }
}
