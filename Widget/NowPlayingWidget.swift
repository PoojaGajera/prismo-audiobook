import WidgetKit
import SwiftUI
import UIKit
import AppIntents

struct NowPlayingEntry: TimelineEntry {
    let date: Date
    let snapshot: NowPlayingSnapshot
    let cover: UIImage?
}

struct NowPlayingProvider: TimelineProvider {
    func placeholder(in context: Context) -> NowPlayingEntry {
        NowPlayingEntry(date: Date(), snapshot: .placeholder, cover: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (NowPlayingEntry) -> Void) {
        if context.isPreview && SharedStore.loadSnapshot()?.hasBook != true {
            completion(placeholder(in: context))
            return
        }
        let snapshot = SharedStore.loadSnapshot() ?? .empty
        completion(NowPlayingEntry(date: Date(), snapshot: snapshot.extrapolated(to: Date()), cover: SharedStore.loadCover()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NowPlayingEntry>) -> Void) {
        let snapshot = SharedStore.loadSnapshot() ?? .empty
        let cover = SharedStore.loadCover()
        let now = Date()

        if snapshot.isPlaying {
            // Keep the progress bar moving for the next 30 minutes; the app reloads us on any change.
            let entries = (0..<30).map { minute -> NowPlayingEntry in
                let date = now.addingTimeInterval(Double(minute) * 60)
                return NowPlayingEntry(date: date, snapshot: snapshot.extrapolated(to: date), cover: cover)
            }
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(30 * 60))))
        } else {
            completion(Timeline(entries: [NowPlayingEntry(date: now, snapshot: snapshot, cover: cover)], policy: .never))
        }
    }
}

struct NowPlayingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedConfig.widgetKind, provider: NowPlayingProvider()) { entry in
            NowPlayingWidgetView(entry: entry)
        }
        .configurationDisplayName("Now Playing")
        .description("Play, pause and skip your audiobook.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct NowPlayingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NowPlayingEntry

    private var s: NowPlayingSnapshot { entry.snapshot }

    var body: some View {
        content
            .widgetURL(URL(string: "\(SharedConfig.urlScheme)://player"))
            .containerBackground(for: .widget) { background }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemMedium: medium
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .accessoryInline: inline
        default: small
        }
    }

    @ViewBuilder
    private var background: some View {
        switch family {
        case .systemSmall, .systemMedium:
            ZStack {
                PrismImage()
                // Frost the glass so text stays readable in light and dark.
                Theme.background.opacity(0.55)
            }
        default:
            Color.clear
        }
    }

    // MARK: - Home Screen

    /// Big cover with the play/pause button on its corner, and the title underneath.
    private var small: some View {
        Group {
            if s.hasBook {
                VStack(spacing: 6) {
                    GeometryReader { geo in
                        let side = min(geo.size.width, geo.size.height)
                        cover(size: side)
                            .overlay(alignment: .bottomTrailing) {
                                playButton(size: side * 0.34)
                                    .padding(side * 0.04)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    Text(s.bookTitle)
                        .font(.system(.caption).weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
            } else {
                emptyState
            }
        }
    }

    /// Cover as tall as the widget; title, chapter number, progress, and the full set of controls.
    private var medium: some View {
        Group {
            if s.hasBook {
                GeometryReader { geo in
                    HStack(spacing: Spacing.s) {
                        cover(size: geo.size.height)
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text(s.bookTitle)
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(chapterLine)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer(minLength: Spacing.xxs)
                            ribbon
                            HStack {
                                Text(TimeFormat.clock(s.scopeElapsed))
                                Spacer()
                                Text("\(TimeFormat.short(s.bookRemaining)) left")
                            }
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            mediumControls
                                .padding(.top, Spacing.xxs)
                        }
                    }
                }
            } else {
                emptyState
            }
        }
    }

    /// Previous chapter, skip back, play/pause, skip forward, next chapter: compact glyphs spread
    /// evenly from the text's left edge to its right edge, so there's an equal gap between each.
    private var mediumControls: some View {
        HStack(spacing: 0) {
            Button(intent: PreviousChapterIntent()) {
                Image(systemName: "backward.end.fill").font(.system(size: 13))
                    .frame(width: 24, height: 36)
            }
            .accessibilityLabel("Previous chapter")
            Spacer(minLength: Spacing.xxs)
            Button(intent: SkipBackwardIntent()) {
                SkipGlyph(back: true, seconds: s.skipBack, size: 19, numberSize: 7)
                    .frame(width: 28, height: 36)
            }
            .accessibilityLabel("Skip back")
            Spacer(minLength: Spacing.xxs)
            playButton(size: 34)
            Spacer(minLength: Spacing.xxs)
            Button(intent: SkipForwardIntent()) {
                SkipGlyph(back: false, seconds: s.skipForward, size: 19, numberSize: 7)
                    .frame(width: 28, height: 36)
            }
            .accessibilityLabel("Skip forward")
            Spacer(minLength: Spacing.xxs)
            Button(intent: NextChapterIntent()) {
                Image(systemName: "forward.end.fill").font(.system(size: 13))
                    .frame(width: 24, height: 36)
            }
            .accessibilityLabel("Next chapter")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            MascotView(size: 58, mood: .curious, animated: false)
            Text("No audiobook")
                .font(.system(.caption).weight(.bold))
                .foregroundStyle(.primary)
            Text("Open the app to start listening")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Lock Screen

    private var circular: some View {
        Button(intent: TogglePlaybackIntent()) {
            Gauge(value: s.scopeProgress) {
                EmptyView()
            } currentValueLabel: {
                Image(systemName: s.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
            }
            .gaugeStyle(.accessoryCircularCapacity)
        }
        .buttonStyle(.plain)
    }

    private var rectangular: some View {
        HStack(spacing: 8) {
            Button(intent: TogglePlaybackIntent()) {
                Image(systemName: s.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 30))
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 1) {
                Text(s.hasBook ? s.bookTitle : "No audiobook")
                    .font(.headline)
                    .lineLimit(1)
                Text(s.hasBook ? s.chapterTitle : "Open the app")
                    .font(.caption)
                    .lineLimit(1)
                ProgressView(value: s.scopeProgress)
            }
        }
    }

    private var inline: some View {
        Label(s.hasBook ? "\(s.bookTitle) · \(TimeFormat.short(s.bookRemaining)) left" : "No audiobook",
              systemImage: s.isPlaying ? "headphones" : "pause")
    }

    // MARK: - Pieces

    private var chapterLine: String {
        s.chapterCount > 1 ? "Chapter \(s.chapterIndex + 1) of \(s.chapterCount)" : s.author
    }

    private func playButton(size: CGFloat) -> some View {
        Button(intent: TogglePlaybackIntent()) {
            PlayBadge(isPlaying: s.isPlaying, size: size)
                .shadow(color: Theme.accent.opacity(0.35), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(s.isPlaying ? "Pause" : "Play")
    }

    private func cover(size: CGFloat) -> some View {
        Group {
            if let image = entry.cover {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    PrismImage()
                        .environment(\.colorScheme, .light)
                    MascotView(size: size * 0.72, headphones: true, animated: false)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.14, style: .continuous)
                .strokeBorder(.white.opacity(0.6), lineWidth: 0.75)
        }
    }

    /// Iridescent progress ribbon.
    private var ribbon: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule()
                    .fill(Theme.iridescent)
                    .frame(width: max(4, geo.size.width * s.scopeProgress))
            }
        }
        .frame(height: 4)
    }
}
