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
        accent: Theme.dynamic(light: 0x0A6CD0, dark: 0x3AA6FF),
        blush: Theme.dynamic(light: 0xE6079F, dark: 0xFF5AD9),
        lilac: Theme.dynamic(light: 0x7E7BFF, dark: 0xA49BFF),
        background: Theme.dynamic(light: 0xEEF4F9, dark: 0x070F1F),
        surface: Theme.dynamic(light: 0xFFFFFF, dark: 0x101B31),
        hairline: Theme.dynamic(light: 0xD4E1EE, dark: 0x22314F),
        onAccent: .white,
        uiAccent: Theme.uiDynamic(light: 0x0A6CD0, dark: 0x3AA6FF),
        iridescent: [Color(hex: 0x5FD3FF), Theme.dynamic(light: 0x078EFB, dark: 0x3AA6FF),
                     Theme.dynamic(light: 0x7E7BFF, dark: 0xA49BFF), Theme.dynamic(light: 0xE6079F, dark: 0xFF5AD9)])

    /// "Pink smoke": a light theme in shades of pink. The accent (#C2185B) keeps white text and
    /// icons on it above 4.5:1 contrast (WCAG AA), and the page and card colours are pale enough
    /// for the usual dark text. Always light (the app switches to light mode with it).
    static let blossom = Palette(
        accent: Color(hex: 0xC2185B),
        blush: Color(hex: 0xD81B60),
        lilac: Color(hex: 0xAD5C9E),
        background: Color(hex: 0xFFF0F5),
        surface: Color(hex: 0xFFFAFC),
        hairline: Color(hex: 0xF3CFDD),
        onAccent: .white,
        uiAccent: UIColor(hex: 0xC2185B),
        iridescent: [Color(hex: 0xF8BBD0), Color(hex: 0xF06292), Color(hex: 0xD81B60), Color(hex: 0xAD1457)])

    /// "Cosmos": like Pink smoke, in purple. A light theme in shades of lavender and violet, with
    /// slowly folding purple smoke behind the pages and the player. The accent (#6A3FD1) keeps white
    /// text and icons on it above 4.5:1. Always light (the app switches to light mode with it).
    static let cosmos = Palette(
        accent: Color(hex: 0x6A3FD1),
        blush: Color(hex: 0x9C4FD6),
        lilac: Color(hex: 0x8E6BE0),
        background: Color(hex: 0xF4F0FF),
        surface: Color(hex: 0xFCFAFF),
        hairline: Color(hex: 0xE2D8FA),
        onAccent: .white,
        uiAccent: UIColor(hex: 0x6A3FD1),
        iridescent: [Color(hex: 0xD9CCFF), Color(hex: 0xA98BF5), Color(hex: 0x7E57E0), Color(hex: 0x5E35B1)])

    /// "Lemon Drop": pale butter yellow with a golden-amber accent (#9E6200: white on it ≥ 4.5:1).
    static let lemon = Palette(
        accent: Color(hex: 0x9E6200),
        blush: Color(hex: 0xE0A100),
        lilac: Color(hex: 0xC9A227),
        background: Color(hex: 0xFFFBE6),
        surface: Color(hex: 0xFFFEF6),
        hairline: Color(hex: 0xF3E8B0),
        onAccent: .white,
        uiAccent: UIColor(hex: 0x9E6200),
        iridescent: [Color(hex: 0xFFF3B0), Color(hex: 0xFFE066), Color(hex: 0xF5C400), Color(hex: 0xD99A00)])

    /// "Coral Reef": soft coral with a warm red-coral accent (#C73A28: white on it ≥ 4.5:1).
    static let coral = Palette(
        accent: Color(hex: 0xC73A28),
        blush: Color(hex: 0xF2785C),
        lilac: Color(hex: 0xE8956B),
        background: Color(hex: 0xFFF1EC),
        surface: Color(hex: 0xFFFAF8),
        hairline: Color(hex: 0xF8D5CB),
        onAccent: .white,
        uiAccent: UIColor(hex: 0xC73A28),
        iridescent: [Color(hex: 0xFFD3C4), Color(hex: 0xFF9B7E), Color(hex: 0xF2674A), Color(hex: 0xC73A28)])

    /// "Matcha Latte": creamy sage with a deep matcha accent (#4E7A3A: white on it ≥ 4.5:1).
    static let matcha = Palette(
        accent: Color(hex: 0x4E7A3A),
        blush: Color(hex: 0x8BAA5E),
        lilac: Color(hex: 0xA3B97F),
        background: Color(hex: 0xF1F5EA),
        surface: Color(hex: 0xFAFCF6),
        hairline: Color(hex: 0xDCE6CC),
        onAccent: .white,
        uiAccent: UIColor(hex: 0x4E7A3A),
        iridescent: [Color(hex: 0xDCEBC6), Color(hex: 0xB5D08E), Color(hex: 0x7FA65A), Color(hex: 0x4E7A3A)])

    /// "Firefly Night": the one dark theme. Deep navy, a warm firefly-gold accent with dark ink on
    /// it (≥ 9:1), and soft starlight blues.
    static let night = Palette(
        accent: Color(hex: 0xF5C95B),
        blush: Color(hex: 0xFF9F6E),
        lilac: Color(hex: 0x8FA8FF),
        background: Color(hex: 0x0B1426),
        surface: Color(hex: 0x16223D),
        hairline: Color(hex: 0x27365A),
        onAccent: Color(hex: 0x10182B),
        uiAccent: UIColor(hex: 0xF5C95B),
        iridescent: [Color(hex: 0x9FE3B0), Color(hex: 0xF5C95B), Color(hex: 0xFFD98A), Color(hex: 0xFF9F6E)])
}

/// The app's look: the mascot's sky blue and blush pink on pearl, with an iridescent "prism" glass pattern.
enum Theme {
    /// "Shimmer & mascot animations" in Settings. When off, the mascot holds still.
    static var motionEnabled = true

    /// The app theme (Settings → Appearance → App theme). Saved in the shared app group so the
    /// widget picks it up too.
    static var current: ThemeID = loadCurrent() {
        didSet {
            SharedConfig.defaults.set(current.rawValue, forKey: currentKey)
            if current != oldValue { ThemeState.shared.changed() }
        }
    }
    private static let currentKey = "theme.id"
    // Older builds saved two flags instead; still read once, so the choice carries over.
    private static let blossomKey = "theme.isBlossom"
    private static let cosmosKey = "theme.isCosmos"

    private static func loadCurrent() -> ThemeID {
        let d = SharedConfig.defaults
        if let raw = d.string(forKey: currentKey), let id = ThemeID(rawValue: raw) { return id }
        if d.bool(forKey: blossomKey) { return .cottonCandy }
        if d.bool(forKey: cosmosKey) { return .moonberry }
        return .cloudNine
    }

    /// Cotton Candy (pink) is on.
    static var isBlossom: Bool { current == .cottonCandy }
    /// Moonberry (purple) is on.
    static var isCosmos: Bool { current == .moonberry }

    /// For the widget: re-reads the theme the app last chose (the widget process can outlive a change).
    static func reloadSharedTheme() {
        let saved = loadCurrent()
        if saved != current { current = saved }
    }

    static var palette: Palette {
        switch current {
        case .cloudNine: .prism
        case .cottonCandy: .blossom
        case .moonberry: .cosmos
        case .lemonDrop: .lemon
        case .coralReef: .coral
        case .matchaLatte: .matcha
        case .fireflyNight: .night
        }
    }

    /// The one dark theme (Firefly Night); every other theme is light.
    static var isDark: Bool { current == .fireflyNight }

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
    /// The app's card: a solid surface with a hairline edge and a soft accent shadow. Redraws when
    /// the app theme changes (`ThemeState`).
    func glassCard(cornerRadius: CGFloat = 20, material: Bool = false) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius, material: material))
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

// MARK: - Activity colours

extension Theme {
    /// The Activity tab's colours (levels, challenges, trophies, today's ring): one harmonious set
    /// of eight per app theme, so everything matches whichever theme is on while staying varied.
    /// Computed, so a theme change shows at once.
    enum Activity {
        /// sky, teal, mint (success), gold, flame, coral, violet, slate, for each theme.
        private static func tone(_ index: Int) -> Color {
            let table: [UInt32]
            switch Theme.current {
            case .cloudNine:   table = [0x2F9BFF, 0x10A5B8, 0x17A97C, 0xE8A400, 0xFF7417, 0xF2545B, 0x7C5CFA, 0x64748B]
            case .cottonCandy: table = [0xE2557F, 0xB03A6F, 0xC2185B, 0xE0A43A, 0xF08A6C, 0xF06272, 0xD06BA8, 0x8C6B7A]
            case .moonberry:   table = [0x7B6FF0, 0x9B59D0, 0x6A3FD1, 0xD9A23A, 0xE98A5B, 0xE05F9E, 0x8E6BE0, 0x7E7395]
            case .lemonDrop:   table = [0xE6A800, 0x7FAF3A, 0x9E6200, 0xD9A400, 0xF28C28, 0xE46F4C, 0xB8932E, 0x8C7B5A]
            case .coralReef:   table = [0xF2846B, 0x2BA3A0, 0xC73A28, 0xE8A33D, 0xF27A3D, 0xE05561, 0xD96C8E, 0x8F6E68]
            case .matchaLatte: table = [0x86AD6A, 0x4F9A8A, 0x4E7A3A, 0xC9A65A, 0xD08B54, 0xC97B63, 0x8E8A5A, 0x7A7F6C]
            case .fireflyNight: table = [0x8FA8FF, 0x6FD6E8, 0x9FE3B0, 0xF5C95B, 0xFFB17A, 0xFF8A9A, 0xB39DFF, 0x8A93C9]
            }
            return Color(hex: table[index])
        }
        static var sky: Color { tone(0) }
        static var teal: Color { tone(1) }
        /// Success ("goal met", "won").
        static var mint: Color { tone(2) }
        static var gold: Color { tone(3) }
        static var flame: Color { tone(4) }
        static var coral: Color { tone(5) }
        static var violet: Color { tone(6) }
        static var slate: Color { tone(7) }
    }

    /// The accent, deepened enough to read as text and icons on white or a pale accent tint
    /// (the book card's chips and ✕). Follows the app theme.
    static var accentInk: Color {
        switch current {
        case .cloudNine: Color(hex: 0x0A5FB4)
        case .cottonCandy: Color(hex: 0x9C1449)
        case .moonberry: Color(hex: 0x4A2A9E)
        case .lemonDrop: Color(hex: 0x7A4A00)
        case .coralReef: Color(hex: 0x8F2414)
        case .matchaLatte: Color(hex: 0x355427)
        case .fireflyNight: Color(hex: 0x8A5A00)
        }
    }
}

/// Tells views that draw with `Theme`'s colours that the app theme changed (Classic, Pink smoke,
/// Cosmos), so they redraw at once. `Theme`'s colours are plain static values, which SwiftUI
/// can't watch: a card whose own inputs didn't change kept the old theme's colours (e.g. white
/// Settings cards after switching from Pink smoke to Cosmos).
final class ThemeState: ObservableObject {
    static let shared = ThemeState()
    @Published private(set) var revision = 0

    func changed() {
        if Thread.isMainThread {
            revision += 1
        } else {
            DispatchQueue.main.async { self.revision += 1 }
        }
    }
}

/// `glassCard()`: see there.
struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat
    var material: Bool
    @ObservedObject private var themeState = ThemeState.shared

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                shape.fill(material ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(Theme.surface))
            }
            .overlay {
                shape.strokeBorder(Theme.hairline, lineWidth: 0.75)
            }
            .shadow(color: Theme.accent.opacity(0.10), radius: 14, y: 6)
    }
}

/// The app themes (smoky; all light except Firefly Night). Shared with the widget.
enum ThemeID: String, CaseIterable {
    case cloudNine, cottonCandy, moonberry, lemonDrop, coralReef, matchaLatte, fireflyNight

    var name: String {
        switch self {
        case .cloudNine: "Cloud Nine"
        case .cottonCandy: "Cotton Candy"
        case .moonberry: "Moonberry"
        case .lemonDrop: "Lemon Drop"
        case .coralReef: "Coral Reef"
        case .matchaLatte: "Matcha Latte"
        case .fireflyNight: "Firefly Night"
        }
    }

    /// The page smoke's five tones, deepest folds to palest crests (Lemon Drop, Coral Reef and
    /// Matcha Latte; the first three themes have their own shaders).
    var smokeStops: [UInt32] {
        switch self {
        case .cloudNine: [0x1A6BCC, 0x54A3F2, 0x94CCFC, 0xC9E6FF, 0xEDF7FF]
        case .cottonCandy: [0xB33873, 0xE073A1, 0xF5A3C4, 0xFCCCDE, 0xFFEDF5]
        case .moonberry: [0x5C38B3, 0x8C6BE0, 0xB89EF5, 0xD9C9FC, 0xF2EDFF]
        case .lemonDrop: [0xD9A400, 0xF2C94C, 0xFBE38A, 0xFFF2BF, 0xFFFBEA]
        case .coralReef: [0xD9533C, 0xF2846B, 0xF9AE9A, 0xFDD3C7, 0xFFF2EE]
        case .matchaLatte: [0x5E8A47, 0x86AD6A, 0xAECB93, 0xD4E3C1, 0xF2F7EB]
        // Dark: deep folds to soft night-blue crests.
        case .fireflyNight: [0x060B18, 0x0B1630, 0x122247, 0x1B3060, 0x274078]
        }
    }
}

// MARK: - Readable text

extension Theme {
    /// Secondary text (subtitles, captions, headings over the page smoke). Stronger than the
    /// system's `.secondary`, which measured only ~3.2:1 over the pale smoke; this stays above 4.5:1
    /// (WCAG AA) on every theme's pages and cards.
    static var secondaryText: Color { Color.primary.opacity(0.72) }
    /// Tertiary text (dates, small hints). Above 4.5:1 on cards in every theme.
    static var tertiaryText: Color { Color.primary.opacity(0.6) }

    /// `color`, deepened (on a light background) or lightened (on a dark one) just enough to reach
    /// `ratio` contrast against `background`, keeping its hue. For coloured text and icons: the
    /// Activity colours (gold, peach, mint…) and cover accents are lovely as fills but too pale to
    /// read as text. 4.5:1 is WCAG AA for normal text.
    static func readable(_ color: Color, on background: Color? = nil, ratio: CGFloat = 4.5) -> Color {
        let traits = UITraitCollection(userInterfaceStyle: isDark ? .dark : .light)
        let fg = UIColor(color).resolvedColor(with: traits)
        let bg = UIColor(background ?? surface).resolvedColor(with: traits)
        let bgL = luminance(bg)
        guard contrast(luminance(fg), bgL) < ratio else { return color }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        fg.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let darken = bgL > 0.4
        for _ in 0..<30 {
            if darken {
                b = max(0, b - 0.03)
                s = min(1, s + 0.01)
            } else {
                b = min(1, b + 0.03)
                s = max(0, s - 0.03)
            }
            let candidate = UIColor(hue: h, saturation: s, brightness: b, alpha: 1)
            if contrast(luminance(candidate), bgL) >= ratio { return Color(uiColor: candidate) }
        }
        return Color(uiColor: UIColor(hue: h, saturation: s, brightness: b, alpha: 1))
    }

    private static func luminance(_ color: UIColor) -> CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        func lin(_ c: CGFloat) -> CGFloat { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    private static func contrast(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
        (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}
