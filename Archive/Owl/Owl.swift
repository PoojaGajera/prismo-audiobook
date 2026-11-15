import SwiftUI

/// The owl mascot, drawn live from its parts so it can pull faces.
/// Artwork coordinates follow the original 1000×1000 SVG.
struct OwlView: View {
    var size: CGFloat = 120
    var mood: MascotMood = .happy
    var earphones = true
    /// 0 = earbuds dangling below (hidden), 1 = in the ears. Animate it for the "plug in" moment.
    var earphonesProgress: CGFloat = 1
    var animated = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var previousMood: MascotMood = .happy
    @State private var changedAt = Date.distantPast

    private var isAnimating: Bool { animated && !reduceMotion }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isAnimating)) { context in
            let now = context.date
            let t = isAnimating ? now.timeIntervalSinceReferenceDate : 0
            let progress = isAnimating ? min(1, max(0, now.timeIntervalSince(changedAt) / 0.35)) : 1
            let eased = CGFloat(progress * progress * (3 - 2 * progress))
            let pose = OwlPose.for(previousMood).blended(to: OwlPose.for(mood), amount: eased)
            OwlCanvas(pose: pose, mood: mood, t: t,
                      earphones: earphones ? earphonesProgress : 0)
        }
        .frame(width: size, height: size)
        .onChange(of: mood) { oldValue, _ in
            previousMood = oldValue
            changedAt = Date()
        }
        .accessibilityHidden(true)
    }
}

/// Facial pose: everything that eases between expressions.
struct OwlPose {
    var browTiltLeft: CGFloat = 0      // + = inner end up (worried), − = inner end down (cross)
    var browTiltRight: CGFloat = 0
    var browLiftLeft: CGFloat = 0      // − = raised
    var browLiftRight: CGFloat = 0
    var lidLeft: CGFloat = 0           // 0 open … 1 closed
    var lidRight: CGFloat = 0
    var smileLeft: CGFloat = 0         // closed "^" eye
    var smileRight: CGFloat = 0
    var pupil: CGSize = .zero
    var pupilScale: CGFloat = 1
    var beak: CGFloat = 0              // 0 closed … 1 wide open
    var blush: CGFloat = 1
    var tilt: CGFloat = 0              // degrees

    static func `for`(_ mood: MascotMood) -> OwlPose {
        var p = OwlPose()
        switch mood {
        case .happy:
            break
        case .listening:
            p.lidLeft = 1; p.lidRight = 1; p.smileLeft = 1; p.smileRight = 1
            p.browTiltLeft = 4; p.browTiltRight = 4; p.beak = 0.15
        case .curious:
            p.browLiftLeft = -28; p.browTiltLeft = -6
            p.pupil = CGSize(width: 16, height: -14); p.tilt = -9; p.beak = 0.1
        case .excited:
            p.browLiftLeft = -30; p.browLiftRight = -30
            p.pupilScale = 1.18; p.beak = 0.9
        case .sleepy:
            p.lidLeft = 0.62; p.lidRight = 0.62
            p.browLiftLeft = 10; p.browLiftRight = 10; p.browTiltLeft = 6; p.browTiltRight = 6
            p.pupil = CGSize(width: 0, height: 12); p.blush = 0; p.tilt = 5
        case .sad:
            p.browTiltLeft = 20; p.browTiltRight = 20; p.browLiftLeft = -4; p.browLiftRight = -4
            p.pupil = CGSize(width: 0, height: 16); p.lidLeft = 0.15; p.lidRight = 0.15
            p.blush = 0; p.tilt = 3
        case .wink:
            p.lidLeft = 1; p.smileLeft = 1; p.browLiftRight = -16
            p.beak = 0.3; p.pupil = CGSize(width: 6, height: 0); p.tilt = -4
        case .surprised:
            p.browLiftLeft = -42; p.browLiftRight = -42
            p.pupilScale = 0.72; p.beak = 1; p.blush = 0
        }
        return p
    }

    func blended(to other: OwlPose, amount a: CGFloat) -> OwlPose {
        func mix(_ x: CGFloat, _ y: CGFloat) -> CGFloat { x + (y - x) * a }
        var p = OwlPose()
        p.browTiltLeft = mix(browTiltLeft, other.browTiltLeft)
        p.browTiltRight = mix(browTiltRight, other.browTiltRight)
        p.browLiftLeft = mix(browLiftLeft, other.browLiftLeft)
        p.browLiftRight = mix(browLiftRight, other.browLiftRight)
        p.lidLeft = mix(lidLeft, other.lidLeft)
        p.lidRight = mix(lidRight, other.lidRight)
        p.smileLeft = mix(smileLeft, other.smileLeft)
        p.smileRight = mix(smileRight, other.smileRight)
        p.pupil = CGSize(width: mix(pupil.width, other.pupil.width), height: mix(pupil.height, other.pupil.height))
        p.pupilScale = mix(pupilScale, other.pupilScale)
        p.beak = mix(beak, other.beak)
        p.blush = mix(blush, other.blush)
        p.tilt = mix(tilt, other.tilt)
        return p
    }
}

/// Draws one frame of the owl.
struct OwlCanvas: View {
    var pose: OwlPose
    var mood: MascotMood
    var t: Double
    var earphones: CGFloat

    static let ink = Color(hex: 0x25232E)
    static let cyan = Color(hex: 0xB1EBF9)
    static let cream = Color(hex: 0xF9E8AE)
    static let white = Color(hex: 0xFDF8E6)
    static let amber = Color(hex: 0xEFB219)

    var body: some View {
        Canvas { ctx, size in
            let rect = CGRect(origin: .zero, size: size)
            let k = size.width / 1000
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * k, y: y * k) }

            // Whole-body motion
            let motion = Self.motion(mood: mood, t: t)
            ctx.translateBy(x: 500 * k, y: (700 + motion.bob) * k)
            ctx.rotate(by: .degrees(Double(pose.tilt + motion.sway)))
            ctx.translateBy(x: -500 * k, y: -700 * k)

            // Body
            let body = OwlBodyShape().path(in: rect)
            ctx.fill(body, with: .color(Self.cyan))
            ctx.fill(body, with: .linearGradient(Gradient(stops: [.init(color: Color(hex: 0x7FD3EC).opacity(0), location: 0.55),
                                                                   .init(color: Color(hex: 0x7FD3EC).opacity(0.9), location: 1)]),
                                                 startPoint: pt(500, 180), endPoint: pt(500, 790)))
            ctx.stroke(OwlOutlineShape().path(in: rect), with: .color(Self.ink), lineWidth: 13 * k)
            ctx.fill(OwlBellyShape().path(in: rect), with: .color(Self.ink))

            // Blush
            if pose.blush > 0.01 {
                for c in [pt(292, 606), pt(708, 600)] {
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - 46 * k, y: c.y - 22 * k, width: 92 * k, height: 44 * k)),
                             with: .color(Color(hex: 0xFF8C9E).opacity(0.6 * Double(pose.blush))))
                }
            }

            // Feet (the left foot taps along)
            var feet = ctx
            feet.translateBy(x: 0, y: -motion.tap * k)
            feet.fill(OwlFeetLeftShape().path(in: rect), with: .color(Self.ink))
            ctx.fill(OwlFeetRightShape().path(in: rect), with: .color(Self.ink))

            ctx.fill(OwlCrownShape().path(in: rect), with: .color(Self.ink))
            ctx.fill(OwlBeakShape().path(in: rect), with: .color(Self.ink))

            // Mouth (opens by stretching down from its top edge)
            var mouth = ctx
            mouth.translateBy(x: 500 * k, y: 507 * k)
            mouth.scaleBy(x: 1 + 0.15 * pose.beak, y: 1 + 1.1 * pose.beak)
            mouth.translateBy(x: -500 * k, y: -507 * k)
            mouth.fill(OwlMouthShape().path(in: rect), with: .color(Self.amber))

            // Eyes
            let blink = Self.blink(t, mood: mood)
            drawEye(&ctx, rect: rect, k: k,
                    goggle: OwlGoggleLeftShape(), rim: OwlGoggleRimLeftShape(), disc: OwlDiscLeftShape(),
                    pupilCenter: CGPoint(x: 420.8, y: 391.5), sparkleOffset: CGSize(width: 22.7, height: 0),
                    lid: max(pose.lidLeft, pose.smileLeft > 0.5 ? 0 : blink), smile: pose.smileLeft, motion: motion)
            drawEye(&ctx, rect: rect, k: k,
                    goggle: OwlGoggleRightShape(), rim: OwlGoggleRimRightShape(), disc: OwlDiscRightShape(),
                    pupilCenter: CGPoint(x: 575.2, y: 388.1), sparkleOffset: CGSize(width: -22.7, height: 0.6),
                    lid: max(pose.lidRight, pose.smileRight > 0.5 ? 0 : blink), smile: pose.smileRight, motion: motion)

            // Brows
            drawBrow(&ctx, k: k, points: [CGPoint(x: 448.566, y: 230.222), CGPoint(x: 123.057, y: 246.145), CGPoint(x: 439.93, y: 285.046)],
                     pivot: CGPoint(x: 444, y: 257), degrees: -pose.browTiltLeft, lift: pose.browLiftLeft)
            drawBrow(&ctx, k: k, points: [CGPoint(x: 538.175, y: 228.34), CGPoint(x: 864.066, y: 230.578), CGPoint(x: 557.543, y: 282.809)],
                     pivot: CGPoint(x: 548, y: 256), degrees: pose.browTiltRight, lift: pose.browLiftRight)

            if earphones > 0.01 {
                drawEarphones(&ctx, k: k, progress: earphones, sway: motion.cableSway)
            }

            drawExtras(&ctx, k: k)
        }
    }

    // MARK: Motion

    struct Motion {
        var bob: CGFloat = 0
        var sway: CGFloat = 0
        var tap: CGFloat = 0
        var cableSway: CGFloat = 0
        var glance: CGFloat = 0
    }

    static func motion(mood: MascotMood, t: Double) -> Motion {
        var m = Motion()
        m.cableSway = CGFloat(sin(t * 1.4)) * 10
        switch mood {
        case .listening:
            let beat = abs(sin(t * 3.2))
            m.bob = -CGFloat(beat) * 22
            m.sway = CGFloat(sin(t * 1.6)) * 7
            m.tap = CGFloat(max(0, sin(t * 6.4))) * 14
            m.cableSway = CGFloat(sin(t * 3.2)) * 16
        case .excited:
            m.bob = -CGFloat(abs(sin(t * 6))) * 26
            m.sway = CGFloat(sin(t * 3)) * 3
        case .sleepy:
            m.bob = CGFloat(sin(t * 0.9)) * 6
            m.sway = CGFloat(sin(t * 0.5)) * 3
        case .sad:
            m.bob = CGFloat(sin(t * 1.0)) * 4
        case .happy, .wink, .curious, .surprised:
            m.bob = CGFloat(sin(t * 1.8)) * 8
            m.sway = CGFloat(sin(t * 0.9)) * 2
            m.glance = CGFloat(sin(t * 0.4)) * 8
        }
        return m
    }

    /// 0 open … 1 closed. Regular blinks, slower and longer when sleepy.
    static func blink(_ t: Double, mood: MascotMood) -> CGFloat {
        guard t > 0 else { return 0 }
        let period = mood == .sleepy ? 3.0 : 4.0
        let duration = mood == .sleepy ? 0.5 : 0.18
        let phase = t.truncatingRemainder(dividingBy: period)
        guard phase < duration else { return 0 }
        return CGFloat(1 - abs(1 - 2 * phase / duration))
    }

    // MARK: Parts

    private func drawEye<G: Shape, R: Shape, D: Shape>(_ ctx: inout GraphicsContext, rect: CGRect, k: CGFloat,
                                                       goggle: G, rim: R, disc: D,
                                                       pupilCenter: CGPoint, sparkleOffset: CGSize,
                                                       lid: CGFloat, smile: CGFloat, motion: Motion) {
        ctx.fill(goggle.path(in: rect), with: .color(Self.cream))
        ctx.stroke(rim.path(in: rect), with: .color(Self.ink), lineWidth: 23.9 * k)

        let discPath = disc.path(in: rect)
        ctx.fill(discPath, with: .color(Self.white))
        ctx.drawLayer { eye in
            eye.clip(to: discPath)
            let scale = pose.pupilScale
            let cx = pupilCenter.x + pose.pupil.width + motion.glance
            let cy = pupilCenter.y + pose.pupil.height
            let r = 49.2 * scale
            eye.fill(Path(ellipseIn: CGRect(x: (cx - r) * k, y: (cy - r) * k, width: 2 * r * k, height: 2 * r * k)),
                     with: .color(Self.ink))
            let hr = 18.6 * scale
            let hx = cx + sparkleOffset.width * scale
            let hy = cy + sparkleOffset.height * scale
            eye.fill(Path(ellipseIn: CGRect(x: (hx - hr) * k, y: (hy - hr) * k, width: 2 * hr * k, height: 2 * hr * k)),
                     with: .color(Self.white))

            if lid > 0.01 {
                let bottom = 230 + min(1, lid) * 330
                eye.fill(Path(CGRect(x: 200 * k, y: 0, width: 600 * k, height: bottom * k)), with: .color(Self.cream))
                var edge = Path()
                edge.move(to: CGPoint(x: 200 * k, y: bottom * k))
                edge.addLine(to: CGPoint(x: 800 * k, y: bottom * k))
                eye.stroke(edge, with: .color(Self.ink), lineWidth: 14 * k)
            }
        }

        if smile > 0.5 {
            let x0 = pupilCenter.x, y0 = pupilCenter.y + 10
            var arc = Path()
            arc.move(to: CGPoint(x: (x0 - 48) * k, y: (y0 + 18) * k))
            arc.addQuadCurve(to: CGPoint(x: (x0 + 48) * k, y: (y0 + 18) * k), control: CGPoint(x: x0 * k, y: (y0 - 46) * k))
            ctx.stroke(arc, with: .color(Self.ink), style: StrokeStyle(lineWidth: 20 * k, lineCap: .round))
        }
    }

    private func drawBrow(_ ctx: inout GraphicsContext, k: CGFloat, points: [CGPoint], pivot: CGPoint,
                          degrees: CGFloat, lift: CGFloat) {
        let a = degrees * .pi / 180
        var path = Path()
        for (i, p) in points.enumerated() {
            let dx = p.x - pivot.x, dy = p.y - pivot.y
            let x = pivot.x + dx * cos(a) - dy * sin(a)
            let y = pivot.y + dx * sin(a) + dy * cos(a) + lift
            let q = CGPoint(x: x * k, y: y * k)
            if i == 0 { path.move(to: q) } else { path.addLine(to: q) }
        }
        path.closeSubpath()
        ctx.fill(path, with: .color(Self.ink))
    }

    private func drawEarphones(_ ctx: inout GraphicsContext, k: CGFloat, progress: CGFloat, sway: CGFloat) {
        var layer = ctx
        layer.opacity = Double(min(1, progress * 1.5))
        let drop = (1 - progress) * 300
        for side in [CGFloat(-1), CGFloat(1)] {
            let bx = 500 + side * 402
            let by = 430 + drop
            let stemX = bx + side * 4
            let stemY = by + 30
            let endY = stemY + 72

            var cable = Path()
            cable.move(to: CGPoint(x: stemX * k, y: endY * k))
            cable.addCurve(to: CGPoint(x: 500 * k, y: 918 * k),
                           control1: CGPoint(x: (500 + side * (430 + sway)) * k, y: 700 * k),
                           control2: CGPoint(x: (500 + side * 300) * k, y: 960 * k))
            layer.stroke(cable, with: .color(Self.ink), style: StrokeStyle(lineWidth: 9 * k, lineCap: .round))

            let stem = Path(roundedRect: CGRect(x: (stemX - 15) * k, y: stemY * k, width: 30 * k, height: 74 * k), cornerRadius: 15 * k)
            layer.fill(stem, with: .color(.white))
            layer.stroke(stem, with: .color(Self.ink), lineWidth: 9 * k)
            let tip = Path(roundedRect: CGRect(x: (stemX - 15) * k, y: (stemY + 48) * k, width: 30 * k, height: 26 * k), cornerRadius: 11 * k)
            layer.fill(tip, with: .color(Self.amber))
            layer.stroke(tip, with: .color(Self.ink), lineWidth: 9 * k)

            let bud = Path(ellipseIn: CGRect(x: (bx - 44) * k, y: (by - 40) * k, width: 88 * k, height: 80 * k))
            layer.fill(bud, with: .color(.white))
            layer.stroke(bud, with: .color(Self.ink), lineWidth: 10 * k)
            layer.fill(Path(ellipseIn: CGRect(x: (bx - side * 10 - 18) * k, y: (by - 8 - 15) * k, width: 36 * k, height: 30 * k)),
                       with: .color(Self.cyan))
        }
        let splitter = Path(roundedRect: CGRect(x: 485 * k, y: 900 * k, width: 30 * k, height: 46 * k), cornerRadius: 13 * k)
        layer.fill(splitter, with: .color(Self.amber))
        layer.stroke(splitter, with: .color(Self.ink), lineWidth: 8 * k)
        var tail = Path()
        tail.move(to: CGPoint(x: 500 * k, y: 946 * k))
        tail.addCurve(to: CGPoint(x: 430 * k, y: 1000 * k), control1: CGPoint(x: 500 * k, y: 980 * k), control2: CGPoint(x: 470 * k, y: 990 * k))
        layer.stroke(tail, with: .color(Self.ink), style: StrokeStyle(lineWidth: 9 * k, lineCap: .round))
    }

    /// Floating notes, z's and sparkles, depending on the mood.
    private func drawExtras(_ ctx: inout GraphicsContext, k: CGFloat) {
        func floaters(_ glyph: String, origins: [CGPoint], speed: Double, rise: CGFloat, sizes: [CGFloat], weight: Font.Weight) {
            for (i, origin) in origins.enumerated() {
                let phase = (t * speed + Double(i) / Double(origins.count)).truncatingRemainder(dividingBy: 1)
                let x = origin.x + CGFloat(sin(phase * 2 * .pi)) * 22
                let y = origin.y - CGFloat(phase) * rise
                var layer = ctx
                layer.opacity = sin(phase * .pi)
                let text = Text(glyph)
                    .font(.system(size: sizes[i % sizes.count] * k, weight: weight, design: .rounded))
                    .foregroundStyle(Self.ink)
                layer.draw(text, at: CGPoint(x: x * k, y: y * k))
            }
        }
        switch mood {
        case .listening:
            floaters("♪", origins: [CGPoint(x: 150, y: 420), CGPoint(x: 860, y: 400), CGPoint(x: 880, y: 300)],
                     speed: 0.45, rise: 300, sizes: [90, 110, 70], weight: .bold)
        case .sleepy:
            floaters("z", origins: [CGPoint(x: 780, y: 200), CGPoint(x: 820, y: 220), CGPoint(x: 860, y: 210)],
                     speed: 0.3, rise: 170, sizes: [70, 56, 44], weight: .heavy)
        case .excited:
            for (i, c) in [CGPoint(x: 150, y: 180), CGPoint(x: 860, y: 160), CGPoint(x: 900, y: 560)].enumerated() {
                let r = CGFloat([34.0, 26.0, 20.0][i] * (0.7 + 0.3 * sin(t * 5 + Double(i))))
                var star = Path()
                star.move(to: CGPoint(x: c.x * k, y: (c.y - r) * k))
                star.addQuadCurve(to: CGPoint(x: (c.x + r) * k, y: c.y * k), control: CGPoint(x: c.x * k, y: c.y * k))
                star.addQuadCurve(to: CGPoint(x: c.x * k, y: (c.y + r) * k), control: CGPoint(x: c.x * k, y: c.y * k))
                star.addQuadCurve(to: CGPoint(x: (c.x - r) * k, y: c.y * k), control: CGPoint(x: c.x * k, y: c.y * k))
                star.addQuadCurve(to: CGPoint(x: c.x * k, y: (c.y - r) * k), control: CGPoint(x: c.x * k, y: c.y * k))
                ctx.fill(star, with: .color(Self.amber))
            }
        default:
            break
        }
    }
}
