import SwiftUI
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - Prism background

/// Screen backdrop. Only the splash shows the refracted glass pattern (it drifts and its
/// colours shimmer slowly, unless motion is off in Settings or Reduce Motion is on).
/// Every other screen gets the plain page colour, plus an optional cover tint.
struct PrismBackground: View {
    enum Style {
        case plain    // page colour only, no pattern
        case splash   // whole screen pattern, full strength
    }

    var style: Style = .plain
    var tint: Color? = nil

    @EnvironmentObject private var settings: AppSettings
    @Environment(\.pageIsVisible) private var pageIsVisible
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private var animated: Bool { settings.backgroundMotionEnabled && !reduceMotion }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                if style == .plain {
                    // Every theme: pale, slow smoke in its colours.
                    PageSmoke(isActive: pageIsVisible)
                } else {
                    Theme.background
                }

                if style == .plain, settings.snowfall {
                    ThemeParticles()
                }

                if style == .splash {
                    ShimmeringPrism(animated: animated)
                        .frame(width: geo.size.width, height: geo.size.height)
                }

                if let tint {
                    LinearGradient(colors: [tint.opacity(0.35), tint.opacity(0.10), .clear],
                                   startPoint: .top, endPoint: .bottom)
                        .blendMode(colorScheme == .dark ? .plusLighter : .multiply)
                        .opacity(colorScheme == .dark ? 0.5 : 0.6)
                }
            }
        }
        .ignoresSafeArea()
    }

}

/// The pattern with a slow drift and a gentle hue shift, like light moving across glass.
struct ShimmeringPrism: View {
    var animated: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !animated)) { context in
            let t = animated ? context.date.timeIntervalSinceReferenceDate : 0
            PrismImage()
                .scaleEffect(1.12 + 0.03 * sin(t / 9))
                .offset(x: 14 * sin(t / 13), y: 10 * cos(t / 11))
                .hueRotation(.degrees(10 * sin(t / 7)))
        }
        .clipped()
    }
}

// MARK: - Progress

/// The scrubber: an iridescent ribbon with a pearl thumb.
struct PearlSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    /// Solid fill colour (the player passes the cover's accent). Nil = the iridescent ribbon.
    var tint: Color? = nil
    var onEditingChanged: (Bool) -> Void = { _ in }

    @State private var isDragging = false

    private var fill: AnyShapeStyle { tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(Theme.iridescent) }
    private var ring: Color { tint ?? Theme.accent }

    private var span: Double { max(range.upperBound - range.lowerBound, 0.0001) }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let thumb: CGFloat = isDragging ? 26 : 18
            let fraction = min(1, max(0, (value - range.lowerBound) / span))
            let x = thumb / 2 + (width - thumb) * fraction

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.10))
                    .frame(height: isDragging ? 8 : 6)
                Capsule()
                    .fill(fill)
                    .frame(width: max(6, x), height: isDragging ? 8 : 6)
                Circle()
                    .fill(.white)
                    .overlay { Circle().strokeBorder(ring, lineWidth: isDragging ? 3 : 2.5) }
                    .frame(width: thumb, height: thumb)
                    .shadow(color: ring.opacity(0.35), radius: isDragging ? 8 : 4, y: 2)
                    .position(x: x, y: geo.size.height / 2)
            }
            .frame(height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { gesture in
                        if !isDragging {
                            isDragging = true
                            onEditingChanged(true)
                        }
                        let f = min(1, max(0, (gesture.location.x - thumb / 2) / max(1, width - thumb)))
                        value = range.lowerBound + f * span
                    }
                    .onEnded { _ in
                        isDragging = false
                        onEditingChanged(false)
                    })
        }
        .frame(height: 34)
        .animation(.spring(duration: 0.25), value: isDragging)
        .sensoryFeedback(.selection, trigger: isDragging)
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue(TimeFormat.clock(value - range.lowerBound))
        .accessibilityAdjustableAction { direction in
            let step = span * 0.02
            onEditingChanged(true)
            switch direction {
            case .increment: value = min(range.upperBound, value + step)
            case .decrement: value = max(range.lowerBound, value - step)
            @unknown default: break
            }
            onEditingChanged(false)
        }
    }
}

/// A slim read-only iridescent progress ribbon.
struct IridescentBar: View {
    var value: Double
    var height: CGFloat = 4
    /// Solid fill colour instead of the iridescent ribbon.
    var tint: Color? = nil

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(Theme.iridescent))
                    .frame(width: max(height, geo.size.width * min(1, max(0, value))))
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue("\(Int(min(1, max(0, value)) * 100)) percent")
    }
}

// MARK: - Buttons

/// Play/pause in the shape of the mascot's scalloped badge. Glows a little while playing.
struct BadgePlayButton: View {
    var isPlaying: Bool
    var size: CGFloat = 80
    var color: Color = Theme.accent
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            PlayBadge(isPlaying: isPlaying, size: size, color: color)
                .shadow(color: color.opacity(isPlaying ? 0.55 : 0.30), radius: isPlaying ? size * 0.25 : size * 0.14, y: size * 0.06)
                .animation(.spring(duration: 0.5, bounce: 0.35), value: isPlaying)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: isPlaying)
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
    }
}

/// Round frosted icon button used in toolbars and bars.
struct GlassIconButton: View {
    var systemName: String
    var label: String
    var size: CGFloat = 44
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: size, height: size)
                .background(.ultraThinMaterial, in: Circle())
                .overlay { Circle().strokeBorder(Theme.hairline.opacity(0.8), lineWidth: 0.5) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Cover colours

/// Colours taken from a book's cover, used all over the player: the background gradient,
/// the play button, the progress bar, the option chips and the player's sheets. Light and airy:
/// pastel tints of the cover's main colour, plus one clear (not muddy) accent.
/// Every colour adapts to light and dark mode.
struct CoverTheme {
    /// Play button, progress fill, selected chips. White icons sit on it.
    var accent: Color
    /// Top of the player background (a soft pastel of the cover colour).
    var deep: Color
    /// Middle of the background gradient.
    var mid: Color
    /// Bottom of the background (almost white in light mode).
    var light: Color
    /// Solid fill of the option chips, round buttons and sheet cards.
    var chip: Color
    /// Icons and text on `chip`.
    var onChip: Color
    /// Solid background of the player's sheets.
    var sheet: Color
    /// The 4 × 4 colours of the player's mesh-gradient background (row by row from the top):
    /// a mix of deep and light blobs in the cover's main colours, softer behind the text.
    var mesh: [Color]
    /// Three soft but colourful tints of the cover's main colours (its top hue first), for the
    /// player's smoke, which blends between them.
    var smokeHues: [Color] = []

    /// Used before a cover has loaded, or for books without one: a soft periwinkle.
    static let fallback = CoverTheme(hue: 0.62, saturation: 0.45, others: [(0.83, 0.35), (0.52, 0.35)])

    /// - Parameters:
    ///   - hue: the cover's dominant hue (0…1).
    ///   - saturation: how colourful that hue is on the cover (0 = a grey or black-and-white cover).
    ///   - others: the cover's next most common colours (hue, saturation), for the background.
    init(hue: CGFloat, saturation: CGFloat, others: [(CGFloat, CGFloat)] = []) {
        mesh = Self.meshColors(primary: (hue, saturation), others: others)
        smokeHues = Self.smokeHueColors(primary: (hue, saturation), others: others)
        let gray = saturation < 0.12
        // Yellows and greens look much brighter than blues and reds at the same brightness,
        // so their accent is a little deeper to keep the white play icon readable.
        let luminous = hue > 0.10 && hue < 0.50
        func clamp(_ x: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { min(hi, max(lo, x)) }
        /// (saturation, brightness) for light mode, then for dark mode.
        func tone(_ light: (CGFloat, CGFloat), _ dark: (CGFloat, CGFloat)) -> Color {
            Color(uiColor: UIColor { traits in
                let (s, b) = traits.userInterfaceStyle == .dark ? dark : light
                return UIColor(hue: hue, saturation: s, brightness: b, alpha: 1)
            })
        }
        let s = saturation
        if gray {
            accent = tone((0.06, 0.36), (0.05, 0.62))
            deep   = tone((0.03, 0.93), (0.04, 0.26))
            mid    = tone((0.02, 0.97), (0.04, 0.15))
            light  = tone((0.01, 1.0), (0.03, 0.08))
            chip   = tone((0.03, 0.92), (0.04, 0.24))
            onChip = tone((0.05, 0.30), (0.00, 0.96))
            sheet  = tone((0.01, 1.0), (0.03, 0.12))
        } else {
            accent = tone((clamp(s, 0.45, 0.72), luminous ? 0.66 : 0.80),
                          (clamp(s, 0.40, 0.60), luminous ? 0.72 : 0.82))
            deep   = tone((0.24, 0.96), (clamp(s, 0.35, 0.55), 0.32))
            mid    = tone((0.12, 0.98), (0.40, 0.17))
            light  = tone((0.03, 1.0), (0.30, 0.09))
            chip   = tone((0.16, 0.93), (0.28, 0.24))
            onChip = tone((0.50, 0.30), (0.06, 0.96))
            sheet  = tone((0.03, 1.0), (0.25, 0.13))
        }
    }
}

extension CoverTheme {
    /// Sixteen blob colours from the cover's palette, deep and light mixed.
    /// A cover with only one colour gets its neighbouring hues, so the background still has life.
    /// The smoke's three tints: the cover's main colours (filled up with the top colour's
    /// neighbours on the colour wheel), soft enough that dark text stays well above 4.5:1.
    fileprivate static func smokeHueColors(primary: (CGFloat, CGFloat), others: [(CGFloat, CGFloat)]) -> [Color] {
        func wrap(_ h: CGFloat) -> CGFloat { h - floor(h) }
        var palette = [primary] + others.filter { $0.1 >= 0.12 }
        if primary.1 < 0.12 {
            palette = [(0.60, 0.12), (0.08, 0.12), (0.75, 0.10)]
        } else {
            let shifts: [CGFloat] = [0.07, -0.07]
            var i = 0
            while palette.count < 3 {
                palette.append((wrap(primary.0 + shifts[i % 2] * CGFloat(i / 2 + 1)), primary.1))
                i += 1
            }
        }
        return palette.prefix(3).map { h, s in
            Color(hue: h, saturation: min(0.42, max(0.14, s * 0.6)), brightness: 0.96)
        }
    }

    fileprivate static func meshColors(primary: (CGFloat, CGFloat), others: [(CGFloat, CGFloat)]) -> [Color] {
        func clamp(_ x: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { min(hi, max(lo, x)) }
        func wrap(_ h: CGFloat) -> CGFloat { h - floor(h) }

        let gray = primary.1 < 0.12
        var palette = [primary] + others.filter { $0.1 >= 0.12 }
        if gray {
            // Black-and-white cover: a quiet cool/warm mix.
            palette = [(0.60, 0.10), (0.08, 0.10), (0.75, 0.08)]
        } else {
            // Fill up to three with the main colour's neighbours on the colour wheel.
            let shifts: [CGFloat] = [0.07, -0.07]
            var i = 0
            while palette.count < 3 {
                palette.append((wrap(primary.0 + shifts[i % 2] * CGFloat(i / 2 + 1)), primary.1))
                i += 1
            }
        }
        /// The blob tones. Light mode: rich deep blobs and pale ones around the cover, staying
        /// light behind the title and controls so the text reads. Dark mode: the same pattern,
        /// glowing tones on deep ones, staying dark behind the text.
        enum Tone { case deep, mid, soft, pale }
        func color(_ index: Int, _ kind: Tone) -> Color {
            let (h, s) = palette[index % palette.count]
            return Color(uiColor: UIColor { traits in
                // The player keeps its light, airy look in dark mode too (the user's choice);
                // the dark tones below are kept in case that changes.
                let dark = false && traits.userInterfaceStyle == .dark
                let tone: (CGFloat, CGFloat)
                switch (kind, dark) {
                case (.deep, false): tone = (clamp(s, 0.10, 0.80), gray ? 0.40 : 0.50)
                case (.mid, false):  tone = (clamp(s * 0.80, 0.08, 0.60), 0.80)
                case (.soft, false): tone = (clamp(s * 0.45, 0.05, 0.32), 0.93)
                case (.pale, false): tone = (clamp(s * 0.20, 0.03, 0.14), 0.99)
                case (.deep, true):  tone = (clamp(s, 0.10, 0.75), 0.16)
                case (.mid, true):   tone = (clamp(s, 0.10, 0.65), 0.46)
                case (.soft, true):  tone = (clamp(s, 0.08, 0.55), 0.28)
                case (.pale, true):  tone = (clamp(s, 0.05, 0.45), 0.12)
                }
                return UIColor(hue: h, saturation: tone.0, brightness: tone.1, alpha: 1)
            })
        }
        let d = palette.count > 3 ? 3 : 0
        // 4 × 4, row by row from the top (rows sit at 0, ⅓, ⅔ and the bottom of the screen).
        // Deep and light blobs alternate at the top, beside the cover and in the bottom corners;
        // the row at ⅔ (chapter and progress bar) stays soft and pale so text reads.
        return [
            color(1, .mid),  color(0, .deep), color(2, .pale), color(d, .mid),
            color(2, .deep), color(1, .soft), color(0, .mid),  color(1, .deep),
            color(0, .soft), color(2, .pale), color(1, .pale), color(2, .mid),
            color(1, .deep), color(d, .mid),  color(0, .soft), color(2, .deep)
        ]
    }
}

extension EnvironmentValues {
    /// The current book's cover colours (set by the player for itself and its sheets).
    @Entry var coverTheme: CoverTheme = .fallback
}

/// Works out a cover's dominant colour (its most common vivid hue, not the muddy average).
@MainActor
enum CoverPalette {
    private static var cache: [String: CoverTheme] = [:]

    /// The Pink smoke theme's colours for the player (instead of the cover's).
    static let blossom: CoverTheme = {
        var theme = CoverTheme(hue: 0.935, saturation: 0.7)
        theme.accent = Color(hex: 0xC2185B)
        return theme
    }()

    /// The Cosmos theme's colours for the player: lavender, with a violet accent.
    static let lavender: CoverTheme = {
        var theme = CoverTheme(hue: 0.72, saturation: 0.6)
        theme.accent = Color(hex: 0x6A3FD1)
        return theme
    }()

    static func theme(for book: Book) -> CoverTheme {
        // Every theme's player takes the cover's own colours (Pink smoke's player used to be pink:
        // `blossom`, now unused; Cosmos' `lavender` likewise).
        // Called on every redraw of the player, so the cache is checked first (no image work).
        guard book.hasCover else { return .fallback }
        let key = "\(book.id)#\(book.coverVersion ?? 0)"
        if let cached = cache[key] { return cached }
        guard let image = CoverCache.image(for: book, fullSize: false) else { return .fallback }
        let colors = dominantColors(of: image)
        let theme = colors.first.map {
            CoverTheme(hue: $0.hue, saturation: $0.saturation,
                       others: colors.dropFirst().map { ($0.hue, $0.saturation) })
        } ?? .fallback
        cache[key] = theme
        return theme
    }

    /// The cover's accent colour (buttons, progress).
    static func color(for book: Book) -> Color? {
        theme(for: book).accent
    }

    /// The cover's main colours, most common first (up to four, at least 30° apart on the colour
    /// wheel). A grey or black-and-white cover gives one colour with no saturation.
    private static func dominantColors(of image: UIImage) -> [(hue: CGFloat, saturation: CGFloat)] {
        guard let cgImage = image.cgImage else { return [] }
        let side = 24
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side,
                                          bitsPerComponent: 8, bytesPerRow: side * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return [] }

        // A hue histogram where vivid, mid-bright pixels count most (near-black, near-white and
        // grey pixels barely count), so a cover's real colour wins over its shadows and text.
        let bins = 24
        var weight = [Double](repeating: 0, count: bins)
        var satSum = [Double](repeating: 0, count: bins)
        var hueX = [Double](repeating: 0, count: bins)
        var hueY = [Double](repeating: 0, count: bins)
        var total = 0.0
        let count = Double(side * side)

        for i in stride(from: 0, to: pixels.count, by: 4) {
            let color = UIColor(red: CGFloat(pixels[i]) / 255, green: CGFloat(pixels[i + 1]) / 255,
                                blue: CGFloat(pixels[i + 2]) / 255, alpha: 1)
            var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
            color.getHue(&h, saturation: &s, brightness: &v, alpha: &a)
            let w = Double(s * s) * max(0, 1 - abs(Double(v) - 0.6) / 0.6)
            guard w > 0.01 else { continue }
            let bin = min(bins - 1, Int(Double(h) * Double(bins)))
            let angle = Double(h) * 2 * .pi
            weight[bin] += w
            satSum[bin] += Double(s) * w
            hueX[bin] += cos(angle) * w
            hueY[bin] += sin(angle) * w
            total += w
        }

        // Mostly grey / black-and-white cover.
        guard total / count > 0.02 else { return [(0.6, 0)] }

        // The strongest hues, each counting its neighbours too (the histogram wraps round).
        func around(_ i: Int) -> [Int] { [(i + bins - 1) % bins, i, (i + 1) % bins] }
        func sum(_ values: [Double], over bins: [Int]) -> Double {
            var total = 0.0
            for i in bins { total += values[i] }
            return total
        }
        var colors: [(hue: CGFloat, saturation: CGFloat)] = []
        var taken = Set<Int>()
        var firstScore = 0.0
        while colors.count < 4 {
            var best = -1
            var bestScore = 0.0
            for i in 0..<bins where !taken.contains(i) {
                let score = sum(weight, over: around(i))
                if score > bestScore {
                    best = i
                    bestScore = score
                }
            }
            // Stop when nothing is left, or what's left is only a speck of colour.
            guard best >= 0, bestScore > 0, bestScore >= firstScore * 0.12 else { break }
            if colors.isEmpty { firstScore = bestScore }
            let group = around(best)
            let groupWeight = sum(weight, over: group)
            var hue = atan2(sum(hueY, over: group), sum(hueX, over: group)) / (2 * Double.pi)
            if hue < 0 { hue += 1 }
            colors.append((CGFloat(hue), CGFloat(sum(satSum, over: group) / groupWeight)))
            // Keep the next colour at least two bins (30°) away from this one.
            for d in -2...2 { taken.insert((best + d + bins) % bins) }
        }
        return colors.isEmpty ? [(0.6, 0)] : colors
    }
}

// MARK: - Cover background

/// The open player's background: a soft mesh gradient of the cover's colours that slowly drifts,
/// like light moving through the cover. Holds still with Reduce Motion, or with
/// "Shimmer & mascot animations" off in Settings.
struct CoverMeshBackground: View {
    /// Sixteen colours, row by row (`CoverTheme.mesh`).
    var colors: [Color]
    /// Drift only while the player can be seen.
    var isActive: Bool

    @EnvironmentObject private var settings: AppSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let moving = isActive && settings.backgroundMotionEnabled && !reduceMotion
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !moving)) { context in
            MeshGradient(width: 4, height: 4,
                         points: Self.points(at: context.date.timeIntervalSinceReferenceDate),
                         colors: colors,
                         smoothsColors: true,
                         colorSpace: .perceptual)
        }
        .accessibilityHidden(true)
    }

    /// Tune the drift here. `cycleScale` multiplies every cycle's length (0.4 = 2.5× faster than
    /// the original 17–37 s, so roughly 7–15 s); `swayScale` multiplies how far the blobs move.
    static let cycleScale = 0.4
    static let swayScale: Float = 1.25

    /// The mesh's points sway (each on its own cycle, see `cycleScale`), so the blobs drift
    /// and change shape; the corners stay put and edge points only slide along their edge.
    private static func points(at t: Double) -> [SIMD2<Float>] {
        func sway(_ period: Double, _ phase: Double, _ amount: Float) -> Float {
            Float(sin(t * 2 * .pi / (period * cycleScale) + phase)) * amount * swayScale
        }
        let a: Float = 1.0 / 3.0
        let b: Float = 2.0 / 3.0
        return [
            SIMD2(0, 0), SIMD2(a + sway(29, 0, 0.08), 0), SIMD2(b + sway(23, 1, 0.08), 0), SIMD2(1, 0),

            SIMD2(0, a + sway(31, 2, 0.07)),
            SIMD2(a + sway(19, 3, 0.10), a + sway(27, 4, 0.08)),
            SIMD2(b + sway(37, 5, 0.10), a + sway(21, 6, 0.08)),
            SIMD2(1, a + sway(25, 7, 0.07)),

            SIMD2(0, b + sway(33, 8, 0.07)),
            SIMD2(a + sway(23, 9, 0.10), b + sway(29, 10, 0.07)),
            SIMD2(b + sway(17, 11, 0.10), b + sway(35, 12, 0.07)),
            SIMD2(1, b + sway(27, 13, 0.07)),

            SIMD2(0, 1), SIMD2(a + sway(21, 14, 0.08), 1), SIMD2(b + sway(31, 15, 0.08), 1), SIMD2(1, 1)
        ]
    }
}

/// The open player's background, as chosen in Settings → Appearance → Player background.
struct PlayerBackground: View {
    var theme: CoverTheme
    /// Moves only while the player can be seen.
    var isActive: Bool

    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        // Every theme: folding smoke in the book cover's colours (user's request).
        CoverSmokeBackground(theme: theme, isActive: isActive)
    }
}

/// Slowly folding smoke in shades of pink (`pinkSmoke` in PlayerBackgrounds.metal). Holds still
/// with Reduce Motion, or with "Animations" off in Settings.
struct PinkSmokeBackground: View {
    var isActive: Bool
    /// Lowest tone (0…1): 0.32 behind the player, paler (0.8, plus a white veil) behind pages of text.
    var lightness: Float = 0.32
    /// How fast it moves (1 = the player's pace).
    var pace: Double = 1
    /// Which colours: pink (Cotton Candy), purple (Moonberry) or sky blue (Cloud Nine).
    var tint: SmokeTint = .pink

    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// One shared clock, so the smoke carries on where it was when a screen opens again.
    private static let start = Date()

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let moving = isActive && settings.backgroundMotionEnabled && !reduceMotion
        TimelineView(.animation(minimumInterval: pace < 1 ? 1.0 / 15 : 1.0 / 24, paused: !moving)) { context in
            let seconds = context.date.timeIntervalSince(Self.start) * pace
            let time = Float(seconds.truncatingRemainder(dividingBy: 3600))
            // Full resolution, as before (the low-resolution version looked worse).
            GeometryReader { geo in
                Rectangle()
                    .fill(.white)
                    .colorEffect(tint.shader(.float2(geo.size), .float(time), .float(lightness)))
            }
        }
        .accessibilityHidden(true)
    }
}

/// The background of the app's pages (library, settings, chapters, bookmarks, book details):
/// the plain page colour, or with the Pink smoke theme a very pale, slow pink smoke.
struct ThemedPageBackground: View {
    /// True on a tab page (Settings): the smoke and particles move. Sheets (Edit Details, goals,
    /// cover search, the finished book…) keep a still background, and while one is open the
    /// pages underneath pause their animations too (`ModalPresence`): typing stays smooth.
    var live = false

    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.pageIsVisible) private var pageIsVisible

    var body: some View {
        ZStack {
            PageSmoke(isActive: live && pageIsVisible)
            if live, settings.snowfall {
                ThemeParticles()
            }
        }
        .ignoresSafeArea()
        .onAppear { if !live { ModalPresence.shared.enter() } }
        .onDisappear { if !live { ModalPresence.shared.leave() } }
    }
}

/// How many sheets with a page background are open. While any is, the tab pages underneath
/// pause their moving backgrounds (RootView folds this into `pageIsVisible`).
final class ModalPresence: ObservableObject {
    static let shared = ModalPresence()
    @Published private(set) var count = 0

    func enter() { count += 1 }
    func leave() { count = max(0, count - 1) }
}

// MARK: - Marquee text

/// One line of text that, when it's too long to fit, slowly scrolls sideways (pausing at the
/// start each time round) so the whole of it can be read. Short text just sits still.
/// Holds still, truncated, with Reduce Motion on, or while `isActive` is false.
struct MarqueeText: View {
    let text: String
    var font: Font
    /// Scroll only while this is true (e.g. while the player is open).
    var isActive = true
    /// Points per second.
    var speed: CGFloat = 30
    /// Space between the end of the text and its repeat.
    var gap: CGFloat = 48
    /// Seconds it rests at the start before each scroll.
    var pause: Double = 2.5

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var textWidth: CGFloat = 0
    @State private var boxWidth: CGFloat = 0
    @State private var start = Date()

    private var overflows: Bool { boxWidth > 0 && textWidth > boxWidth + 1 }

    var body: some View {
        // An invisible copy sets the height; the visible text is drawn on top.
        Text(text)
            .font(font)
            .lineLimit(1)
            .hidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { boxWidth = $0 }
            .background(alignment: .leading) {
                // The text's full natural width.
                Text(text)
                    .font(font)
                    .lineLimit(1)
                    .fixedSize()
                    .hidden()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { textWidth = $0 }
            }
            .overlay(alignment: .leading) {
                if overflows && !reduceMotion {
                    TimelineView(.animation(minimumInterval: nil, paused: !isActive)) { context in
                        let shift = offset(at: context.date)
                        HStack(spacing: gap) {
                            label
                            label
                        }
                        .fixedSize()
                        .offset(x: -shift)
                        .frame(width: boxWidth, alignment: .leading)
                        .clipped()
                        // Fades out at the end; while scrolling, letters also fade at the start.
                        .mask { TextEdgeFade(leading: min(16, shift)) }
                    }
                } else {
                    Text(text)
                        .font(font)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .onChange(of: text) { start = Date() }
            .onChange(of: isActive) { start = Date() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
    }

    private var label: some View {
        Text(text).font(font).lineLimit(1).fixedSize()
    }

    private func offset(at date: Date) -> CGFloat {
        let distance = textWidth + gap
        let cycle = pause + Double(distance / speed)
        let t = max(0, date.timeIntervalSince(start)).truncatingRemainder(dividingBy: cycle)
        return t < pause ? 0 : CGFloat(t - pause) * speed
    }
}

/// One line of text that, when it's too long, fades out at the end instead of ending in "…".
/// Unlike "…" (which jumps a letter at a time as the space changes), the fade stays put, so this
/// is used for text that moves and resizes while the player opens and closes. At rest it looks
/// exactly like `MarqueeText` before it starts scrolling, so the two can swap without a jump.
struct FadedLineText: View {
    let text: String
    var font: Font

    var body: some View {
        // An invisible copy sets the height; the full-length text is drawn on top and cut off.
        Text(text)
            .font(font)
            .lineLimit(1)
            .hidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                Text(text)
                    .font(font)
                    .lineLimit(1)
                    .fixedSize()
            }
            .clipped()
            .mask { TextEdgeFade() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
    }
}

/// A mask that softly fades text out over its last points (and optionally in over its first).
struct TextEdgeFade: View {
    var leading: CGFloat = 0
    var trailing: CGFloat = 24

    var body: some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: max(0, leading))
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: trailing)
        }
    }
}

// MARK: - Reactive mascot

/// The theme's mascot with a base mood that reacts to taps (a random face) and to
/// `reactTo` changing (a wink), then settles back.
struct ReactiveMascot: View {
    var size: CGFloat
    var mood: MascotMood
    var headphones = true
    /// Change this value to make the mascot wink (e.g. pass the id of a new bookmark).
    var reactTo: AnyHashable? = nil
    var reactionMood: MascotMood = .wink

    @State private var reaction: MascotMood?
    @State private var reactionTask: Task<Void, Never>?

    var body: some View {
        MascotView(size: size, mood: reaction ?? mood, headphones: headphones)
            .contentShape(Rectangle())
            .onTapGesture {
                let options: [MascotMood] = [.excited, .wink, .surprised, .curious].filter { $0 != reaction }
                react(options.randomElement() ?? .excited)
            }
            .onChange(of: reactTo) { _, newValue in
                if newValue != nil { react(reactionMood) }
            }
            .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: reaction)
            .accessibilityElement()
            .accessibilityLabel("Mascot")
            .accessibilityHint("Tap to say hi")
            .accessibilityAddTraits(.isButton)
    }

    private func react(_ mood: MascotMood) {
        reactionTask?.cancel()
        reaction = mood
        reactionTask = Task {
            try? await Task.sleep(for: .seconds(1.8))
            if !Task.isCancelled { reaction = nil }
        }
    }
}

// MARK: - Cosmos background

/// The Cosmos theme's page background: a deep night-sky gradient with small dots wandering
/// around it, each on its own slow, meandering path. Most are pale; about a quarter are gold.
/// Subtle on purpose. The dots hold still with Reduce Motion or with animations off in Settings.
struct CosmosBackground: View {
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.pageIsVisible) private var pageIsVisible
    private static let start = Date()

    private struct Dot {
        var x, y, size: CGFloat
        /// How far it wanders from its home spot (fraction of the screen), and how fast.
        var range: CGFloat
        var fx1, fx2, fy1, fy2: Double
        var px1, px2, py1, py2: Double
        var twinklePhase, twinkleSpeed: Double
        var gold: Bool
    }

    /// Fixed dots (unit square), the same every launch.
    private static let dots: [Dot] = {
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func next() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 11) / Double(1 << 53)
        }
        func frequency() -> Double { 0.02 + next() * 0.06 }   // one wander every ~15–50 s
        func phase() -> Double { next() * .pi * 2 }
        return (0..<56).map { i in
            let gold = i % 4 == 0
            return Dot(x: CGFloat(next()), y: CGFloat(next()),
                       size: CGFloat(0.9 + next() * 1.3) + (gold ? 0.6 : 0),
                       range: CGFloat(0.02 + next() * 0.05),
                       fx1: frequency(), fx2: frequency() * 1.7, fy1: frequency(), fy2: frequency() * 1.3,
                       px1: phase(), px2: phase(), py1: phase(), py2: phase(),
                       twinklePhase: phase(), twinkleSpeed: 0.3 + next() * 0.5,
                       gold: gold)
        }
    }()

    private static let goldColor = Color(hex: 0xFFD27A)
    private static let paleColor = Color(hex: 0xDDE3FF)

    var body: some View {
        let moving = settings.backgroundMotionEnabled && !reduceMotion && pageIsVisible
        ZStack {
            LinearGradient(colors: [Color(hex: 0x10153F), Color(hex: 0x0A0E2A), Color(hex: 0x060920)],
                           startPoint: .top, endPoint: .bottom)
            // A faint violet haze in one corner, so the sky isn't flat.
            RadialGradient(colors: [Color(hex: 0x6B4FD8).opacity(0.18), .clear],
                           center: UnitPoint(x: 0.9, y: 0.05), startRadius: 0, endRadius: 420)
            TimelineView(.animation(minimumInterval: 1.0 / 15, paused: !moving)) { context in
                let t = moving ? context.date.timeIntervalSince(Self.start) : 0
                Canvas { ctx, size in
                    let reach = min(size.width, size.height)
                    for dot in Self.dots {
                        // Two slow sine waves per axis with different speeds: a meandering path
                        // that never quite repeats, rather than a straight drift.
                        let wx = sin(t * dot.fx1 * 2 * .pi + dot.px1) + 0.6 * sin(t * dot.fx2 * 2 * .pi + dot.px2)
                        let wy = sin(t * dot.fy1 * 2 * .pi + dot.py1) + 0.6 * sin(t * dot.fy2 * 2 * .pi + dot.py2)
                        let p = CGPoint(x: dot.x * size.width + CGFloat(wx) * dot.range * reach,
                                        y: dot.y * size.height + CGFloat(wy) * dot.range * reach)
                        let twinkle = moving ? 0.5 + 0.5 * sin(t * dot.twinkleSpeed * 2 + dot.twinklePhase) : 0.6
                        let alpha = dot.gold ? 0.45 + 0.45 * twinkle : 0.15 + 0.45 * twinkle
                        let rect = CGRect(x: p.x - dot.size / 2, y: p.y - dot.size / 2, width: dot.size, height: dot.size)
                        ctx.fill(Path(ellipseIn: rect),
                                 with: .color((dot.gold ? Self.goldColor : Self.paleColor).opacity(alpha)))
                    }
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

extension EnvironmentValues {
    /// False for a tab page that isn't showing (or is under the open player): its moving
    /// background and animations pause.
    @Entry var pageIsVisible: Bool = true
}

// MARK: - Snowfall

/// Soft snow drifting down behind the pages (Settings → Appearance → Snowfall): small round
/// flakes of different sizes falling at different speeds, each swaying gently, wrapping round to
/// the top. White on dark backgrounds; on light ones a pale tint of the theme's accent, so it
/// still shows. Holds still with Reduce Motion, with animations off, or while the page is hidden.
struct SnowfallView: View {
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.pageIsVisible) private var pageIsVisible
    @Environment(\.colorScheme) private var colorScheme
    private static let start = Date()

    private struct Flake {
        var x, size: CGFloat
        /// Screen heights per second.
        var speed: Double
        var offset: Double
        var swayAmount: CGFloat
        var swaySpeed, swayPhase: Double
        var alpha: Double
    }

    private static let flakes: [Flake] = {
        var seed: UInt64 = 0xC0FFEE1234567
        func next() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 11) / Double(1 << 53)
        }
        return (0..<44).map { _ in
            let depth = 0.35 + next() * 0.65            // nearer flakes: bigger, faster, brighter
            return Flake(x: CGFloat(next()), size: CGFloat(1.6 + 3.2 * depth),
                         speed: 0.018 + 0.035 * depth, offset: next(),
                         swayAmount: CGFloat(6 + 14 * depth), swaySpeed: 0.3 + next() * 0.5,
                         swayPhase: next() * .pi * 2, alpha: 0.35 + 0.5 * depth)
        }
    }()

    var body: some View {
        let moving = settings.backgroundMotionEnabled && !reduceMotion && pageIsVisible
        let dark = colorScheme == .dark
        let color: Color = dark ? .white : Theme.accent
        let strength = dark ? 0.75 : 0.28

        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !moving)) { context in
            let t = moving ? context.date.timeIntervalSince(Self.start) : 0
            Canvas { ctx, size in
                for flake in Self.flakes {
                    var y = (flake.offset + t * flake.speed).truncatingRemainder(dividingBy: 1.08) - 0.04
                    if y < -0.04 { y += 1.08 }
                    let x = flake.x * size.width + flake.swayAmount * CGFloat(sin(t * flake.swaySpeed + flake.swayPhase))
                    let rect = CGRect(x: x - flake.size / 2, y: CGFloat(y) * size.height - flake.size / 2,
                                      width: flake.size, height: flake.size)
                    ctx.fill(Path(ellipseIn: rect), with: .color(color.opacity(flake.alpha * strength)))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Cover smoke

/// The open player's background under the smoke themes (Pink smoke, Cosmos): the same slowly
/// folding smoke as the pages, coloured from the book's cover: its clear accent in the deepest
/// folds, then its pastels, up to near-white crests. Kept light so the player's text reads.
/// Holds still with Reduce Motion or with animations off.
struct CoverSmokeBackground: View {
    var theme: CoverTheme
    var isActive: Bool
    /// Lowest tone (0…1): how deep the darkest folds go.
    var lightness: Float = 0.32

    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let start = Date()

    @Environment(\.displayScale) private var displayScale

    /// One of the cover's smoke tints (falls back to the theme's soft colours).
    private func hue(_ i: Int) -> Color {
        let hues = theme.smokeHues
        if hues.indices.contains(i) { return hues[i] }
        return [theme.deep, theme.mid, theme.chip][i % 3]
    }

    var body: some View {
        let moving = isActive && settings.backgroundMotionEnabled && !reduceMotion
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !moving)) { context in
            let time = Float(context.date.timeIntervalSince(Self.start).truncatingRemainder(dividingBy: 3600))
            // Full resolution, as before (the low-resolution version looked worse).
            GeometryReader { geo in
                Rectangle()
                    .fill(.white)
                    .colorEffect(ShaderLibrary.coverSmokeMix(
                        .float2(geo.size), .float(time), .float(lightness),
                        .color(hue(0)), .color(hue(1)), .color(hue(2)),
                        .color(theme.light), .color(Color.white)))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Smoke tints

/// The page smoke's colours, one per app theme: the first three have their own shaders; the
/// rest use the five-tone `coverSmoke` shader with the theme's `smokeStops`.
enum SmokeTint {
    case pink, purple, sky, stops(ThemeID)

    /// The current app theme's.
    static var current: SmokeTint {
        switch Theme.current {
        case .cloudNine: .sky
        case .cottonCandy: .pink
        case .moonberry: .purple
        default: .stops(Theme.current)
        }
    }

    func shader(_ size: Shader.Argument, _ time: Shader.Argument, _ lightness: Shader.Argument) -> Shader {
        switch self {
        case .pink: ShaderLibrary.pinkSmoke(size, time, lightness)
        case .purple: ShaderLibrary.purpleSmoke(size, time, lightness)
        case .sky: ShaderLibrary.skySmoke(size, time, lightness)
        case .stops(let theme):
            ShaderLibrary.coverSmoke(size, time, lightness,
                                     .color(Color(hex: theme.smokeStops[0])), .color(Color(hex: theme.smokeStops[1])),
                                     .color(Color(hex: theme.smokeStops[2])), .color(Color(hex: theme.smokeStops[3])),
                                     .color(Color(hex: theme.smokeStops[4])))
        }
    }
}

/// The page background in every theme: the theme's pale, slow smoke with a soft white veil, so
/// grey secondary text keeps its contrast.
struct PageSmoke: View {
    var isActive: Bool
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        PinkSmokeBackground(isActive: isActive, lightness: Theme.isDark ? 0.55 : 0.8, pace: 0.6,
                            tint: SmokeTint.current)
            // A soft veil so secondary text keeps its contrast: white on light themes, black on dark.
            .overlay(Theme.isDark ? Color.black.opacity(0.2) : Color.white.opacity(0.3))
            .id(settings.playerBackground)
    }
}

// MARK: - Theme particles

/// Little things floating behind the pages, one kind per theme: soft dots (Cloud Nine), hearts
/// (Cotton Candy), twinkling stars (Moonberry), fluttering butterflies (Lemon Drop), sparkles
/// (Coral Reef), dandelion clocks (Matcha Latte) and glowing fireflies (Firefly Night).
/// Each one wanders slowly in its own direction with a gentle downward drift (a "falling" feel),
/// wrapping round the edges. Small and slightly bigger ones are mixed, in light tints of the
/// theme's colours. Tap a dandelion and it bursts into drifting seeds (see `ParticleField`).
/// Settings → Appearance: the toggle (named after them), Amount and Speed.
/// Holds still with Reduce Motion, with animations off, or while the page is hidden.
struct ThemeParticles: View {
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.pageIsVisible) private var pageIsVisible

    var body: some View {
        let kind = Theme.current.particles
        let moving = settings.backgroundMotionEnabled && !reduceMotion && pageIsVisible
        let count = min(ParticleField.bits.count, max(1, settings.particleCount))
        let speed = settings.particleSpeed
        let colors = ParticleField.colors()

        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !moving)) { context in
            let field = ParticleField.shared
            let now = context.date
            let t = moving ? now.timeIntervalSince(field.start) : 0
            let bursts = field.liveBursts(at: now)
            let bald = field.bald

            Canvas { ctx, size in
                field.lastSize = size
                for (index, bit) in ParticleField.bits.prefix(count).enumerated() {
                    let p = ParticleField.position(bit, t: t, speed: speed, size: size)
                    let wave = sin(t * bit.wanderSpeed * 3 + bit.phase)
                    var opacity = bit.alpha
                    if kind.twinkle { opacity *= 0.35 + 0.65 * (0.5 + 0.5 * wave) }
                    let color = colors[bit.colorIndex % colors.count]

                    switch kind.shape {
                    case .dot:
                        var layer = ctx
                        layer.opacity = opacity
                        if kind.glows { layer.addFilter(.shadow(color: color.opacity(0.9), radius: 6)) }
                        let r = bit.size * 0.32 * kind.scale
                        layer.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                                   with: .color(color))

                    case .symbol:
                        guard let symbol = ctx.resolveSymbol(id: bit.colorIndex % colors.count) else { continue }
                        var layer = ctx
                        layer.opacity = opacity
                        layer.translateBy(x: p.x, y: p.y)
                        layer.rotate(by: .radians(wave * 0.25))
                        let scale = bit.size / 14 * kind.scale
                        layer.scaleBy(x: scale, y: scale)
                        layer.draw(symbol, at: .zero)

                    case .butterfly:
                        ParticleField.drawButterfly(in: ctx, at: p, size: bit.size * 1.4, color: color,
                                                    flap: abs(sin(t * 7 + bit.phase * 3)),
                                                    tilt: wave * 0.35, opacity: opacity)

                    case .dandelion:
                        // A tapped clock is bald for a while, then grows back.
                        var grown = 1.0
                        if let when = bald[index] {
                            let since = now.timeIntervalSince(when)
                            grown = min(1, max(0, (since - 5) / 3))
                        }
                        ParticleField.drawDandelion(in: ctx, at: p, radius: bit.size * 0.95, grown: grown,
                                                    turn: t * 0.15 + bit.phase, opacity: min(1, opacity + 0.2))
                    }
                }

                // Seeds blowing away from tapped dandelions.
                for burst in bursts {
                    ParticleField.drawSeeds(in: ctx, burst: burst, now: now)
                }
            } symbols: {
                if case .symbol(let name) = kind.shape {
                    ForEach(Array(colors.enumerated()), id: \.offset) { index, color in
                        Image(systemName: name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(color)
                            .tag(index)
                    }
                }
            }
        }
        .id(settings.playerBackground)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// What floats behind a theme's pages.
struct ThemeParticleKind {
    enum Shape { case dot, symbol(String), butterfly, dandelion }
    let shape: Shape
    /// Fades in and out as it floats (stars, sparkles, fireflies).
    var twinkle = false
    /// A soft glow round each one (fireflies).
    var glows = false
    /// Size relative to the other themes' (fireflies are tiny).
    var scale: CGFloat = 1
    /// The Settings toggle's name.
    let name: String
}

extension ThemeID {
    var particles: ThemeParticleKind {
        switch self {
        case .cloudNine: ThemeParticleKind(shape: .dot, name: "Floating dots")
        case .cottonCandy: ThemeParticleKind(shape: .symbol("heart.fill"), name: "Floating hearts")
        case .moonberry: ThemeParticleKind(shape: .symbol("star.fill"), twinkle: true, name: "Twinkling stars")
        case .lemonDrop: ThemeParticleKind(shape: .butterfly, name: "Butterflies")
        case .coralReef: ThemeParticleKind(shape: .symbol("sparkle"), twinkle: true, name: "Sparkles")
        case .matchaLatte: ThemeParticleKind(shape: .dandelion, name: "Dandelions")
        case .fireflyNight: ThemeParticleKind(shape: .dot, twinkle: true, glows: true, scale: 0.7, name: "Fireflies")
        }
    }
}

// MARK: - Particle field (motion, taps, drawing)

/// The particles' shared clock, their paths, and the dandelions' taps. Positions are worked out
/// from the time alone, so a tap can find which dandelion is under the finger.
final class ParticleField {
    static let shared = ParticleField()

    /// The shared clock: every page's particles move together.
    let start = Date()
    /// The particle canvas's size (full screen), for working out tap hits.
    var lastSize: CGSize = .zero
    /// Dandelions tapped (by index), and when: bald, then growing back.
    private(set) var bald: [Int: Date] = [:]
    private(set) var bursts: [Burst] = []

    struct Burst {
        var origin: CGPoint
        var time: Date
        var seed: UInt64
    }

    struct Bit {
        var x, y: CGFloat          // starting spot (0…1)
        var angle: Double          // the direction it wanders
        var speed: Double          // screen fractions per second
        var wander: CGFloat        // how far its path curls
        var wanderSpeed: Double
        var phase: Double
        var size: CGFloat
        var alpha: Double
        var colorIndex: Int
    }

    /// Enough for the "Lots" setting; `AppSettings.particleCount` of them are drawn.
    static let bits: [Bit] = {
        var seed: UInt64 = 0x5EED5EED1234
        func next() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 11) / Double(1 << 53)
        }
        return (0..<28).map { _ in
            // A mix: about a third a little bigger, the rest small.
            let big = next() < 0.35
            return Bit(x: CGFloat(next()), y: CGFloat(next()),
                       angle: next() * 2 * .pi,
                       speed: 0.008 + next() * 0.01,
                       wander: CGFloat(0.015 + next() * 0.03),
                       wanderSpeed: 0.08 + next() * 0.12,
                       phase: next() * 2 * .pi,
                       size: big ? CGFloat(13 + next() * 4) : CGFloat(7 + next() * 3),
                       alpha: 0.55 + next() * 0.35,
                       colorIndex: Int(next() * 3))
        }
    }()

    /// Light tints of the theme's colours: a mix of three, each well lightened (they used to be
    /// the full accent, which looked dark).
    static func colors() -> [Color] {
        if Theme.isDark {
            return [Theme.accent.mix(with: .white, by: 0.25), Color(hex: 0xFFE7A3), Color(hex: 0xC8F5D2)]
        }
        return [Theme.accent.mix(with: .white, by: 0.5),
                Theme.lilac.mix(with: .white, by: 0.45),
                Theme.blush.mix(with: .white, by: 0.5)]
    }

    /// Where a particle is at time `t`: drifting its own way with a slow curl, and a gentle pull
    /// downwards (the falling feel), wrapping round every edge.
    static func position(_ b: Bit, t: Double, speed: Double, size: CGSize) -> CGPoint {
        let s = b.speed * speed
        let vx = cos(b.angle) * s
        let vy = sin(b.angle) * s * 0.6 + s * 0.6          // any direction, leaning downwards
        var x = Double(b.x) + vx * t + Double(b.wander) * sin(t * b.wanderSpeed + b.phase)
        var y = Double(b.y) + vy * t + Double(b.wander) * cos(t * b.wanderSpeed * 0.8 + b.phase * 1.3)
        func wrap(_ v: Double) -> Double {
            let span = 1.16
            var r = (v + 0.08).truncatingRemainder(dividingBy: span)
            if r < 0 { r += span }
            return r - 0.08
        }
        x = wrap(x)
        y = wrap(y)
        return CGPoint(x: x * size.width, y: y * size.height)
    }

    // MARK: Taps (dandelions)

    /// A tap on the screen (global points): if a dandelion is under it, it bursts.
    /// On the main actor: it reads the app's settings.
    @MainActor
    func tap(at point: CGPoint) {
        let settings = AppSettings.shared
        guard Theme.current.particles.isDandelion, settings.snowfall, lastSize.width > 0 else { return }
        let now = Date()
        let moving = settings.backgroundMotionEnabled && !UIAccessibility.isReduceMotionEnabled
        let t = moving ? now.timeIntervalSince(start) : 0
        let count = min(Self.bits.count, max(1, settings.particleCount))
        var best: (index: Int, distance: CGFloat, point: CGPoint)?
        for (index, bit) in Self.bits.prefix(count).enumerated() {
            if let when = bald[index], now.timeIntervalSince(when) < 8 { continue }
            let p = Self.position(bit, t: t, speed: settings.particleSpeed, size: lastSize)
            let d = hypot(p.x - point.x, p.y - point.y)
            if d < bit.size * 0.95 + 26, d < (best?.distance ?? .infinity) { best = (index, d, p) }
        }
        guard let best else { return }
        bald[best.index] = now
        bursts.append(Burst(origin: best.point, time: now, seed: UInt64.random(in: 1...UInt64.max)))
        bursts.removeAll { now.timeIntervalSince($0.time) > 7 }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.6)
    }

    func liveBursts(at now: Date) -> [Burst] {
        bursts.filter { now.timeIntervalSince($0.time) < 7 }
    }

    // MARK: Drawing

    /// A butterfly: two pairs of rounded wings round a slim body, flapping (`flap` 0…1).
    static func drawButterfly(in ctx: GraphicsContext, at p: CGPoint, size: CGFloat, color: Color,
                              flap: Double, tilt: Double, opacity: Double) {
        var layer = ctx
        layer.opacity = opacity
        layer.translateBy(x: p.x, y: p.y)
        layer.rotate(by: .radians(tilt))
        let open = CGFloat(0.35 + 0.65 * flap)           // wings fold towards the body
        let w = size * 0.5, h = size * 0.42
        for side in [-1.0, 1.0] {
            var wing = layer
            wing.scaleBy(x: CGFloat(side) * open, y: 1)
            // Upper wing (bigger), lower wing (smaller), both leaning outwards.
            wing.fill(Path(ellipseIn: CGRect(x: 0, y: -h * 1.05, width: w, height: h * 1.1))
                        .applying(CGAffineTransform(rotationAngle: -0.35)), with: .color(color))
            wing.fill(Path(ellipseIn: CGRect(x: 0, y: -h * 0.05, width: w * 0.72, height: h * 0.85))
                        .applying(CGAffineTransform(rotationAngle: 0.35)), with: .color(color.opacity(0.85)))
        }
        layer.fill(Path(roundedRect: CGRect(x: -size * 0.04, y: -size * 0.32, width: size * 0.08, height: size * 0.62),
                        cornerRadius: size * 0.04),
                   with: .color(color.mix(with: .black, by: 0.35)))
    }

    /// A dandelion clock: a small centre, fine filaments radiating out, each tipped with a tiny
    /// tuft, over a faint glow. `grown` 0…1 (0 = just the bald centre, after a tap).
    static func drawDandelion(in ctx: GraphicsContext, at p: CGPoint, radius: CGFloat, grown: Double,
                              turn: Double, opacity: Double) {
        var layer = ctx
        layer.opacity = opacity
        layer.translateBy(x: p.x, y: p.y)
        let tint = Theme.accent.mix(with: .white, by: 0.25)
        if grown > 0 {
            let r = radius * CGFloat(0.4 + 0.6 * grown)
            layer.fill(Path(ellipseIn: CGRect(x: -r * 1.15, y: -r * 1.15, width: r * 2.3, height: r * 2.3)),
                       with: .radialGradient(Gradient(colors: [.white.opacity(0.55 * grown), .white.opacity(0)]),
                                             center: .zero, startRadius: 0, endRadius: r * 1.15))
            let filaments = 26
            var lines = Path()
            var tufts = Path()
            for i in 0..<filaments {
                let a = Double(i) / Double(filaments) * 2 * .pi + turn + (i.isMultiple(of: 2) ? 0.06 : -0.04)
                let len = r * (i.isMultiple(of: 3) ? 0.92 : 1.0)
                let end = CGPoint(x: cos(a) * len, y: sin(a) * len)
                lines.move(to: CGPoint(x: cos(a) * r * 0.18, y: sin(a) * r * 0.18))
                lines.addLine(to: end)
                // The tuft: three tiny hairs fanning out at the tip.
                for k in -1...1 {
                    let b = a + Double(k) * 0.5
                    tufts.move(to: end)
                    tufts.addLine(to: CGPoint(x: end.x + cos(b) * r * 0.2, y: end.y + sin(b) * r * 0.2))
                }
            }
            layer.stroke(lines, with: .color(tint.opacity(0.9 * grown)), lineWidth: 0.5)
            layer.stroke(tufts, with: .color(Color.white.opacity(0.95 * grown)), lineWidth: 0.6)
            layer.stroke(tufts, with: .color(tint.opacity(0.5 * grown)), lineWidth: 0.3)
        }
        let c = max(1.6, radius * 0.16)
        layer.fill(Path(ellipseIn: CGRect(x: -c, y: -c, width: c * 2, height: c * 2)),
                   with: .color(Theme.accent.mix(with: .white, by: 0.1).opacity(0.85)))
    }

    /// Seeds from a tapped dandelion: each a tiny seed on a slim stalk under a feathery
    /// parachute, flung out, then carried off on a gentle breeze (to the right and a little up),
    /// fluttering, turning and fading.
    static func drawSeeds(in ctx: GraphicsContext, burst: Burst, now: Date) {
        let age = now.timeIntervalSince(burst.time)
        guard age >= 0, age < 7 else { return }
        var seed = burst.seed
        func next() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 11) / Double(1 << 53)
        }
        let tint = Theme.accent.mix(with: .white, by: 0.25)
        for _ in 0..<18 {
            let angle = next() * 2 * .pi
            let fling = 30 + next() * 50                  // points per second outwards, slowing
            let wind = 22 + next() * 26                   // the breeze, to the right
            let lift = -(6 + next() * 10)                 // and a little up
            let flutter = 5 + next() * 7
            let spin = (next() - 0.5) * 1.2
            let phase = next() * 2 * .pi
            let life = 4.5 + next() * 2.3
            guard age < life else { continue }
            let slow = (1 - exp(-age * 1.4)) / 1.4        // the outward fling eases off
            let x = burst.origin.x + CGFloat(cos(angle) * fling * slow + wind * age * age * 0.18 + wind * age * 0.25
                                             + flutter * sin(age * 3 + phase))
            let y = burst.origin.y + CGFloat(sin(angle) * fling * slow + lift * age + 3 * age * age * 0.2)
            let fade = age < life - 1.2 ? 1 : max(0, (life - age) / 1.2)

            var layer = ctx
            layer.opacity = 0.9 * fade
            layer.translateBy(x: x, y: y)
            layer.rotate(by: .radians(spin * age + 0.25 * sin(age * 2.5 + phase)))
            // Seed (a tiny dark grain) at the bottom, stalk up to the parachute.
            layer.fill(Path(ellipseIn: CGRect(x: -0.9, y: 5, width: 1.8, height: 3.6)),
                       with: .color(Color(hex: 0x6B5B3E).opacity(0.85)))
            var stalk = Path()
            stalk.move(to: CGPoint(x: 0, y: 5))
            stalk.addLine(to: CGPoint(x: 0, y: -4))
            layer.stroke(stalk, with: .color(tint.opacity(0.9)), lineWidth: 0.5)
            // The parachute: fine hairs fanning upwards from the top of the stalk.
            var hairs = Path()
            for i in 0..<11 {
                let a = -Double.pi / 2 + (Double(i) / 10 - 0.5) * 2.4
                hairs.move(to: CGPoint(x: 0, y: -4))
                hairs.addLine(to: CGPoint(x: cos(a) * 6.5, y: -4 + sin(a) * 6.5))
            }
            layer.stroke(hairs, with: .color(Color.white.opacity(0.95)), lineWidth: 0.5)
            layer.stroke(hairs, with: .color(tint.opacity(0.45)), lineWidth: 0.3)
        }
    }
}

extension ThemeParticleKind {
    var isDandelion: Bool {
        if case .dandelion = shape { return true }
        return false
    }
}

// MARK: - Low-resolution shader

/// Fills the space with a shader worked out on a much smaller grid (about one sample per 2.5
/// points instead of one per pixel), then scaled up smoothly. For soft effects like the smoke this
/// looks the same and costs a small fraction (roughly 1/50th) of the GPU work, which kept the app
/// lagging while typing over it.
struct LowResShader: View {
    var displayScale: CGFloat
    var shader: (CGSize) -> Shader

    var body: some View {
        GeometryReader { geo in
            let divisor = max(1, displayScale * 2.5)
            let small = CGSize(width: max(2, (geo.size.width / divisor).rounded(.up)),
                               height: max(2, (geo.size.height / divisor).rounded(.up)))
            Rectangle()
                .fill(.white)
                .colorEffect(shader(small))
                .frame(width: small.width, height: small.height)
                .drawingGroup()
                .scaleEffect(divisor, anchor: .topLeading)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                .clipped()
        }
    }
}
