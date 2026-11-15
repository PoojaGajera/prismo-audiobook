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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private var animated: Bool { settings.backgroundMotionEnabled && !reduceMotion }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Theme.background

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
                DragGesture(minimumDistance: 0)
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

    /// Used before a cover has loaded, or for books without one: a soft periwinkle.
    static let fallback = CoverTheme(hue: 0.62, saturation: 0.45)

    /// - Parameters:
    ///   - hue: the cover's dominant hue (0…1).
    ///   - saturation: how colourful that hue is on the cover (0 = a grey or black-and-white cover).
    init(hue: CGFloat, saturation: CGFloat) {
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

extension EnvironmentValues {
    /// The current book's cover colours (set by the player for itself and its sheets).
    @Entry var coverTheme: CoverTheme = .fallback
}

/// Works out a cover's dominant colour (its most common vivid hue, not the muddy average).
@MainActor
enum CoverPalette {
    private static var cache: [String: CoverTheme] = [:]

    static func theme(for book: Book) -> CoverTheme {
        guard let image = CoverCache.image(for: book) else { return .fallback }
        let key = "\(book.id)#\(book.coverVersion ?? 0)"
        if let cached = cache[key] { return cached }
        let theme = dominantHue(of: image).map { CoverTheme(hue: $0.hue, saturation: $0.saturation) } ?? .fallback
        cache[key] = theme
        return theme
    }

    /// The cover's accent colour (buttons, progress).
    static func color(for book: Book) -> Color? {
        theme(for: book).accent
    }

    private static func dominantHue(of image: UIImage) -> (hue: CGFloat, saturation: CGFloat)? {
        guard let cgImage = image.cgImage else { return nil }
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
        guard drawn else { return nil }

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
        guard total / count > 0.02 else { return (0.6, 0) }

        // The strongest hue, counting its neighbours too (the histogram wraps round).
        func around(_ i: Int) -> [Int] { [(i + bins - 1) % bins, i, (i + 1) % bins] }
        func sum(_ values: [Double], over bins: [Int]) -> Double {
            var total = 0.0
            for i in bins { total += values[i] }
            return total
        }
        var best = 0
        var bestScore = -1.0
        for i in 0..<bins {
            let score = sum(weight, over: around(i))
            if score > bestScore {
                best = i
                bestScore = score
            }
        }
        let group = around(best)
        let groupWeight = sum(weight, over: group)
        guard groupWeight > 0 else { return (0.6, 0) }
        var hue = atan2(sum(hueY, over: group), sum(hueX, over: group)) / (2 * Double.pi)
        if hue < 0 { hue += 1 }
        let saturation = sum(satSum, over: group) / groupWeight
        return (CGFloat(hue), CGFloat(saturation))
    }
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
