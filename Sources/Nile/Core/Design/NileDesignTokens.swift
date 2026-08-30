import SwiftUI
import UIKit

enum NileColors {
    // Beautiful UI's sampled semantic palette.
    static let background = adaptive(light: 0xFAFAFB, dark: 0x17181A)
    static let canvas = adaptive(light: 0xF1F2F3, dark: 0x1C1D1F)
    static let panel = adaptive(light: 0xFFFFFF, dark: 0x232427)
    static let panelAlt = adaptive(light: 0xF2F2F3, dark: 0x2B2C2F)
    static let inset = adaptive(light: 0xF7F8F9, dark: 0x1F2022)
    static let border = adaptive(light: 0xECEDEF, dark: 0x2E3033)
    static let borderStrong = adaptive(light: 0xE0E2E5, dark: 0x3A3C40)
    static let text = adaptive(light: 0x1F2124, dark: 0xF2F3F4)
    static let prose = text
    static let proseStrong = text
    static let muted = adaptive(light: 0x62656B, dark: 0xA5A8AD)
    static let faint = adaptive(light: 0x9A9DA3, dark: 0x6C6F75)
    static let accent = adaptive(light: 0x0285FF, dark: 0x3D9AFF)
    static let accentStrong = accent
    static let accentInk = adaptive(light: 0x0170DD, dark: 0x7EC0FF)
    static let accentSoft = adaptive(light: 0xE9F3FF, dark: 0x202D3A)
    static let onAccent = Color.white
    static let link = accentInk
    static let agent = link
    static let warning = adaptive(light: 0xEF720C, dark: 0xF68F3C)
    static let needsInputSurface = adaptive(light: 0xFFF3E9, dark: 0x382A20)
    static let error = adaptive(light: 0xE3474C, dark: 0xEE5C61)
    static let surfaceRaised = panel
    static let surfaceSelected = accentSoft
    static let surfaceHover = adaptive(light: 0xF4F5F6, dark: 0x2A2B2E)
    static let surfaceHighest = adaptive(light: 0xE7E9EB, dark: 0x313236)
    static let complete = adaptive(light: 0x189A4D, dark: 0x3DBB72)
    static let stopped = warning
    static let chartBlue = accent
    static let chartGreen = complete
    static let chartPurple = adaptive(light: 0x7655C9, dark: 0xA98DFF)
    static let chartRed = error
    static let chartOrange = warning
    static let chartCyan = adaptive(light: 0x168B9C, dark: 0x53C4D4)
    static let chartYellow = adaptive(light: 0xA87909, dark: 0xE7BA4D)
    static let chartPink = adaptive(light: 0xC54586, dark: 0xF27AB6)
    static let syntaxKeyword = link
    static let syntaxString = Color(uiColor: .systemGreen)
    static let syntaxValue = Color(uiColor: .systemPink)
    static let syntaxComment = faint

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
    }
}
enum NileRadii {
    static let small: CGFloat = 8
    static let control: CGFloat = 8
    static let card: CGFloat = 10
    static let window: CGFloat = 14
    static let sheet: CGFloat = 14
    static let pill: CGFloat = 999
}

enum NileMotion {
    static let quick = Duration.milliseconds(150)
    static let standard = Duration.milliseconds(240)
    static let emphasis = Duration.milliseconds(900)
    static let shimmer = Duration.milliseconds(1_200)
}

enum NileTactilePressFeedback {
    static let pressedScale: CGFloat = 0.96
    static let pressedOpacity = 0.9
    static let reducedMotionPressedOpacity = 0.76

    static func scale(
        isPressed: Bool,
        reduceMotion: Bool
    ) -> CGFloat {
        isPressed && !reduceMotion ? pressedScale : 1
    }

    static func opacity(
        isPressed: Bool,
        reduceMotion: Bool
    ) -> Double {
        guard isPressed else {
            return 1
        }
        return reduceMotion
            ? reducedMotionPressedOpacity
            : pressedOpacity
    }
}

struct NileTactileButtonStyle: ButtonStyle {
    @Environment(\.nileReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(
                NileTactilePressFeedback.scale(
                    isPressed: configuration.isPressed,
                    reduceMotion: reduceMotion
                )
            )
            .opacity(
                NileTactilePressFeedback.opacity(
                    isPressed: configuration.isPressed,
                    reduceMotion: reduceMotion
                )
            )
            .animation(
                reduceMotion
                    ? nil
                    : .spring(
                        response: 0.18,
                        dampingFraction: 0.82,
                        blendDuration: 0.02
                    ),
                value: configuration.isPressed
            )
    }
}

private struct NileReduceMotionEnvironmentKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var nileReduceMotion: Bool {
        get { self[NileReduceMotionEnvironmentKey.self] }
        set { self[NileReduceMotionEnvironmentKey.self] = newValue }
    }
}
extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}
