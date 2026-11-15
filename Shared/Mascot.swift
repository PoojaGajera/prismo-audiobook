import SwiftUI

/// Expressions shared by every mascot.
enum MascotMood: Hashable, CaseIterable {
    case happy      // idle: slow float, occasional blink
    case listening  // grooving along (used while playing or working)
    case curious    // looks up and to the side
    case excited    // bouncy, wide-eyed, sparkles
    case sleepy     // heavy lids, floating z's
    case sad        // worried brows, looks down
    case wink       // one eye closed
    case surprised  // brows up, little "o"
}

/// The app mascot (the blue scalloped badge).
struct MascotView: View {
    typealias Mood = MascotMood

    var size: CGFloat = 120
    var mood: MascotMood = .happy
    var headphones = false
    /// 0 = headphones/earbuds off (hidden), 1 = on. Animate it for the "put on" moment.
    var headphonesProgress: CGFloat = 1
    var animated = true

    var body: some View {
        BadgeMascotView(size: size, mood: mood, headphones: headphones,
                        headphonesProgress: headphonesProgress,
                        animated: animated && Theme.motionEnabled)
    }
}

/// The blue scalloped-badge mascot, drawn live so it can blink, glance around and bob along.
/// Artwork coordinates follow the original 1000×1000 SVG.
struct BadgeMascotView: View {
    typealias Mood = MascotMood

    var size: CGFloat = 120
    var mood: Mood = .happy
    var headphones = false
    /// 0 = headphones floating above (hidden), 1 = on the head. Animate it for the "put on" moment.
    var headphonesProgress: CGFloat = 1
    var animated = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isAnimating: Bool { animated && !reduceMotion }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isAnimating)) { context in
            let t = isAnimating ? context.date.timeIntervalSinceReferenceDate : 0
            ZStack {
                MascotFace(mood: mood, blink: eyeOpenness(t), look: look(t))
                if headphones {
                    MascotHeadphones()
                        .offset(y: -(1 - headphonesProgress) * size * 0.55)
                        .opacity(Double(headphonesProgress))
                }
            }
            .rotationEffect(.degrees(tilt(t)))
            .offset(y: bob(t))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    // MARK: Motion

    private func bob(_ t: Double) -> CGFloat {
        switch mood {
        case .listening: return CGFloat(sin(t * 4.0)) * size * 0.025
        case .excited: return -CGFloat(abs(sin(t * 6))) * size * 0.04
        case .sleepy: return CGFloat(sin(t * 0.9)) * size * 0.01
        default: return CGFloat(sin(t * 1.8)) * size * 0.02
        }
    }

    private func tilt(_ t: Double) -> Double {
        switch mood {
        case .listening: return sin(t * 2.0) * 5
        case .curious, .surprised: return -6 + sin(t * 1.2) * 1.5
        case .sleepy: return 6 + sin(t * 0.6) * 2
        case .sad: return 3
        case .wink: return -4
        case .happy, .excited: return sin(t * 0.9) * 2
        }
    }

    /// Pupil offset in artwork units.
    private func look(_ t: Double) -> CGSize {
        switch mood {
        case .listening: return CGSize(width: sin(t * 0.7) * 10, height: -5)
        case .curious, .surprised: return CGSize(width: 13, height: -11)
        case .sad, .sleepy: return CGSize(width: 0, height: 12)
        case .happy, .excited, .wink: return CGSize(width: sin(t * 0.35) * 6, height: 0)
        }
    }

    /// Per-eye openness (1 open … ~0 closed), combining blinks with the mood.
    private func eyeOpenness(_ t: Double) -> (left: CGFloat, right: CGFloat) {
        let blink = Self.blink(t)
        switch mood {
        case .sleepy: return (min(blink, 0.4), min(blink, 0.4))
        case .wink: return (0.08, blink)
        default: return (blink, blink)
        }
    }

    /// 1 = open, ~0 = closed. Blinks every 4.2 s, with a double blink every third time.
    static func blink(_ t: Double) -> CGFloat {
        guard t > 0 else { return 1 }
        let period = 4.2
        let phase = t.truncatingRemainder(dividingBy: period)
        let cycle = Int(t / period)
        func closeness(_ x: Double) -> CGFloat {
            let duration = 0.18
            guard x >= 0, x < duration else { return 1 }
            return CGFloat(max(0.08, abs(1 - 2 * x / duration)))
        }
        var value = closeness(phase)
        if cycle % 3 == 0 { value = min(value, closeness(phase - 0.3)) }
        return value
    }
}

/// The face: blue scalloped badge, pearl face, eyes, blush and smile.
struct MascotFace: View {
    var mood: MascotMood = .happy
    /// Openness of the left and right eye (1 open … ~0 closed).
    var blink: (left: CGFloat, right: CGFloat) = (1, 1)
    var look: CGSize = .zero

    private static let eyes: [CGPoint] = [CGPoint(x: 372.87, y: 494.65), CGPoint(x: 627.79, y: 494.65)]
    /// Highlight offsets from the eye centre and their radii.
    private static let sparkles: [(dx: CGFloat, dy: CGFloat, r: CGFloat)] = [(-19.8, -22.5, 19.8), (28.8, -4.5, 9.9), (18.9, 33.3, 7.2)]
    private static let cheeks: [(center: CGPoint, angle: CGFloat)] = [
        (CGPoint(x: 357.6, y: 541.7), 58.67),
        (CGPoint(x: 661.35, y: 533.2), -58.67),
    ]

    var body: some View {
        Canvas { ctx, size in
            let rect = CGRect(origin: .zero, size: size)
            let k = size.width / 1000
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * k, y: y * k) }

            // Badge
            ctx.fill(MascotOuterBadgeShape().path(in: rect),
                     with: .linearGradient(Gradient(colors: [Color(hex: 0x33A6FF), Theme.mascotBlue]),
                                           startPoint: pt(500, 140), endPoint: pt(500, 860)))

            // Face with a soft inner shadow along the top edge
            let face = MascotInnerBadgeShape().path(in: rect)
            ctx.fill(face, with: .color(Theme.mascotPearl))
            ctx.drawLayer { layer in
                layer.clip(to: face)
                layer.addFilter(.blur(radius: 10 * k))
                layer.stroke(face.offsetBy(dx: 0, dy: 17 * k), with: .color(.black.opacity(0.12)), lineWidth: 30 * k)
            }

            // Blush
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: 26 * k))
                for cheek in Self.cheeks {
                    let ellipse = Path(ellipseIn: CGRect(x: -34 * k, y: -14 * k, width: 68 * k, height: 28 * k))
                        .applying(CGAffineTransform(rotationAngle: cheek.angle * .pi / 180))
                        .applying(CGAffineTransform(translationX: cheek.center.x * k, y: cheek.center.y * k))
                    layer.fill(ellipse, with: .color(Theme.mascotBlush.opacity(0.9)))
                }
            }

            // Eyes
            let radius: CGFloat = 53.1
            for (index, eye) in Self.eyes.enumerated() {
                let blink = index == 0 ? self.blink.left : self.blink.right
                let cx = eye.x + look.width
                let cy = eye.y + look.height
                let eyeRect = CGRect(x: (cx - radius) * k, y: (cy - radius * blink) * k,
                                     width: radius * 2 * k, height: radius * 2 * blink * k)
                ctx.fill(Path(ellipseIn: eyeRect), with: .color(.black))
                if blink > 0.6 {
                    for s in Self.sparkles {
                        let sx = cx + s.dx * 0.9
                        let sy = cy + s.dy * blink
                        ctx.fill(Path(ellipseIn: CGRect(x: (sx - s.r) * k, y: (sy - s.r) * k, width: s.r * 2 * k, height: s.r * 2 * k)),
                                 with: .color(.white))
                    }
                }
            }

            // Mouth
            if mood == .curious || mood == .surprised || mood == .excited {
                ctx.fill(Path(ellipseIn: CGRect(x: 487 * k, y: 552 * k, width: 26 * k, height: 30 * k)), with: .color(.black))
            } else {
                ctx.fill(MascotMouthShape().path(in: rect), with: .color(.black))
            }
        }
    }
}

/// Navy band with pink ear cups, drawn on the mascot's artboard.
struct MascotHeadphones: View {
    var body: some View {
        Canvas { ctx, size in
            let k = size.width / 1000
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * k, y: y * k) }

            var band = Path()
            band.move(to: pt(150, 520))
            band.addCurve(to: pt(500, 105), control1: pt(150, 250), control2: pt(300, 105))
            band.addCurve(to: pt(850, 520), control1: pt(700, 105), control2: pt(850, 250))
            ctx.stroke(band, with: .linearGradient(Gradient(colors: [Color(hex: 0x1B2A52), Theme.mascotInk]),
                                                    startPoint: pt(500, 80), endPoint: pt(500, 520)),
                       style: StrokeStyle(lineWidth: 54 * k, lineCap: .round))

            var shine = Path()
            shine.move(to: pt(205, 360))
            shine.addCurve(to: pt(500, 150), control1: pt(250, 215), control2: pt(360, 150))
            ctx.stroke(shine, with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: 12 * k, lineCap: .round))

            for side in [(cushion: CGFloat(88), cup: CGFloat(62), glint: CGFloat(80)),
                         (cushion: CGFloat(784), cup: CGFloat(826), glint: CGFloat(844))] {
                ctx.fill(Path(roundedRect: CGRect(x: side.cushion * k, y: 420 * k, width: 128 * k, height: 230 * k),
                              cornerRadius: 58 * k),
                         with: .color(Theme.mascotInk))
                ctx.fill(Path(roundedRect: CGRect(x: side.cup * k, y: 438 * k, width: 112 * k, height: 196 * k),
                              cornerRadius: 52 * k),
                         with: .linearGradient(Gradient(colors: [Color(hex: 0xFF8ADF), Theme.mascotBlush]),
                                               startPoint: pt(side.cup, 438), endPoint: pt(side.cup + 112, 634)))
                ctx.fill(Path(roundedRect: CGRect(x: side.glint * k, y: 458 * k, width: 26 * k, height: 100 * k),
                              cornerRadius: 13 * k),
                         with: .color(.white.opacity(0.45)))
            }
        }
    }
}
