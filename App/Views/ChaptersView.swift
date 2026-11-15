import SwiftUI

/// Table of contents.
struct ChaptersView: View {
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    /// The playing book's cover colours (set by the player).
    @Environment(\.coverTheme) private var theme
    @State private var showDetection = false
    @State private var confirmRestore = false

    private var needsChapters: Bool {
        guard let book = player.book else { return false }
        return book.chapters.count <= 1
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    if needsChapters {
                        findChaptersCard
                    }
                    if let book = player.book {
                        Section {
                            ForEach(Array(book.chapters.enumerated()), id: \.offset) { index, chapter in
                                Button {
                                    player.jumpToChapter(index)
                                    dismiss()
                                } label: {
                                    row(index: index, chapter: chapter)
                                }
                                .buttonStyle(.plain)
                                .id(index)
                                .listRowBackground(index == player.currentChapterIndex ? theme.accent.opacity(0.08) : Theme.surface)
                            }
                        } header: {
                            Label(book.chapterSource.summary, systemImage: "sparkles")
                                .font(.system(.footnote))
                                .textCase(nil)
                        } footer: {
                            Text("Total length \(TimeFormat.short(book.duration))")
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Theme.background.ignoresSafeArea())
                .onAppear {
                    proxy.scrollTo(player.currentChapterIndex, anchor: .center)
                }
            }
            .navigationTitle(player.book?.title ?? "Chapters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button { showDetection = true } label: {
                            Label(needsChapters ? "Find Chapters…" : "Find Chapters Again…", systemImage: "wand.and.stars")
                        }
                        if player.book?.originalChapters != nil {
                            Button(role: .destructive) { confirmRestore = true } label: {
                                Label("Restore Original Chapters", systemImage: "arrow.uturn.backward")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Chapter options")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showDetection) {
                ChapterDetectionView()
                    .environmentObject(player)
                    .tint(theme.accent)
            }
            .confirmationDialog("Restore the original chapters?", isPresented: $confirmRestore, titleVisibility: .visible) {
                Button("Restore", role: .destructive) { player.restoreOriginalChapters() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The automatically found chapters will be removed.")
            }
        }
    }

    private var findChaptersCard: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    MascotView(size: 48, mood: .curious)
                    Text("This book has no chapters")
                        .font(Theme.title(.headline))
                }
                Text("I can listen through it and add a chapter wherever the narrator announces one.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    showDetection = true
                } label: {
                    Label("Find Chapters", systemImage: "wand.and.stars")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(theme.accent, in: Capsule())
                        .foregroundStyle(Theme.onAccent)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
            .padding(.vertical, 6)
            .listRowBackground(Theme.surface)
        }
    }

    private func row(index: Int, chapter: Chapter) -> some View {
        let isCurrent = index == player.currentChapterIndex
        let isPast = index < player.currentChapterIndex
        return HStack(spacing: 12) {
            Group {
                if isCurrent {
                    Image(systemName: player.isPlaying ? "speaker.wave.2.fill" : "speaker.fill")
                        .foregroundStyle(theme.accent)
                        .symbolEffect(.variableColor.iterative, options: .repeating, isActive: player.isPlaying)
                } else {
                    Text("\(index + 1)")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline.monospacedDigit())
            .frame(width: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(chapter.title)
                    .font(isCurrent ? Theme.title(.body) : .body)
                    .foregroundStyle(isPast ? .secondary : .primary)
                    .lineLimit(2)
                if isCurrent {
                    IridescentBar(value: chapter.duration > 0 ? (player.currentTime - chapter.start) / chapter.duration : 0, height: 3,
                                  tint: theme.accent)
                        .padding(.top, 2)
                }
            }

            Spacer()

            Text(TimeFormat.clock(chapter.duration / (settings.adjustForSpeed ? player.speed : 1)))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}
