import SwiftUI

struct PlayerView: View {
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var scrubValue: Double?
    @State private var activeSheet: PlayerSheet?
    @State private var showBookmarkPrompt = false
    @State private var bookmarkNote = ""
    @State private var bookmarkTime: Double = 0

    enum PlayerSheet: String, Identifiable {
        case chapters, bookmarks, speed, settings
        var id: String { rawValue }
    }

    var body: some View {
        Group {
            if let book = player.book {
                content(book)
            } else {
                ContentUnavailableView("Nothing playing", systemImage: "headphones")
            }
        }
        .sheet(item: $activeSheet) { sheet in
            Group {
                switch sheet {
                case .chapters: ChaptersView()
                case .bookmarks: BookmarksView()
                case .speed: SpeedView().presentationDetents([.height(340)])
                case .settings: SettingsView()
                }
            }
            .environmentObject(player)
            .environmentObject(settings)
            .tint(.orange)
        }
        .alert("Add Bookmark", isPresented: $showBookmarkPrompt) {
            TextField("Note (optional)", text: $bookmarkNote)
            Button("Save") { player.addBookmark(at: bookmarkTime, note: bookmarkNote) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("At \(TimeFormat.clock(bookmarkTime))")
        }
        .alert("Playback problem", isPresented: Binding(
            get: { player.errorMessage != nil },
            set: { if !$0 { player.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(player.errorMessage ?? "")
        }
    }

    // MARK: - Layout

    private func content(_ book: Book) -> some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: 8)

            CoverView(book: book, cornerRadius: 14)
                .frame(maxWidth: 300)
                .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
                .padding(.horizontal, 32)

            Spacer(minLength: 12)

            VStack(spacing: 4) {
                Text(book.title)
                    .font(.title3.weight(.bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text(book.author)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                chapterButton
            }
            .padding(.horizontal)

            progressSection
                .padding(.horizontal, 24)
                .padding(.top, 14)

            transportControls
                .padding(.top, 10)

            volumeRow
                .padding(.horizontal, 28)
                .padding(.top, 14)

            bottomBar
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 12)
        }
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            Spacer()
            Text("Now Playing")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Button { activeSheet = .settings } label: {
                Image(systemName: "gearshape")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 8)
        .foregroundStyle(.primary)
    }

    @ViewBuilder
    private var chapterButton: some View {
        if player.chapters.count > 1, let chapter = player.currentChapter {
            Button { activeSheet = .chapters } label: {
                HStack(spacing: 4) {
                    Text("\(player.currentChapterIndex + 1)/\(player.chapters.count)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Text(chapter.title)
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.thinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
    }

    // MARK: - Progress

    private var useChapter: Bool { settings.useChapterContext && player.chapters.count > 1 }
    private var scopeStart: Double { useChapter ? (player.currentChapter?.start ?? 0) : 0 }
    private var scopeDuration: Double {
        max(0.1, useChapter ? (player.currentChapter?.duration ?? player.duration) : player.duration)
    }
    private var displayedElapsed: Double {
        min(scopeDuration, max(0, scrubValue ?? (player.currentTime - scopeStart)))
    }
    private var speedFactor: Double { settings.adjustForSpeed ? player.speed : 1 }

    private var progressSection: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(get: { displayedElapsed }, set: { scrubValue = $0 }),
                in: 0...scopeDuration,
                onEditingChanged: { editing in
                    if !editing, let value = scrubValue {
                        player.seek(to: scopeStart + value)
                        scrubValue = nil
                    }
                })

            HStack {
                Text(TimeFormat.clock(displayedElapsed))
                Spacer()
                if player.speed != 1 {
                    Text(TimeFormat.speed(player.speed))
                        .foregroundStyle(.tint)
                }
                Spacer()
                Text(rightLabel)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)

            if settings.showTotalRemaining {
                Text(totalRemainingLine)
                    .font(.footnote.weight(.medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
    }

    private var rightLabel: String {
        if settings.useRemainingTime {
            return "-" + TimeFormat.clock((scopeDuration - displayedElapsed) / speedFactor)
        }
        return TimeFormat.clock(scopeDuration)
    }

    private var totalRemainingLine: String {
        let elapsedInBook = scrubValue.map { scopeStart + $0 } ?? player.currentTime
        let remaining = max(0, player.duration - elapsedInBook) / speedFactor
        var line = "\(TimeFormat.short(remaining)) left in book"
        if settings.adjustForSpeed && player.speed != 1 { line += " at \(TimeFormat.speed(player.speed))" }
        return line
    }

    // MARK: - Controls

    private var transportControls: some View {
        HStack(spacing: 0) {
            controlButton("backward.end.fill", size: 22, label: "Previous chapter") { player.previousChapter() }
            controlButton(SkipIcon.name(back: true, seconds: settings.skipBackInterval), size: 30,
                          label: "Skip back \(Int(settings.skipBackInterval)) seconds") { player.skipBackward() }

            Button { player.togglePlayPause() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 76, height: 76)
                    .background(Circle().fill(Color.orange))
                    .contentTransition(.symbolEffect(.replace))
            }
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            .frame(maxWidth: .infinity)

            controlButton(SkipIcon.name(back: false, seconds: settings.skipForwardInterval), size: 30,
                          label: "Skip forward \(Int(settings.skipForwardInterval)) seconds") { player.skipForward() }
            controlButton("forward.end.fill", size: 22, label: "Next chapter") { player.nextChapter() }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
    }

    private func controlButton(_ symbol: String, size: CGFloat, label: String,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 56)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }

    private var volumeRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
            SystemVolumeSlider()
                .frame(height: 30)
            Image(systemName: "speaker.wave.3.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var bottomBar: some View {
        HStack {
            Button { activeSheet = .speed } label: {
                Text(TimeFormat.speed(player.speed))
                    .font(.headline.monospacedDigit())
                    .frame(minWidth: 56, minHeight: 44)
            }
            .accessibilityLabel("Playback speed")
            Spacer()
            Button {
                bookmarkTime = player.currentTime
                bookmarkNote = ""
                showBookmarkPrompt = true
            } label: {
                Image(systemName: "bookmark")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Add bookmark")
            Spacer()
            Button { activeSheet = .chapters } label: {
                Image(systemName: "list.bullet")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Table of contents")
            Spacer()
            Button { activeSheet = .bookmarks } label: {
                Image(systemName: "bookmark.square")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Bookmarks")
            Spacer()
            RoutePickerButton()
                .frame(width: 44, height: 44)
                .accessibilityLabel("Audio output")
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Speed

struct SpeedView: View {
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(spacing: 18) {
            Text("Playback Speed")
                .font(.headline)
                .padding(.top, 20)

            Text(TimeFormat.speed(player.speed))
                .font(.system(size: 44, weight: .bold).monospacedDigit())

            HStack {
                Button { player.setSpeed(player.speed - 0.05) } label: { Image(systemName: "minus.circle.fill") }
                Slider(value: Binding(get: { player.speed }, set: { player.setSpeed($0) }),
                       in: 0.5...3.0, step: 0.05)
                Button { player.setSpeed(player.speed + 0.05) } label: { Image(systemName: "plus.circle.fill") }
            }
            .font(.title2)
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(AppSettings.speedPresets, id: \.self) { preset in
                        Button { player.setSpeed(preset) } label: {
                            Text(TimeFormat.speed(preset))
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(abs(player.speed - preset) < 0.001 ? Color.orange : Color(.secondarySystemBackground),
                                            in: Capsule())
                                .foregroundStyle(abs(player.speed - preset) < 0.001 ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }

            Button("Use \(TimeFormat.speed(player.speed)) as default for new books") {
                settings.defaultSpeed = player.speed
            }
            .font(.footnote)
            .disabled(abs(settings.defaultSpeed - player.speed) < 0.001)

            Spacer(minLength: 0)
        }
    }
}
