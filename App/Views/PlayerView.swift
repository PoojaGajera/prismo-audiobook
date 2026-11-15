import SwiftUI

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

    @State private var scrubValue: Double?
    @State private var activeSheet: PlayerSheet?
    /// The bookmark just saved, for the "Bookmark Saved" sheet.
    @State private var savedBookmark: Bookmark?
    @State private var bookmarkSaved = 0
    /// Right-hand time under the progress bar: time left in the chapter, or (tapped) in the book.
    @AppStorage("progressShowsBookRemaining") private var showBookRemaining = false

    enum PlayerSheet: String, Identifiable {
        case chapters, bookmarks, speed, more, bookmarkSaved, settings, editDetails
        var id: String { rawValue }
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
            sheetContent(sheet)
                .environmentObject(player)
                .environmentObject(settings)
                .environment(\.coverTheme, theme)
                .tint(theme.accent)
                .presentationBackground(theme.sheet)
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
        // These size themselves to fit (PlayerSheetScaffold).
        case .speed:
            SpeedSheet { activeSheet = .settings }
                .presentationDragIndicator(.visible)
        case .more:
            MoreSheet { activeSheet = $0 }
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
                ChipIconButton(systemName: "chevron.down", label: "Close player", action: onCollapse)
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
                    .foregroundStyle(.secondary)
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
                        .foregroundStyle(.tertiary)
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
                        player.seek(to: scopeStart + value)
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

                Text("-" + TimeFormat.clock(chapterRemaining))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
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

            BadgePlayButton(isPlaying: player.isPlaying, size: 64, color: theme.accent) {
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
        HStack(spacing: Spacing.s) {
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

            optionButton(accessibilityLabel: "More player options") {
                Image(systemName: "ellipsis")
            } action: {
                activeSheet = .more
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// A solid chip, 64 × 36 points to look light, with a 64 × 44-point tap area.
    private func optionButton<Content: View>(
        accessibilityLabel: String,
        @ViewBuilder content: () -> Content,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            content()
                .font(.body.weight(.semibold))
                .foregroundStyle(theme.onChip)
                .frame(width: 64, height: 36)
                .background(theme.chip, in: Capsule())
                .frame(height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}
