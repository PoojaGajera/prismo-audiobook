import SwiftUI
import AVFoundation
import AVKit
import Combine

struct PlayerView: View {
    /// Coordinate space of the now-playing panel; the artwork placeholder reports its frame in it.
    static let panelSpace = "nowPlayingPanel"

    /// The vertical gaps in the open player, in points. Tune the spacing here.
    /// (The chapter row is 44 points tall and the scrubber 34, for easy tapping, so each already
    /// carries about 11–14 points of space around what you see.)
    enum Gap {
        /// Chapter name → progress bar.
        static let chapterToProgress: CGFloat = 0
        /// Progress bar times → play controls.
        static let progressToControls: CGFloat = Spacing.l
        /// Play controls → the option chips.
        static let controlsToOptions: CGFloat = Spacing.m
    }

    /// Collapse back to the mini bar (the chevron).
    var onCollapse: () -> Void = {}
    /// Where the artwork should sit; the panel draws the travelling artwork there.
    var onArtworkFrame: (CGRect) -> Void = { _ in }
    /// Where the title block sits; the panel draws the travelling title there mid-drag.
    var onTitleFrame: (CGRect) -> Void = { _ in }
    /// Hidden while the panel's travelling title stands in for it (mid-drag).
    var hideTitle = false
    /// False while the panel is closed or moving: long titles hold still instead of scrolling.
    var isActive = true

    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var router: AppRouter

    @State private var scrubValue: Double?
    @State private var activeSheet: PlayerSheet?
    /// The bookmark just saved, for the "Bookmark Saved" sheet.
    @State private var savedBookmark: Bookmark?
    @State private var bookmarkSaved = 0
    /// Right-hand time under the progress bar: time left in the chapter, or (tapped) in the book.
    @AppStorage("progressShowsBookRemaining") private var showBookRemaining = false

    enum PlayerSheet: String, Identifiable {
        case chapters, bookmarks, speed, more, bookmarkSaved, settings, editDetails, about
        var id: String { rawValue }

        /// A full app page (as opposed to one of the player's own small sheets).
        var isAppPage: Bool {
            switch self {
            case .bookmarks, .settings, .editDetails: true
            // The chapter list wears the cover's colours, like the player (user's request).
            case .chapters, .speed, .more, .bookmarkSaved, .about: false
            }
        }
    }

    /// The app's own light/dark (the open player itself is always drawn light).
    @Environment(\.appColorScheme) private var appColorScheme

    private func openBookCard() {
        guard let id = player.book?.id else { return }
        showBookCard(id, in: Binding(get: { router.bookCard }, set: { router.bookCard = $0 }))
    }

    /// The current cover's colours (background, buttons, chips, sheets).
    private var theme: CoverTheme {
        player.book.map { CoverPalette.theme(for: $0) } ?? .fallback
    }

    var body: some View {
        Group {
            if let book = player.book {
                // The panel draws the background and the artwork.
                content(book)
            } else {
                ContentUnavailableView("Nothing playing", systemImage: "headphones")
                    .background { PrismBackground(style: .plain) }
            }
        }
        .environment(\.coverTheme, theme)
        .sheet(item: $activeSheet) { sheet in
            // The player's own small sheets (speed, more, bookmark saved) wear the cover's colours
            // and stay light like the player. Full app pages opened from it (chapters, bookmarks,
            // settings, edit details) look like every other page: the app's theme and light/dark.
            sheetContent(sheet)
                .environmentObject(player)
                .environmentObject(settings)
                .environment(\.coverTheme, theme)
                .environment(\.colorScheme, sheet.isAppPage ? appColorScheme : .light)
                // The player's own sheets are light all the way down, UIKit controls included
                // (text fields, keyboards), even under the dark theme.
                .preferredColorScheme(sheet.isAppPage ? nil : .light)
                .tint(sheet.isAppPage ? Theme.accent : theme.accent)
                .presentationBackground(sheet == .bookmarks ? AnyShapeStyle(Theme.surface)
                                        : sheet.isAppPage ? AnyShapeStyle(Theme.background) : AnyShapeStyle(theme.sheet))
                .presentationCornerRadius(28)
        }
        .alert("Playback problem", isPresented: Binding(
            get: { player.errorMessage != nil },
            set: { if !$0 { player.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(player.errorMessage ?? "")
        }
        .sensoryFeedback(.success, trigger: bookmarkSaved)
    }

    @ViewBuilder
    private func sheetContent(_ sheet: PlayerSheet) -> some View {
        switch sheet {
        case .chapters: ChaptersView()
        case .bookmarks: BookmarksView()
        case .settings: SettingsView(scrollTo: SettingsView.playbackSection)
        case .editDetails:
            if let book = player.book {
                BookDetailsView(book: book)
            }
        case .about:
            EmptyView()   // shown as the book card (BookCard), not as a sheet
        // These size themselves to fit (PlayerSheetScaffold).
        case .speed:
            SpeedSheet { activeSheet = .settings }
                .presentationDragIndicator(.visible)
        case .more:
            MoreSheet { sheet in
                if sheet == .about {
                    // The book's details card, over everything (let this sheet close first).
                    activeSheet = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { openBookCard() }
                } else {
                    activeSheet = sheet
                }
            }
                .presentationDragIndicator(.visible)
        case .bookmarkSaved:
            if let bookmark = savedBookmark {
                BookmarkSavedSheet(bookmark: bookmark) { activeSheet = .bookmarks }
                    .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Layout

    /// Laid out like YouTube Music, on the 4-point scale (`Spacing`): a big cover with 16-point
    /// margins and small corners, then the title and author left-aligned under it, then the
    /// chapter, progress, controls and options. Buttons are at least 44 points.
    private func content(_ book: Book) -> some View {
        VStack(spacing: 0) {
            HStack {
                ChipIconButton(systemName: "chevron.down", label: "Close player", glass: true, action: onCollapse)
                Spacer()
            }
            // 12 + (44 − 36) / 2 = 16: the round button lines up with the cover's edge.
            .padding(.horizontal, Spacing.s)
            .padding(.top, Spacing.xs)

            // The artwork's spot: as big as the screen allows (full width less the margins),
            // shrinking only when the screen is too short for everything else.
            // The panel draws the cover here (it travels in from the mini bar).
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                // Measure the square itself (before it's placed in the flexible space).
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .named(Self.panelSpace))
                } action: { frame in
                    onArtworkFrame(frame)
                }
                // Tap the cover: the book's details card.
                .contentShape(Rectangle())
                .onTapGesture { openBookCard() }
                .accessibilityElement()
                .accessibilityLabel("Cover")
                .accessibilityHint("Shows the book's details")
                .accessibilityAddTraits(.isButton)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, Spacing.m)
                .padding(.top, Spacing.s)
                .padding(.bottom, Spacing.l)
                .layoutPriority(-1)

            // Title and author, left-aligned under the cover. A title too long to fit scrolls
            // slowly so it can be read. Mid-drag the panel's travelling title stands in for them.
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                MarqueeText(text: book.title, font: .title2.bold(), isActive: isActive)
                FadedLineText(text: book.author, font: .body)
                    .foregroundStyle(Theme.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Measured inside the margins, so the travelling title lands exactly here.
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(Self.panelSpace))
            } action: { frame in
                onTitleFrame(frame)
            }
            .opacity(hideTitle ? 0 : 1)
            .padding(.horizontal, Spacing.m)

            chapterButton
                .padding(.horizontal, Spacing.m)
                .padding(.top, Spacing.xs)

            progressSection
                .padding(.horizontal, Spacing.m)
                .padding(.top, Gap.chapterToProgress)

            transportControls
                .padding(.top, Gap.progressToControls)

            playerOptions
                .padding(.horizontal, Spacing.m)
                .padding(.top, Gap.controlsToOptions)
                .padding(.bottom, Spacing.s)
        }
    }

    @ViewBuilder
    private var chapterButton: some View {
        if let chapter = player.currentChapter {
            Button { activeSheet = .chapters } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "list.bullet")
                        .font(.body)
                    // Long chapter names scroll slowly so they can be read.
                    MarqueeText(text: chapter.title, font: .subheadline.weight(.semibold), isActive: isActive)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.tertiaryText)
                }
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Chapters, current chapter: \(chapter.title)")
        }
    }

    // MARK: - Progress

    private var scopeStart: Double { player.currentChapter?.start ?? 0 }
    private var scopeDuration: Double {
        max(0.1, player.currentChapter?.duration ?? player.duration)
    }
    private var displayedElapsed: Double {
        min(scopeDuration, max(0, scrubValue ?? (player.currentTime - scopeStart)))
    }
    private var speedFactor: Double { settings.adjustForSpeed ? player.speed : 1 }

    private var progressSection: some View {
        VStack(spacing: Spacing.xxs) {
            PearlSlider(
                value: Binding(get: { displayedElapsed }, set: { scrubValue = $0 }),
                range: 0...scopeDuration,
                tint: theme.accent,
                onEditingChanged: { editing in
                    if !editing, let value = scrubValue {
                        // Never all the way to the end: that would jump to the next chapter.
                        player.seek(to: scopeStart + min(value, max(0, scopeDuration - 1)))
                        scrubValue = nil
                    }
                })

            HStack(spacing: Spacing.xs) {
                Text(TimeFormat.clock(displayedElapsed))
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Time left in the chapter; tap to switch to time left in the book.
                Button {
                    showBookRemaining.toggle()
                } label: {
                    Text(remainingLabel)
                        .contentTransition(.numericText())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityHint("Switches between time left in the chapter and in the book")

                // The chapter's total length (the whole book's when there are no chapters).
                Text(TimeFormat.clock(scopeDuration))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityLabel("Chapter length \(TimeFormat.clock(scopeDuration))")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(Theme.secondaryText)
        }
    }

    private var remainingLabel: String {
        let now = scrubValue.map { scopeStart + $0 } ?? player.currentTime
        if !showBookRemaining, let chapter = player.currentChapter {
            return preciseDuration(max(0, chapter.end - now) / speedFactor) + " left"
        }
        return preciseDuration(max(0, player.duration - now) / speedFactor) + " left in book"
    }

    private var chapterRemaining: Double {
        let now = scrubValue.map { scopeStart + $0 } ?? player.currentTime
        return max(0, (player.currentChapter?.end ?? player.duration) - now) / speedFactor
    }

    private func preciseDuration(_ seconds: Double) -> String {
        let total = Int(max(0, seconds).rounded(.down))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let remainingSeconds = total % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m \(remainingSeconds)s" }
        return "\(remainingSeconds)s"
    }

    // MARK: - Controls

    private var transportControls: some View {
        HStack(spacing: 0) {
            controlButton("backward.end.fill", size: 21, label: "Previous chapter") { player.previousChapter() }
            skipButton(back: true, seconds: settings.skipBackInterval) { player.skipBackward() }

            // The play button wears the app theme's colour (not the cover's), by request.
            BadgePlayButton(isPlaying: player.isPlaying, size: 64, color: Theme.accent) {
                player.togglePlayPause()
            }
            .frame(maxWidth: .infinity)

            skipButton(back: false, seconds: settings.skipForwardInterval) { player.skipForward() }
            controlButton("forward.end.fill", size: 21, label: "Next chapter") { player.nextChapter() }
        }
        .padding(.horizontal, Spacing.s)
    }

    /// A thin, roomy skip circle; the number stays small.
    private func skipButton(back: Bool, seconds: Double, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            SkipGlyph(back: back, seconds: seconds, size: 30, numberSize: 10)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, minHeight: 56)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Skip \(back ? "back" : "forward") \(Int(seconds)) seconds")
    }

    private func controlButton(_ symbol: String, size: CGFloat, label: String,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .regular))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, minHeight: 56)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Option chips

    private var playerOptions: some View {
        // Fixed-width chips, grouped in the middle rather than stretched edge to edge.
        HStack(spacing: Spacing.xs) {
            optionButton(accessibilityLabel: "Playback speed, \(TimeFormat.speed(player.speed))") {
                Text(TimeFormat.speed(player.speed))
                    .font(.subheadline.weight(.bold).monospacedDigit())
            } action: {
                activeSheet = .speed
            }

            optionButton(accessibilityLabel: "Add bookmark") {
                Image(systemName: "bookmark.fill")
            } action: {
                savedBookmark = player.addBookmark()
                bookmarkSaved += 1
                if savedBookmark != nil { activeSheet = .bookmarkSaved }
            }

            optionButton(accessibilityLabel: "Open chapters") {
                Image(systemName: "list.bullet")
            } action: {
                activeSheet = .chapters
            }

            AudioOutputChip()

            optionButton(accessibilityLabel: "More player options") {
                Image(systemName: "ellipsis")
            } action: {
                activeSheet = .more
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// A glass chip, 64 × 36 points to look light, with a 64 × 44-point tap area.
    private func optionButton<Content: View>(
        accessibilityLabel: String,
        @ViewBuilder content: () -> Content,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            content()
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 64, height: 36)
                .playerGlass(in: Capsule())
                .frame(height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Audio output (AirPlay)

/// A chip that opens the system's audio output picker: AirPlay speakers and TVs, Bluetooth
/// headphones, or the iPhone itself. Its icon is the same colour as the other chips' icons, and
/// shows where the sound is going (AirPlay, AirPods, headphones, car). The system picker sits on
/// top, invisible, so a tap anywhere on the chip opens it.
private struct AudioOutputChip: View {
    /// Looked up once when shown and on route changes, off the main thread: asking the audio
    /// system can take a moment, and the player redraws often (every frame while it moves).
    @State private var output: AudioOutput?

    var body: some View {
        Image(systemName: output?.symbol ?? "airplay.audio")
            .font(.body.weight(.semibold))
            .foregroundStyle(.primary)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 64, height: 36)
            .playerGlass(in: Capsule())
            .overlay { InvisibleRoutePicker() }
            .frame(height: 44)
            .task { output = await AudioOutput.load() }
            .onReceive(NotificationCenter.default
                .publisher(for: AVAudioSession.routeChangeNotification)
                .receive(on: DispatchQueue.main)) { _ in
                Task { output = await AudioOutput.load() }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Audio output, \(output?.name ?? "iPhone")")
    }
}

/// Where the sound is going right now.
private struct AudioOutput: Equatable, Sendable {
    var symbol: String
    var name: String

    /// `current()`, worked out off the main thread.
    static func load() async -> AudioOutput {
        await Task.detached(priority: .utility) { AudioOutput.current() }.value
    }

    static func current() -> AudioOutput {
        guard let port = AVAudioSession.sharedInstance().currentRoute.outputs.first else {
            return AudioOutput(symbol: "airplay.audio", name: "iPhone")
        }
        switch port.portType {
        case .airPlay:
            return AudioOutput(symbol: "airplay.audio", name: port.portName)
        case .bluetoothA2DP, .bluetoothLE, .bluetoothHFP:
            let isAirPods = port.portName.localizedCaseInsensitiveContains("airpods")
            return AudioOutput(symbol: isAirPods ? "airpods" : "headphones", name: port.portName)
        case .headphones, .usbAudio:
            return AudioOutput(symbol: "headphones", name: port.portName)
        case .carAudio:
            return AudioOutput(symbol: "car.fill", name: port.portName)
        default:
            return AudioOutput(symbol: "airplay.audio", name: "iPhone")
        }
    }
}

/// The system AirPlay / audio route button, made invisible (but still tappable), so the chip's
/// own icon shows instead of the system one.
private struct InvisibleRoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = false
        view.tintColor = .clear
        view.activeTintColor = .clear
        view.backgroundColor = .clear
        // Nearly transparent, not fully: views below 1% opacity stop receiving taps.
        view.alpha = 0.02
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

extension EnvironmentValues {
    /// The app's real light/dark, passed into the player (which forces light for itself), so
    /// full pages opened from it can follow the app instead.
    @Entry var appColorScheme: ColorScheme = .light
}
