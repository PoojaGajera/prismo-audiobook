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
            LinearGradient(colors: [Color(.secondarySystemBackground), Color(.systemBackground)],
                           startPoint: .top, endPoint: .bottom)
        default:
            Color.clear
        }
    }

    // MARK: - Home Screen

    private var small: some View {
        Group {
            if s.hasBook {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top) {
                        cover(size: 52)
                        Spacer(minLength: 0)
                        playButton(size: 42)
                    }
                    Spacer(minLength: 0)
                    Text(s.bookTitle)
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)
                    Text(s.chapterTitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    ProgressView(value: s.scopeProgress)
                        .tint(.orange)
                    Text("\(TimeFormat.short(s.bookRemaining)) left")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            } else {
                emptyState
            }
        }
    }

    private var medium: some View {
        Group {
            if s.hasBook {
                HStack(spacing: 14) {
                    cover(size: 116)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(s.bookTitle)
                            .font(.headline)
                            .lineLimit(1)
                        Text(chapterLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        ProgressView(value: s.scopeProgress)
                            .tint(.orange)
                        HStack {
                            Text(TimeFormat.clock(s.scopeElapsed))
                            Spacer()
                            Text("\(TimeFormat.short(s.bookRemaining)) left")
                        }
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        HStack {
                            Spacer()
                            Button(intent: SkipBackwardIntent()) {
                                Image(systemName: skipIcon(back: true, seconds: s.skipBack))
                                    .font(.title3)
                            }
                            Spacer()
                            playButton(size: 40)
                            Spacer()
                            Button(intent: SkipForwardIntent()) {
                                Image(systemName: skipIcon(back: false, seconds: s.skipForward))
                                    .font(.title3)
                            }
                            Spacer()
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }
                }
            } else {
                emptyState
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "headphones")
                .font(.title)
                .foregroundStyle(.orange)
            Text("No audiobook")
                .font(.caption.weight(.semibold))
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
        s.chapterCount > 1 ? "\(s.chapterIndex + 1)/\(s.chapterCount) · \(s.chapterTitle)" : s.author
    }

    private func playButton(size: CGFloat) -> some View {
        Button(intent: TogglePlaybackIntent()) {
            Image(systemName: s.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Circle().fill(Color.orange))
        }
        .buttonStyle(.plain)
    }

    private func cover(size: CGFloat) -> some View {
        Group {
            if let image = entry.cover {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: [.orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "headphones")
                        .font(.system(size: size * 0.4, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.14, style: .continuous))
    }

    private func skipIcon(back: Bool, seconds: Double) -> String {
        let n = Int(seconds)
        let base = back ? "gobackward" : "goforward"
        return [5, 10, 15, 30, 45, 60, 75, 90].contains(n) ? "\(base).\(n)" : base
    }
}
