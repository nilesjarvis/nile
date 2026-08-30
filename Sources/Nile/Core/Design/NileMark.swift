import SwiftUI

struct NileMark: View {
    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let origin = CGPoint(
                x: (size.width - side) / 2,
                y: (size.height - side) / 2
            )
            let background = Path(
                roundedRect: CGRect(
                    origin: origin,
                    size: CGSize(width: side, height: side)
                ),
                cornerRadius: side * 0.22
            )
            context.fill(background, with: .color(Self.navy))

            let footprintScale: CGFloat = 0.8
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                let insetX = 512 + (x - 512) * footprintScale
                let insetY = 512 + (y - 512) * footprintScale
                return CGPoint(
                    x: origin.x + side * insetX / 1024,
                    y: origin.y + side * insetY / 1024
                )
            }

            var river = Path()
            river.move(to: point(566, 106))
            river.addCurve(
                to: point(710, 220),
                control1: point(625, 128),
                control2: point(676, 168)
            )
            river.addCurve(
                to: point(732, 426),
                control1: point(749, 285),
                control2: point(759, 358)
            )
            river.addCurve(
                to: point(557, 584),
                control1: point(703, 500),
                control2: point(639, 549)
            )
            river.addCurve(
                to: point(418, 664),
                control1: point(495, 610),
                control2: point(445, 631)
            )
            river.addCurve(
                to: point(408, 744),
                control1: point(397, 690),
                control2: point(392, 718)
            )
            river.addCurve(
                to: point(564, 802),
                control1: point(433, 785),
                control2: point(493, 806)
            )
            river.addCurve(
                to: point(764, 704),
                control1: point(643, 798),
                control2: point(711, 763)
            )
            river.addCurve(
                to: point(892, 817),
                control1: point(811, 743),
                control2: point(854, 782)
            )
            river.addCurve(
                to: point(797, 905),
                control1: point(868, 850),
                control2: point(836, 879)
            )
            river.addCurve(
                to: point(579, 970),
                control1: point(735, 946),
                control2: point(660, 969)
            )
            river.addCurve(
                to: point(225, 804),
                control1: point(424, 973),
                control2: point(286, 912)
            )
            river.addCurve(
                to: point(270, 536),
                control1: point(176, 716),
                control2: point(193, 613)
            )
            river.addCurve(
                to: point(465, 424),
                control1: point(327, 485),
                control2: point(393, 454)
            )
            river.addCurve(
                to: point(584, 351),
                control1: point(520, 401),
                control2: point(563, 379)
            )
            river.addCurve(
                to: point(588, 270),
                control1: point(603, 326),
                control2: point(603, 299)
            )
            river.addCurve(
                to: point(520, 198),
                control1: point(572, 240),
                control2: point(548, 214)
            )
            river.addCurve(
                to: point(566, 106),
                control1: point(532, 161),
                control2: point(548, 131)
            )
            river.closeSubpath()
            context.fill(river, with: .color(Self.ivory))
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private static let navy = Color(
        .sRGB,
        red: 18 / 255,
        green: 59 / 255,
        blue: 93 / 255,
        opacity: 1
    )
    private static let ivory = Color(
        .sRGB,
        red: 246 / 255,
        green: 241 / 255,
        blue: 232 / 255,
        opacity: 1
    )
}
