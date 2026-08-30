import SwiftUI

struct NilePanelModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(NileColors.panel)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(NileColors.border, lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.035), radius: 3, y: 2)
    }
}
struct NileGlassModifier: ViewModifier {
    let cornerRadius: CGFloat
    let interactive: Bool
    let tint: Color?

    func body(content: Content) -> some View {
        content
            .background(tint ?? NileColors.panel)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(
                    cornerRadius: cornerRadius,
                    style: .continuous
                )
                .strokeBorder(NileColors.border, lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.04), radius: 3, y: 2)
    }
}

struct NileGlassButtonModifier: ViewModifier {
    let prominent: Bool

    func body(content: Content) -> some View {
        content
            .buttonStyle(NileReferenceButtonStyle(prominent: prominent))
    }
}

struct NileGlassIconButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .buttonStyle(NileReferenceButtonStyle(prominent: false))
            .clipShape(RoundedRectangle(cornerRadius: NileRadii.control))
    }
}

private struct NileReferenceButtonStyle: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(
                prominent ? NileColors.onAccent : NileColors.text
            )
            .background(
                prominent
                    ? NileColors.accentStrong
                    : (configuration.isPressed
                        ? NileColors.surfaceHover
                        : NileColors.panel)
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: NileRadii.control,
                    style: .continuous
                )
            )
            .overlay {
                if !prominent {
                    RoundedRectangle(
                        cornerRadius: NileRadii.control,
                        style: .continuous
                    )
                    .strokeBorder(NileColors.borderStrong, lineWidth: 1)
                }
            }
            .shadow(color: Color.black.opacity(0.05), radius: 1, y: 1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct NileTextButtonStyle: ButtonStyle {
    var prominent = false
    var destructive = false
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(NileTypography.bodyMedium.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .frame(minHeight: 40)
            .background(background(configuration.isPressed))
            .clipShape(RoundedRectangle(cornerRadius: NileRadii.control))
            .overlay {
                if !prominent && !destructive {
                    RoundedRectangle(cornerRadius: NileRadii.control)
                        .strokeBorder(NileColors.borderStrong, lineWidth: 1)
                }
            }
            .opacity(isEnabled ? 1 : 0.45)
    }
    private var foreground: Color {
        prominent || destructive ? NileColors.onAccent : NileColors.text
    }
    private func background(_ pressed: Bool) -> Color {
        if destructive { return NileColors.error }
        if prominent { return NileColors.accentStrong }
        return pressed ? NileColors.surfaceHover : NileColors.panel
    }
}
struct NilePixelGrid: View {
    let color: Color
    let shifted: Bool
    var squareSize: CGFloat = 6

    var body: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.fixed(squareSize), spacing: 3),
                count: 3
            ),
            spacing: 3
        ) {
            ForEach(0..<9, id: \.self) { index in
                RoundedRectangle(cornerRadius: squareSize * 0.2)
                    .fill(
                        index == (shifted ? 2 : 6)
                            ? color
                            : NileColors.faint.opacity(
                                index.isMultiple(of: 2) ? 0.5 : 0.25
                            )
                    )
                    .frame(width: squareSize, height: squareSize)
            }
        }
        .frame(
            width: squareSize * 3 + 6,
            height: squareSize * 3 + 6
        )
    }
}

struct NileTextStyleModifier: ViewModifier {
    let style: NileTypography.TextStyle

    func body(content: Content) -> some View {
        let extraLeading = style.additionalLineSpacing
        content
            .font(style.font)
            .tracking(style.renderedTracking)
            .lineSpacing(extraLeading)
    }
}


extension View {
    func nilePanel(
        cornerRadius: CGFloat = NileRadii.card
    ) -> some View {
        modifier(NilePanelModifier(cornerRadius: cornerRadius))
    }

    func nileTextStyle(_ style: NileTypography.TextStyle) -> some View {
        modifier(NileTextStyleModifier(style: style))
    }

    func nileGlass(
        cornerRadius: CGFloat = NileRadii.sheet,
        interactive: Bool = false,
        tint: Color? = nil
    ) -> some View {
        modifier(
            NileGlassModifier(
                cornerRadius: cornerRadius,
                interactive: interactive,
                tint: tint
            )
        )
    }

    func nileGlassButton(prominent: Bool = false) -> some View {
        modifier(NileGlassButtonModifier(prominent: prominent))
    }

    func nileGlassIconButton() -> some View {
        modifier(NileGlassIconButtonModifier())
    }
}
