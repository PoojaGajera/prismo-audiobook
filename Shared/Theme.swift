import SwiftUI
import UIKit

/// The app's colours (each adapts to light / dark).
struct Palette {
    var accent: Color
    var blush: Color
    var lilac: Color
    var background: Color
    var surface: Color
    var hairline: Color
    var onAccent: Color
    var uiAccent: UIColor
    var iridescent: [Color]

    static let prism = Palette(
        accent: Theme.dynamic(light: 0x078EFB, dark: 0x3AA6FF),
        blush: Theme.dynamic(light: 0xE6079F, dark: 0xFF5AD9),
        lilac: Theme.dynamic(light: 0x7E7BFF, dark: 0xA49BFF),
        background: Theme.dynamic(light: 0xEEF4F9, dark: 0x070F1F),
        surface: Theme.dynamic(light: 0xFFFFFF, dark: 0x101B31),
        hairline: Theme.dynamic(light: 0xD4E1EE, dark: 0x22314F),
        onAccent: .white,
        uiAccent: Theme.uiDynamic(light: 0x078EFB, dark: 0x3AA6FF),
        iridescent: [Color(hex: 0x5FD3FF), Theme.dynamic(light: 0x078EFB, dark: 0x3AA6FF),
                     Theme.dynamic(light: 0x7E7BFF, dark: 0xA49BFF), Theme.dynamic(light: 0xE6079F, dark: 0xFF5AD9)])
}

/// The app's look: the mascot's sky blue and blush pink on pearl, with an iridescent "prism" glass pattern.
enum Theme {
    /// "Shimmer & mascot animations" in Settings. When off, the mascot holds still.
    static var motionEnabled = true

    static var palette: Palette { .prism }

    // MARK: Brand (from the mascot)
    static let mascotBlue = Color(hex: 0x078EFB)
    static let mascotPearl = Color(hex: 0xEEF4F9)
    static let mascotBlush = Color(hex: 0xFB07CE)
    static let mascotInk = Color(hex: 0x0B1530)

    // MARK: Adaptive (light / dark)
    /// Primary accent: buttons, progress, selection.
    static var accent: Color { palette.accent }
    /// Secondary accent, used sparingly: bookmarks, highlights.
    static var blush: Color { palette.blush }
    /// The colour that bridges the two accents in the iridescent gradient.
    static var lilac: Color { palette.lilac }
    static var background: Color { palette.background }
    static var surface: Color { palette.surface }
    /// Hairline borders on glass cards.
    static var hairline: Color { palette.hairline }
    static var onAccent: Color { palette.onAccent }
    static var uiAccent: UIColor { palette.uiAccent }

    // MARK: Fixed
    static let deepSea = Color(hex: 0x0A2A5E)
    static let abyss = Color(hex: 0x061433)

    /// Cyan → blue → lilac → pink, like light through the prism glass.
    static var iridescent: LinearGradient {
        LinearGradient(colors: palette.iridescent, startPoint: .leading, endPoint: .trailing)
    }

    static var progressGradient: LinearGradient { iridescent }

    static var coverPlaceholder: LinearGradient {
        LinearGradient(colors: [Color(hex: 0x9BD8FF), accent, lilac],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Titles in the system font (SF Pro).
    static func title(_ style: Font.TextStyle, weight: Font.Weight = .bold) -> Font {
        .system(style).weight(weight)
    }

    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: uiDynamic(light: light, dark: dark))
    }

    static func uiDynamic(light: UInt32, dark: UInt32) -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        }
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

/// The refracted glass pattern ("Prism" in the asset catalogs; light and dark variants).
struct PrismImage: View {
    var body: some View {
        Image("Prism")
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .accessibilityHidden(true)
    }
}

extension View {
    /// Frosted card with a hairline edge and a soft blue-tinted shadow.
    func glassCard(cornerRadius: CGFloat = 20, material: Bool = false) -> some View {
        self
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(material ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(Theme.surface))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 0.75)
            }
            .shadow(color: Theme.accent.opacity(0.10), radius: 14, y: 6)
    }
}

/// The play/pause glyph: a plain accent-coloured circle. Shared by the app and the widget.
struct PlayBadge: View {
    var isPlaying: Bool
    var size: CGFloat
    var color: Color = Theme.accent

    var body: some View {
        ZStack {
            Circle()
                .fill(color)
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: size * 0.36, weight: .bold))
                .foregroundStyle(Theme.onAccent)
                .contentTransition(.symbolEffect(.replace))
                // SF Symbols' "play.fill" already sits slightly right in its box, which looks centred
                // in a circle; an extra nudge pushed it visibly off-centre.
                .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
    }
}

/// The skip back / skip forward icon: a thin open circle with an arrowhead, with the seconds drawn
/// separately, so the circle can be made bigger without the number growing with it (and any interval
/// works, not just the ones SF Symbols has a numbered glyph for). Shared by the app and the widget.
struct SkipGlyph: View {
    var back: Bool
    var seconds: Double
    /// The circle's point size.
    var size: CGFloat
    /// The number's point size.
    var numberSize: CGFloat

    var body: some View {
        Image(systemName: back ? "gobackward" : "goforward")
            .font(.system(size: size, weight: .light))
            .overlay {
                Text("\(Int(seconds))")
                    .font(.system(size: numberSize, weight: .semibold).monospacedDigit())
                    // The arrowhead sits on top of the circle, so the circle's centre is a little low.
                    .offset(y: size * 0.04)
            }
    }
}

/// The 4-point spacing scale. Use these instead of one-off numbers, so gaps stay consistent:
/// small steps inside a group (title → author), larger steps between groups.
enum Spacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 24
    static let xl: CGFloat = 32
}
