import SwiftUI
import UIKit

/// "Find Chapters": listens through a book for the narrator announcing each chapter.
struct ChapterDetectionView: View {
    @EnvironmentObject private var player: PlayerController
    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .setup
    @State private var task: Task<Void, Never>?

    enum Phase {
        case setup
        case running(stage: String, fraction: Double)
        case result([Chapter])
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .setup: setup
                case .running(let stage, let fraction): running(stage: stage, fraction: fraction)
                case .result(let chapters): result(chapters)
                case .failed(let message): failed(message)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Find Chapters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        task?.cancel()
                        dismiss()
                    }
                }
            }
        }
        .interactiveDismissDisabled(isRunning)
        .onDisappear {
            task?.cancel()
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private var isRunning: Bool {
        if case .running = phase { return true }
        return false
    }

    // MARK: - Setup

    private var setup: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        MascotView(size: 56, mood: .happy, headphones: true)
                        Text("Let's find the chapters")
                            .font(Theme.title(.headline))
                    }
                    Text("I'll listen through the whole book for the narrator announcing each chapter, like “Chapter one” or “Chapter 12”, and add a break at every one. Everything happens on your iPhone.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section {
                Button(action: start) {
                    HStack {
                        Spacer()
                        Label("Find Chapters", systemImage: "waveform.and.mic")
                            .font(.headline)
                            .foregroundStyle(Theme.onAccent)
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
                .listRowBackground(Theme.accent)
            } footer: {
                Text("Long books take a while. Keep the app open while it works; you can keep listening in the meantime.")
            }
        }
    }

    // MARK: - Running

    private func running(stage: String, fraction: Double) -> some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: max(0.02, fraction))
                    .stroke(AngularGradient(colors: [Color(hex: 0x5FD3FF), Theme.accent, Theme.lilac, Theme.blush, Color(hex: 0x5FD3FF)],
                                            center: .center),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.3), value: fraction)
                MascotView(size: 104, mood: .listening, headphones: true)
            }
            .frame(width: 170, height: 170)

            VStack(spacing: 6) {
                Text(stage)
                    .font(Theme.title(.headline))
                Text("\(Int(fraction * 100))%")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            Text("Keep the app open. You can keep listening while it works.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Result

    @ViewBuilder
    private func result(_ chapters: [Chapter]) -> some View {
        if chapters.count < 2 {
            VStack(spacing: 16) {
                Spacer()
                MascotView(size: 120, mood: .sad, headphones: true)
                Text("No chapter announcements heard")
                    .font(Theme.title(.title3))
                Text("This narrator doesn't seem to read out chapter numbers, or the recording was hard to make out.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button("Try Again") { start() }
                    .buttonStyle(.borderedProminent)
                Button("Back") { phase = .setup }
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            List {
                Section {
                    HStack(spacing: 12) {
                        MascotView(size: 48, mood: .excited, headphones: true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Heard \(chapters.count) chapters")
                                .font(Theme.title(.headline))
                            Text("Based on the chapter numbers the narrator reads out")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Preview") {
                    ForEach(Array(chapters.enumerated()), id: \.offset) { index, chapter in
                        HStack {
                            Text("\(index + 1)")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 28, alignment: .leading)
                            Text(chapter.title)
                                .lineLimit(1)
                            Spacer()
                            Text(TimeFormat.clock(chapter.start))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .listRowBackground(Theme.surface)
                    }
                }

                Section {
                    Button {
                        player.replaceChapters(chapters, source: .detected)
                        dismiss()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Use These Chapters")
                                .font(.headline)
                                .foregroundStyle(Theme.onAccent)
                            Spacer()
                        }
                        .padding(.vertical, 6)
                    }
                    .listRowBackground(Theme.accent)

                    Button("Listen Again") { start() }
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                } footer: {
                    Text("You can restore the original chapters any time from Contents.")
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func failed(_ message: String) -> some View {
        VStack(spacing: 14) {
            Spacer()
            MascotView(size: 110, mood: .surprised)
            Text(message)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Back") { phase = .setup }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Work

    private func start() {
        guard let book = player.book else { return }
        let sources = book.files.map {
            ChapterDetector.Source(url: LibraryStore.shared.fileURL(for: book, file: $0), start: $0.start, duration: $0.duration)
        }
        let total = book.duration

        phase = .running(stage: "Getting ready…", fraction: 0)
        UIApplication.shared.isIdleTimerDisabled = true

        let reporter = ProgressReporter { stage, fraction in
            phase = .running(stage: stage, fraction: fraction)
        }

        task = Task {
            do {
                let found = try await ChapterDetector.detect(sources: sources, totalDuration: total) { stage, fraction in
                    reporter.report(stage, fraction)
                }
                phase = .result(found.chapters)
            } catch is CancellationError {
                phase = .setup
            } catch {
                phase = .failed(error.localizedDescription)
            }
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
}

/// Forwards progress from the background detector to the UI, at most a few times a second.
private final class ProgressReporter: @unchecked Sendable {
    private let lock = NSLock()
    private var lastSent = Date.distantPast
    private let update: @MainActor (String, Double) -> Void

    init(update: @escaping @MainActor (String, Double) -> Void) {
        self.update = update
    }

    func report(_ stage: String, _ fraction: Double) {
        lock.lock()
        let now = Date()
        let shouldSend = now.timeIntervalSince(lastSent) > 0.25 || fraction >= 1
        if shouldSend { lastSent = now }
        lock.unlock()
        guard shouldSend else { return }
        let update = self.update
        Task { @MainActor in update(stage, fraction) }
    }
}
