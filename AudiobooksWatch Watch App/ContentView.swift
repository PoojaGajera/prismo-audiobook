import Combine
import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject private var session: WatchSession
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Group {
                if session.nowPlaying.hasBook {
                    NowPlayingView()
                } else {
                    NothingPlayingView()
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { session.refresh() }
        }
    }
}

// MARK: - Now playing

struct NowPlayingView: View {
    @EnvironmentObject private var session: WatchSession
    @State private var crownSpeed: Double = 1
    @State private var speedSend: Task<Void, Never>?
    @State private var showsChapters = false

    private var state: NowPlaying { session.nowPlaying }

    /// Tapping the speed steps through these; the Digital Crown sets any speed.
    private static let speedSteps: [Double] = [1, 1.25, 1.5, 1.75, 2]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let position = state.time(at: context.date)
            let scope = state.scope(at: position)
            let length = max(1, scope.end - scope.start)
            let progress = min(1, max(0, (position - scope.start) / length))

            VStack(spacing: 0) {
                // Book name (moves when it's too long) and chapter.
                VStack(spacing: 1) {
                    MarqueeText(text: state.title, font: .system(size: 16, weight: .semibold))
                        .id(state.title)
                    Text(state.chapterTitle(at: position) ?? state.author)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
                .shadow(color: .black.opacity(0.5), radius: 3, y: 1)

                Spacer(minLength: 4)

                // Rewind · play/pause · forward.
                HStack(spacing: 0) {
                    RoundButton(systemName: "gobackward.\(Self.symbolSeconds(state.skipBack))", size: 42,
                                label: "Back \(Int(state.skipBack)) seconds") { session.skipBack() }
                    Spacer(minLength: 4)
                    PlayButton(isPlaying: state.isPlaying, progress: progress) { session.togglePlayPause() }
                    Spacer(minLength: 4)
                    RoundButton(systemName: "goforward.\(Self.symbolSeconds(state.skipForward))", size: 42,
                                label: "Forward \(Int(state.skipForward)) seconds") { session.skipForward() }
                }

                Spacer(minLength: 4)

                // Speed on the left, chapter list on the right.
                HStack(spacing: 6) {
                    Button(action: nextSpeedStep) {
                        Text(Self.speedLabel(crownSpeed))
                            .font(.system(size: 14, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .background(.black.opacity(0.35), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Speed \(Self.speedLabel(crownSpeed))")
                    .accessibilityHint("Tap to change, or turn the Digital Crown.")

                    Spacer(minLength: 0)

                    if !session.isReachable {
                        Image(systemName: "iphone.slash")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.7))
                            .accessibilityLabel("iPhone not connected")
                    }

                    Spacer(minLength: 0)

                    RoundButton(systemName: "list.bullet", size: 30, label: "Chapters") { showsChapters = true }
                        .disabled(!state.hasChapters)
                        .opacity(state.hasChapters ? 1 : 0.4)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 2)
        }
        .background { CoverBackdrop(cover: state.cover) }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showsChapters) { NavigationStack { ChapterListView() } }
        // Digital Crown sets the speed (0.5× to 3×, in 0.05 steps).
        .focusable()
        .digitalCrownRotation($crownSpeed, from: 0.5, through: 3.0, by: 0.05,
                              sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
        .onAppear { crownSpeed = state.speed }
        .onChange(of: state.speed) { _, speed in
            if speedSend == nil, abs(speed - crownSpeed) > 0.001 { crownSpeed = speed }
        }
        .onChange(of: crownSpeed) { _, speed in
            let rounded = (speed * 20).rounded() / 20
            guard abs(rounded - state.speed) > 0.001 else { return }
            speedSend?.cancel()
            speedSend = Task {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                session.setSpeed(rounded)
                speedSend = nil
            }
        }
    }

    private func nextSpeedStep() {
        let current = (crownSpeed * 20).rounded() / 20
        let next = Self.speedSteps.first(where: { $0 > current + 0.001 }) ?? Self.speedSteps[0]
        crownSpeed = next
    }

    static func speedLabel(_ speed: Double) -> String {
        let rounded = (speed * 20).rounded() / 20
        var text = String(format: "%.2f", rounded)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text + "×"
    }

    /// SF Symbols only exist for some skip lengths.
    static func symbolSeconds(_ seconds: Double) -> String {
        let available = [5, 10, 15, 30, 45, 60, 75, 90]
        let value = Int(seconds)
        return available.contains(value) ? "\(value)" : ""
    }
}

/// One line of text that scrolls sideways, on a loop, when it doesn't fit.
private struct MarqueeText: View {
    let text: String
    let font: Font

    @State private var textWidth: CGFloat = 0
    @State private var boxWidth: CGFloat = 0
    @State private var moving = false

    private let gap: CGFloat = 32
    private let pointsPerSecond: CGFloat = 28

    private var overflows: Bool { textWidth > boxWidth + 1 && boxWidth > 0 }

    var body: some View {
        Text(text).font(font).lineLimit(1).hidden()
            .frame(maxWidth: .infinity)
            .overlay {
                GeometryReader { box in
                    HStack(spacing: gap) {
                        label
                            .background {
                                GeometryReader { g in
                                    Color.clear
                                        .onAppear { textWidth = g.size.width; start() }
                                        .onChange(of: g.size.width) { _, w in textWidth = w; start() }
                                }
                            }
                        if overflows { label }
                    }
                    .offset(x: moving ? -(textWidth + gap) : 0)
                    .frame(width: box.size.width, alignment: overflows ? .leading : .center)
                    .onAppear { boxWidth = box.size.width; start() }
                    .onChange(of: box.size.width) { _, w in boxWidth = w; start() }
                }
            }
            .clipped()
            .mask {
                if overflows {
                    LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.08),
                                           .init(color: .black, location: 0.92), .init(color: .clear, location: 1)],
                                   startPoint: .leading, endPoint: .trailing)
                } else {
                    Color.black
                }
            }
            .accessibilityElement()
            .accessibilityLabel(text)
    }

    private var label: some View {
        Text(text).font(font).foregroundStyle(.white).lineLimit(1).fixedSize()
    }

    private func start() {
        guard overflows, !moving else { return }
        let duration = Double((textWidth + gap) / pointsPerSecond)
        withAnimation(.linear(duration: duration).delay(1.5).repeatForever(autoreverses: false)) {
            moving = true
        }
    }
}

private struct PlayButton: View {
    let isPlaying: Bool
    let progress: Double
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(.black.opacity(0.35))
                Circle().stroke(.white.opacity(0.3), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: progress)
                Circle()
                    .fill(.white)
                    .padding(8)
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.black)
                    .offset(x: isPlaying ? 0 : 2)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 66, height: 66)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
        .accessibilityValue("\(Int(progress * 100)) percent of chapter")
    }
}

private struct RoundButton: View {
    let systemName: String
    let size: CGFloat
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName.hasSuffix(".") ? String(systemName.dropLast()) : systemName)
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(.black.opacity(0.35), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// The book cover filling the screen, darkened at the top and bottom so the text and buttons read.
private struct CoverBackdrop: View {
    let cover: Data?

    var body: some View {
        ZStack {
            Color.black
            if let cover, let image = UIImage(data: cover) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                LinearGradient(stops: [.init(color: .black.opacity(0.65), location: 0),
                                       .init(color: .black.opacity(0.15), location: 0.35),
                                       .init(color: .black.opacity(0.15), location: 0.6),
                                       .init(color: .black.opacity(0.7), location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Chapters

struct ChapterListView: View {
    @EnvironmentObject private var session: WatchSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let state = session.nowPlaying
        let current = state.chapterIndex(at: state.time(at: Date()))
        ScrollViewReader { proxy in
            List(state.chapterTitles.indices, id: \.self) { index in
                Button {
                    session.jumpToChapter(index)
                    dismiss()
                } label: {
                    HStack(spacing: 6) {
                        Text(state.chapterTitles[index])
                            .font(.body)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                        if index == current {
                            Image(systemName: state.isPlaying ? "speaker.wave.2.fill" : "speaker.fill")
                                .font(.caption)
                                .foregroundStyle(.tint)
                        }
                    }
                }
                .id(index)
                .accessibilityAddTraits(index == current ? .isSelected : [])
            }
            .navigationTitle("Chapters")
            .onAppear { proxy.scrollTo(current, anchor: .center) }
        }
    }
}

// MARK: - Nothing playing

struct NothingPlayingView: View {
    @EnvironmentObject private var session: WatchSession

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text(session.hasHeardFromPhone ? "Nothing playing" : "Connecting…")
                .font(.headline)
            Text("Start a book on your iPhone.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

#Preview {
    ContentView().environmentObject(WatchSession.shared)
}
