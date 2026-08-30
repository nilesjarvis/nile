import SwiftUI

struct ModelPickerText: View {
    let text: String
    let style: NileTypography.TextStyle
    let color: Color
    let background: Color
    let fillsWidth: Bool

    init(
        _ text: String,
        style: NileTypography.TextStyle,
        color: Color,
        background: Color,
        fillsWidth: Bool = false
    ) {
        self.text = text
        self.style = style
        self.color = color
        self.background = background
        self.fillsWidth = fillsWidth
    }

    var body: some View {
        NileComposeText(
            text: text,
            style: style,
            color: UIColor(color),
            backgroundColor: UIColor(background),
            fillsWidth: fillsWidth
        )
        .allowsHitTesting(false)
    }
}
