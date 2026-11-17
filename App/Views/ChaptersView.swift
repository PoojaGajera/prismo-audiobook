import SwiftUI

/// Table of contents.
struct ChaptersView: View {
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    /// The playing book's cover colours (set by the player).
    @Environment(\.coverTheme) private var theme
    @State private var confirmRestore = false
    @ObservedObject private var scanner = ChapterScanner.shared

    private var needsChapters: Bool {
        guard let book = player.book else { return false }
        return book.chapters.count <= 1
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    if let book = player.book, needsChapters || scanner.isScanning(book.id)
                        || scanner.lastOutcome[book.id] != nil {
                        findChaptersCard(book)
                    }
                    if let book = player.book {
                        Section {
                            ForEach(Array(book.chapters.enumerated()), id: \.offset) { index, chapter in
                                let missing = ChapterDetector.rescanNumbers(in: book.chapters, at: index)
                                Button {
                                    // Tapping a chapter goes there and plays it.
                                    player.jumpToChapter(index)
                                    if !player.isPlaying { player.play() }
                                    dismiss()
                                } label: {
                                    row(index: index, chapter: chapter)
                                }
                                .buttonStyle(.plain)
                                // A chapter that may hide a missed one (Chapter 1 followed by
                                // Chapter 3): long-press to listen to it again (or to stop that).
                                .contextMenu {
                                    if let scan = scanner.chapterScan, scan.bookID == book.id, scan.index == index {
                                        Button(role: .destructive) { scanner.cancelChapterScan() } label: {
                                            Label("Stop Scanning", systemImage: "stop.circle")
                                        }
                                    } else if !missing.isEmpty, scanner.chapterScan == nil {
                                        Button { scanner.scanChapter(book, index: index) } label: {
                                            Label("Rescan This Chapter",
                                                  systemImage: "magnifyingglass")
                                        }
                                    }
                                }
                                .id(index)
                                .listRowBackground(index == player.currentChapterIndex ? theme.accent.opacity(0.16) : theme.chip)
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
                .listRowSeparatorTint(theme.onChip.opacity(0.12))
                // The book cover's colours, like the player and its other sheets.
                .background { theme.sheet.ignoresSafeArea() }
                .onAppear {
                    proxy.scrollTo(player.currentChapterIndex, anchor: .center)
                }
            }
            .navigationTitle(player.book?.title ?? "Chapters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        if let book = player.book {
                            if scanner.isScanning(book.id) {
                                Button { scanner.cancel(book.id) } label: {
                                    Label("Stop Finding Chapters", systemImage: "stop.circle")
                                }
                            } else {
                                Button { scanner.find(book) } label: {
                                    Label(needsChapters ? "Find Chapters" : "Find Chapters Again",
                                          systemImage: "wand.and.stars")
                                }
                            }
                        }
                        if player.book?.originalChapters != nil {
                            Button(role: .destructive) { confirmRestore = true } label: {
                                Label("Restore Original Chapters", systemImage: "arrow.uturn.backward")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    // Menu items in the normal text colour (the accent was hard to read on them).
                    .tint(Color.primary)
                    .accessibilityLabel("Chapter options")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert(item: Binding(get: { scanner.chapterScanOutcome.flatMap { $0.bookID == player.book?.id ? $0 : nil } },
                                 set: { scanner.chapterScanOutcome = $0 })) { outcome in
                if outcome.offerWholeBook, let book = player.book {
                    return Alert(title: Text("Chapter Scan"), message: Text(outcome.message),
                                 primaryButton: .default(Text("Scan Whole Book")) { scanner.find(book) },
                                 secondaryButton: .cancel(Text("Not Now")))
                }
                return Alert(title: Text("Chapter Scan"), message: Text(outcome.message), dismissButton: .default(Text("OK")))
            }
            .confirmationDialog("Restore the original chapters?", isPresented: $confirmRestore, titleVisibility: .visible) {
                Button("Restore", role: .destructive) { player.restoreOriginalChapters() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The automatically found chapters will be removed.")
            }
        }
    }

    /// Find Chapters runs in the background (`ChapterScanner`): this card starts it, shows its
    /// progress, and says how it went. The player can be closed, or another book played, meanwhile.
    private func findChaptersCard(_ book: Book) -> some View {
        let scanning = scanner.progress[book.id]
        let isCurrent = scanner.current == book.id
        return Section {
            VStack(alignment: .leading, spacing: Spacing.s) {
                HStack(spacing: Spacing.s) {
                    MascotView(size: 48, mood: scanning != nil ? .listening : .curious, headphones: scanning != nil)
                    Text(scanning != nil ? "Finding chapters…" : (needsChapters ? "This book has no chapters" : "Find chapters"))
                        .font(Theme.title(.headline))
                }
                if let scanning {
                    ProgressView(value: isCurrent ? scanning : 0)
                        .tint(theme.accent)
                    Text(isCurrent
                         ? "\(Int(scanning * 100))%"
                           + ((scanner.foundSoFar[book.id] ?? 0) > 0 ? " · \(scanner.foundSoFar[book.id] ?? 0) chapters found so far" : "")
                           + ". You can close the player or play another book; the chapters appear here when it's done."
                         : "Waiting for another book to finish first.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                    Button(role: .destructive) { scanner.cancel(book.id) } label: {
                        Text("Stop").font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                } else {
                    Text(scanner.lastOutcome[book.id]
                         ?? "I can listen through it and add a chapter wherever the narrator announces one. It runs in the background.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                    if needsChapters {
                        Button { scanner.find(book) } label: {
                            Label(scanner.lastOutcome[book.id] == nil ? "Find Chapters" : "Try Again",
                                  systemImage: "wand.and.stars")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, Spacing.m)
                                .padding(.vertical, Spacing.xs)
                                .background(theme.accent, in: Capsule())
                                .foregroundStyle(Color.white)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, Spacing.xs)
            .listRowBackground(theme.chip)
        }
    }

    private func row(index: Int, chapter: Chapter) -> some View {
        let isCurrent = index == player.currentChapterIndex
        let isPast = index < player.currentChapterIndex
        return HStack(spacing: 12) {
            Group {
                if isCurrent {
                    Image(systemName: player.isPlaying ? "speaker.wave.2.fill" : "speaker.fill")
                        .foregroundStyle(Theme.readable(theme.accent, on: Color.white))
                        .symbolEffect(.variableColor.iterative, options: .repeating, isActive: player.isPlaying)
                } else {
                    Text("\(index + 1)")
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .font(.subheadline.monospacedDigit())
            .frame(width: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(chapter.title)
                    .font(isCurrent ? Theme.title(.body) : .body)
                    .foregroundStyle(isPast ? Theme.secondaryText : Color.primary)
                    .lineLimit(2)
                if let scan = scanner.chapterScan, scan.bookID == player.book?.id, scan.index == index {
                    // Being listened to for a missed chapter: just a progress line and the percent.
                    HStack(spacing: Spacing.xs) {
                        IridescentBar(value: scan.progress, height: 3, tint: theme.accent)
                        Text("\(Int(scan.progress * 100))%")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .padding(.top, 2)
                }
                if isCurrent {
                    IridescentBar(value: chapter.duration > 0 ? (player.currentTime - chapter.start) / chapter.duration : 0, height: 3,
                                  tint: theme.accent)
                        .padding(.top, 2)
                }
            }

            Spacer()

            Text(TimeFormat.clock(chapter.duration / (settings.adjustForSpeed ? player.speed : 1)))
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}
