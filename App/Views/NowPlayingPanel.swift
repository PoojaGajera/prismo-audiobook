import SwiftUI

/// The now-playing panel, modelled on YouTube Music: the mini player and the full player are one
/// surface. Dragging it follows the finger; the cover artwork travels and grows from the mini
/// thumbnail to the big centred artwork, and the title and author travel with it (so the drag
/// never shows a lone cover); the mini bar's controls fade out early and the full player's
/// controls fade in late; letting go springs it open or closed (position + flick speed).
struct NowPlayingPanel: View {
    /// Height of the collapsed bar above the home indicator (the library reserves this space).
    /// 20 top + 56 row + 12 + 4 progress + 12 bottom (the 4-point scale).
    static let miniBarHeight: CGFloat = 104

    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var router: AppRouter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    /// 0 = collapsed mini bar … 1 = full player. Animated, and driven directly while dragging.
    @State private var progress: CGFloat = 0
    /// Progress when the current drag started (nil = not dragging the panel).
    @State private var dragStart: CGFloat?
    /// True while a drag gesture is live. Unlike `onEnded`, this also resets when iOS *cancels* the
    /// drag (e.g. a swipe up from the bottom edge to leave the app starts on the mini bar, then the
    /// system takes it over), which used to leave the panel frozen half-open.
    @GestureState private var isTouching = false
    /// Where the full player wants the artwork, in the panel's coordinate space.
    @State private var fullArtwork: CGRect = .zero
    /// Resting title frames used to keep the title and chapter readable during the drag.
    @State private var fullTitle: CGRect = .zero
    @State private var miniTitle: CGRect = .zero
    var body: some View {
        if let book = player.book {
            GeometryReader { geo in
                let insets = geo.safeAreaInsets
                let screen = CGSize(width: geo.size.width + insets.leading + insets.trailing,
                                    height: geo.size.height + insets.top + insets.bottom)
                let travel = max(1, screen.height - Self.miniBarHeight - insets.bottom)

                PanelChoreography(progress: progress, book: book, screen: screen, insets: insets,
                                  fullArtwork: fullArtwork,
                                  fullTitle: fullTitle,
                                  miniTitle: miniTitle,
                                  onArtworkFrame: { fullArtwork = $0 },
                                  onFullTitleFrame: { fullTitle = $0 },
                                  onMiniTitleFrame: { miniTitle = $0 },
                                  onOpen: { setOpen(true) },
                                  onCollapse: { setOpen(false) })
                    .gesture(panelDrag(travel: travel))
                    .ignoresSafeArea()
            }
            .onAppear { progress = router.showPlayer ? 1 : 0 }
            .onChange(of: router.showPlayer) { _, open in animate(to: open ? 1 : 0) }
            .onChange(of: isTouching) { _, touching in
                guard !touching else { return }
                // Let a normal `onEnded` run first; if the drag was cancelled instead, it never
                // will, so settle back to wherever the panel was before the drag.
                DispatchQueue.main.async {
                    guard dragStart != nil else { return }
                    dragStart = nil
                    setOpen(router.showPlayer)
                }
            }
            // Never leave (or come back to) a half-open panel.
            .onChange(of: scenePhase) { _, _ in snapToRest() }
        }
    }

    // MARK: - Gesture

    private func panelDrag(travel: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .updating($isTouching) { _, touching, _ in touching = true }
            .onChanged { drag in
                if dragStart == nil {
                    // Only claim mostly-vertical drags.
                    guard abs(drag.translation.height) > abs(drag.translation.width) else { return }
                    dragStart = progress
                }
                guard let start = dragStart else { return }
                progress = min(1, max(0, start - drag.translation.height / travel))
            }
            .onEnded { drag in
                guard let start = dragStart else { return }
                dragStart = nil
                // Where a flick would carry it decides, so a quick short swipe still opens/closes.
                let projected = start - drag.predictedEndTranslation.height / travel
                // How fast the finger was moving the panel (progress per second) when it let go.
                let velocity = -drag.velocity.height / travel
                setOpen(projected > 0.5, velocity: velocity)
            }
    }

    /// Ends any drag and puts the panel straight at its resting state (no animation).
    private func snapToRest() {
        dragStart = nil
        var transaction = Transaction(animation: nil)
        transaction.isPanelMotion = true
        withTransaction(transaction) { progress = router.showPlayer ? 1 : 0 }
    }

    private func setOpen(_ open: Bool, velocity: CGFloat = 0) {
        animate(to: open ? 1 : 0, velocity: velocity)
        if router.showPlayer != open { router.showPlayer = open }
    }

    /// Springs to `target`. After a swipe the spring starts at the finger's speed (instead of from
    /// a standstill, which made the panel stall and then move again: a "double" animation), and it
    /// has no bounce, so it settles once at the bottom without a second little motion.
    private func animate(to target: CGFloat, velocity: CGFloat = 0) {
        guard progress != target || dragStart != nil else { return }
        let distance = target - progress
        // SwiftUI wants the starting speed relative to the distance still to go. Only carry speed
        // that points towards the target, and cap it so a hard flick doesn't look like a jump.
        let relative = abs(distance) > 0.001 ? min(12, max(0, velocity / distance)) : 0
        let animation: Animation = reduceMotion
            ? .easeInOut(duration: 0.25)
            : .interpolatingSpring(duration: 0.42, bounce: 0, initialVelocity: Double(relative))
        var transaction = Transaction(animation: animation)
        transaction.isPanelMotion = true
        withTransaction(transaction) { progress = target }
    }
}

/// Marks the panel's own open/close animation, so the views inside it don't animate a second time.
private struct PanelMotionKey: TransactionKey {
    static let defaultValue = false
}

extension Transaction {
    /// True for the now-playing panel's open/close spring.
    var isPanelMotion: Bool {
        get { self[PanelMotionKey.self] }
        set { self[PanelMotionKey.self] = newValue }
    }
}

// MARK: - Choreography

/// Lays everything out for a given progress. Animatable, so springs run through every
/// intermediate step (fades and the artwork path), not just the start and end states.
private struct PanelChoreography: View, Animatable {
    var progress: CGFloat
    let book: Book
    let screen: CGSize
    let insets: EdgeInsets
    let fullArtwork: CGRect
    let fullTitle: CGRect
    let miniTitle: CGRect
    let onArtworkFrame: (CGRect) -> Void
    let onFullTitleFrame: (CGRect) -> Void
    let onMiniTitleFrame: (CGRect) -> Void
    let onOpen: () -> Void
    let onCollapse: () -> Void

    @EnvironmentObject private var player: PlayerController

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    /// The thumbnail's spot in the mini bar (matches `MiniBar`'s padding and size).
    private static let miniArtwork = CGRect(x: 24, y: 20, width: 56, height: 56)

    var body: some View {
        let p = min(1, max(0, progress))
        let collapsedTop = screen.height - NowPlayingPanel.miniBarHeight - insets.bottom
        let panelTop = lerp(collapsedTop, 0, p)
        // The bar's controls and progress line go quickly, before the title drops past them.
        let miniOpacity = 1 - ramp(p, 0, 0.1)
        let fullOpacity = ramp(p, 0.5, 1)
        let corner = lerp(34, 0, ramp(p, 0.7, 1))
        let art = artworkRect(p)
        let artCorner = lerp(10, 8, p)
        let surface = UnevenRoundedRectangle(topLeadingRadius: corner, topTrailingRadius: corner, style: .continuous)
        let theme = CoverPalette.theme(for: book)
        // The travelling title stands in for the real labels whenever the panel isn't fully at
        // rest. It lands exactly on them, so the swap only happens where the two are identical.
        // (Swapping at 3% / 97% made the title jump: the cover still had 3% of its way to go.)
        let titleIsTravelling = p > 0.002 && p < 0.998
        // Where the background turns light: just above the bottom of the cover, so the title,
        // chapter and controls sit on the light part.
        let lightStop = fullArtwork.height > 10
            ? min(0.9, max(0.3, (fullArtwork.maxY - 24) / max(1, screen.height)))
            : 0.55

        ZStack(alignment: .top) {
            // The library dims as the player rises.
            Color.black
                .opacity(0.45 * Double(ramp(p, 0, 1)))
                .frame(width: screen.width, height: screen.height)
                .allowsHitTesting(false)

            ZStack(alignment: .topLeading) {
                // A solid surface that opens into a light, airy gradient in the cover's colours
                // (a soft pastel at the top, almost white from the bottom of the cover down).
                surface
                    .fill(theme.sheet)
                    .overlay {
                        LinearGradient(
                            stops: [
                                .init(color: theme.deep, location: 0),
                                .init(color: theme.mid, location: lightStop * 0.55),
                                .init(color: theme.light, location: lightStop),
                                .init(color: theme.light, location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .opacity(Double(ramp(p, 0.1, 0.75)))
                        .clipShape(surface)
                    }
                    .overlay {
                        surface.strokeBorder(Theme.hairline, lineWidth: 0.75)
                            .opacity(Double(miniOpacity))
                    }
                    .shadow(color: .black.opacity(0.10 * Double(miniOpacity)), radius: 16, y: -3)
                    .frame(width: screen.width, height: screen.height)

                // The one artwork that travels between the two layouts.
                CoverView(book: book, cornerRadius: 0)
                    .frame(width: art.width, height: art.height)
                    .clipShape(RoundedRectangle(cornerRadius: artCorner, style: .continuous))
                    .shadow(color: .black.opacity(0.14 * Double(fullOpacity)),
                            radius: 12 * fullOpacity, y: 6 * fullOpacity)
                    .position(x: art.midX, y: art.midY)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                // Full player (its artwork spot is an empty placeholder that reports its frame).
                PlayerView(onCollapse: onCollapse,
                           onArtworkFrame: onArtworkFrame,
                           onTitleFrame: onFullTitleFrame,
                           hideTitle: titleIsTravelling,
                           isActive: p >= 0.998)
                    .padding(.top, insets.top)
                    .padding(.bottom, insets.bottom)
                    .frame(width: screen.width, height: screen.height)
                    .opacity(Double(fullOpacity))
                    .allowsHitTesting(p > 0.97)
                    .accessibilityHidden(p < 0.5)

                // Mini bar controls (the thumbnail is the travelling artwork above).
                MiniBar(book: book,
                        hideTitle: titleIsTravelling,
                        onTitleFrame: onMiniTitleFrame,
                        onOpen: onOpen)
                    .frame(width: screen.width, height: NowPlayingPanel.miniBarHeight, alignment: .top)
                    .opacity(Double(miniOpacity))
                    .allowsHitTesting(p < 0.03)
                    .accessibilityHidden(p > 0.5)

                if titleIsTravelling, miniTitle.width > 0, fullTitle.width > 0 {
                    TravellingTitle(book: book,
                                    progress: p,
                                    chapterTitle: player.currentChapter?.title,
                                    art: art,
                                    fullArt: fullArtwork,
                                    miniTitle: miniTitle,
                                    fullTitle: fullTitle)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: screen.width, height: screen.height, alignment: .topLeading)
            // The spring already moves everything frame by frame (this view is Animatable). Without
            // this, the text, cover and controls inside would also run their own copy of the spring
            // and lag behind: that was the stutter, and the title smearing across the cover.
            .transaction { if $0.isPanelMotion { $0.animation = nil } }
            .coordinateSpace(.named(PlayerView.panelSpace))
            .offset(y: panelTop)
            .environment(\.coverTheme, theme)
        }
        .frame(width: screen.width, height: screen.height, alignment: .top)
    }

    /// Thumbnail rect → full artwork rect, in the panel's coordinate space.
    private func artworkRect(_ p: CGFloat) -> CGRect {
        let mini = Self.miniArtwork
        var full = fullArtwork
        if full.width < 10 {
            // Not measured yet: a close estimate of the player's layout.
            // (8 top + 44 close button + 12, then full width less 16-point margins.)
            let side = screen.width - 2 * Spacing.m
            full = CGRect(x: Spacing.m, y: insets.top + 64, width: side, height: side)
        }
        return CGRect(x: lerp(mini.minX, full.minX, p),
                      y: lerp(mini.minY, full.minY, p),
                      width: lerp(mini.width, full.width, p),
                      height: lerp(mini.height, full.height, p))
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

    /// Smooth 0…1 ramp of `p` between `from` and `to`.
    private func ramp(_ p: CGFloat, _ from: CGFloat, _ to: CGFloat) -> CGFloat {
        let x = min(1, max(0, (p - from) / (to - from)))
        return x * x * (3 - 2 * x)
    }
}

// MARK: - Travelling title

/// The title and author while the panel moves, always left-aligned (like YouTube Music).
/// They follow the travelling cover so they never cross it: starting beside the thumbnail
/// (as in the mini bar), they drop below the cover while it is still small and line up with its
/// left edge, then move with it, growing to the player's heading size. The subtitle changes from the
/// chapter (mini bar) to the author (player): one fades out before the other fades in.
private struct TravellingTitle: View {
    let book: Book
    let progress: CGFloat
    let chapterTitle: String?
    /// The cover's current and final frames.
    let art: CGRect
    let fullArt: CGRect
    /// The title block's frames at rest, in the mini bar and in the full player.
    let miniTitle: CGRect
    let fullTitle: CGRect

    var body: some View {
        let p = progress
        let drop = ramp(p, 0.06, 0.24)     // beside the cover → below it
        let across = ramp(p, 0.1, 0.3)     // in line with the cover's left edge, and wider

        let besideX = art.maxX + Spacing.m
        let besideY = art.midY - miniTitle.height / 2
        let belowY = art.maxY + (fullTitle.minY - fullArt.maxY)
        // Once below, the title's left edge follows the cover's left edge (they move as one block
        // and meet the full player's margin together).
        let belowX = art.minX + (fullTitle.minX - fullArt.minX)
        let x = lerp(besideX, belowX, across)
        let y = lerp(besideY, belowY, drop)
        // Never past the right margin.
        let width = max(1, min(lerp(miniTitle.width, fullTitle.width, across), fullTitle.maxX - x))

        // The text is never re-laid-out at in-between font sizes (that made the letters shuffle and
        // shimmer). Instead the mini bar's labels and the player's labels are both drawn at their
        // real sizes, scaled together as one, and cross-faded. So at each end the text is exactly
        // the real label, and in between it grows smoothly.
        let titleRatio = Self.size(.title2) / Self.size(.subheadline)
        let miniTitleScale = lerp(1, titleRatio, p)
        let fullTitleScale = miniTitleScale / titleRatio
        let subtitleRatio = Self.size(.body) / Self.size(.caption1)
        let miniSubtitleScale = lerp(1, subtitleRatio, p)
        let fullSubtitleScale = miniSubtitleScale / subtitleRatio
        let subtitleTop = Self.lineHeight(.subheadline) * miniTitleScale + Spacing.xxs
        let style = ramp(p, 0.2, 0.5)      // mini bar look → player look

        ZStack(alignment: .topLeading) {
            scaled(FadedLineText(text: book.title, font: .subheadline.weight(.semibold)),
                   by: miniTitleScale, width: width)
                .opacity(Double(1 - style))
            scaled(FadedLineText(text: book.title, font: .title2.bold()),
                   by: fullTitleScale, width: width)
                .opacity(Double(style))

            // Chapter (mini bar) → author (player).
            ZStack(alignment: .topLeading) {
                scaled(FadedLineText(text: chapterTitle ?? book.author, font: .caption),
                       by: miniSubtitleScale, width: width)
                    .opacity(Double(1 - ramp(p, 0.15, 0.4)))
                scaled(FadedLineText(text: book.author, font: .body),
                       by: fullSubtitleScale, width: width)
                    .opacity(Double(ramp(p, 0.4, 0.65)))
            }
            .foregroundStyle(.secondary)
            .offset(y: subtitleTop)
        }
        .offset(x: x, y: y)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Lays a label out at `width / scale`, then scales it from its top-left corner, so it covers
    /// exactly `width` without its text being re-laid-out.
    private func scaled(_ label: some View, by scale: CGFloat, width: CGFloat) -> some View {
        label
            .frame(width: max(1, width / max(0.01, scale)), alignment: .leading)
            .scaleEffect(scale, anchor: .topLeading)
    }

    private static func lineHeight(_ style: UIFont.TextStyle) -> CGFloat {
        UIFont.preferredFont(forTextStyle: style).lineHeight
    }

    /// The Dynamic Type size of a text style, so the ends match the real labels exactly.
    private static func size(_ style: UIFont.TextStyle) -> CGFloat {
        UIFont.preferredFont(forTextStyle: style).pointSize
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

    private func ramp(_ p: CGFloat, _ from: CGFloat, _ to: CGFloat) -> CGFloat {
        let x = min(1, max(0, (p - from) / (to - from)))
        return x * x * (3 - 2 * x)
    }
}

// MARK: - Mini bar

/// The collapsed bar's contents. Its background is the panel surface, and its thumbnail is the
/// panel's travelling artwork, so this only draws the text and controls. On the 4-point scale.
private struct MiniBar: View {
    let book: Book
    /// Hidden while the travelling title stands in for it (mid-drag).
    var hideTitle = false
    var onTitleFrame: (CGRect) -> Void = { _ in }
    var onOpen: () -> Void

    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.coverTheme) private var theme

    var body: some View {
        VStack(spacing: Spacing.s) {
            HStack(spacing: Spacing.m) {
                Color.clear
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    FadedLineText(text: book.title, font: .subheadline.weight(.semibold))
                    FadedLineText(text: player.currentChapter?.title ?? book.author, font: .caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .named(PlayerView.panelSpace))
                } action: { frame in
                    onTitleFrame(frame)
                }
                .opacity(hideTitle ? 0 : 1)
                Button { player.skipBackward() } label: {
                    SkipGlyph(back: true, seconds: settings.skipBackInterval, size: 24, numberSize: 8)
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Skip back")
                BadgePlayButton(isPlaying: player.isPlaying, size: 48, color: theme.accent) {
                    player.togglePlayPause()
                }
            }
            IridescentBar(value: book.duration > 0 ? player.currentTime / book.duration : 0, height: 4,
                          tint: theme.accent)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.top, 20)
        .padding(.bottom, Spacing.s)
        .overlay(alignment: .top) {
            // Grabber: it can be pulled up.
            Capsule()
                .fill(Color.primary.opacity(0.2))
                .frame(width: 36, height: 4)
                .padding(.top, Spacing.xs)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Now playing: \(book.title)")
        .accessibilityAction(named: "Open player", onOpen)
    }
}
