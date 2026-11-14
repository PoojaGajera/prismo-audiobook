import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var router: AppRouter

    @State private var showImporter = false
    @State private var showSettings = false
    @State private var stagedURLs: [URL] = []
    @State private var showGroupingDialog = false
    @State private var bookToDelete: Book?

    var body: some View {
        NavigationStack {
            Group {
                if library.books.isEmpty {
                    emptyState
                } else {
                    bookList
                }
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showImporter = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Import audiobook")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if player.book != nil {
                    MiniPlayerView { router.showPlayer = true }
                }
            }
            .overlay {
                if library.isImporting {
                    ProgressView("Importing and detecting chapters…")
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: AudioTypes.importable,
                      allowsMultipleSelection: true) { result in
            handlePicked(result)
        }
        .confirmationDialog("Import \(stagedURLs.count) files", isPresented: $showGroupingDialog, titleVisibility: .visible) {
            Button("One book (each file is a chapter)") { importStaged(single: true) }
            Button("Separate books") { importStaged(single: false) }
            Button("Cancel", role: .cancel) {
                library.discardStaged(stagedURLs)
                stagedURLs = []
            }
        } message: {
            Text("Are these files parts of one audiobook, or different books?")
        }
        .alert("Delete “\(bookToDelete?.title ?? "")”?", isPresented: Binding(
            get: { bookToDelete != nil },
            set: { if !$0 { bookToDelete = nil } })) {
            Button("Delete", role: .destructive) {
                if let book = bookToDelete { delete(book) }
                bookToDelete = nil
            }
            Button("Cancel", role: .cancel) { bookToDelete = nil }
        } message: {
            Text("The audio files, progress and bookmarks will be removed from this iPhone.")
        }
        .alert("Import", isPresented: Binding(
            get: { library.importMessage != nil },
            set: { if !$0 { library.importMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(library.importMessage ?? "")
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(settings)
                .tint(.orange)
        }
        .sheet(isPresented: $router.showPlayer) {
            PlayerView()
                .environmentObject(player)
                .environmentObject(settings)
                .tint(.orange)
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No audiobooks yet", systemImage: "headphones")
        } description: {
            Text("Import MP3, M4B or M4A files from the Files app. Chapters are detected automatically.")
        } actions: {
            Button("Import Audiobook") { showImporter = true }
                .buttonStyle(.borderedProminent)
        }
    }

    private var bookList: some View {
        List {
            ForEach(library.sortedBooks) { book in
                Button {
                    player.load(book, autoplay: true)
                    router.showPlayer = true
                } label: {
                    BookRow(book: book, isCurrent: player.book?.id == book.id, isPlaying: player.isPlaying)
                }
                .buttonStyle(.plain)
                .contextMenu { menu(for: book) }
                .swipeActions {
                    Button(role: .destructive) { bookToDelete = book } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func menu(for book: Book) -> some View {
        Button { player.load(book, autoplay: true) } label: { Label("Play", systemImage: "play.fill") }
        if book.isFinished {
            Button { setFinished(book, false) } label: { Label("Mark as Unfinished", systemImage: "circle") }
        } else {
            Button { setFinished(book, true) } label: { Label("Mark as Finished", systemImage: "checkmark.circle") }
        }
        Button { resetProgress(book) } label: { Label("Start Over", systemImage: "arrow.counterclockwise") }
        Divider()
        Button(role: .destructive) { bookToDelete = book } label: { Label("Delete", systemImage: "trash") }
    }

    // MARK: - Actions

    private func handlePicked(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, !urls.isEmpty else { return }
        library.isImporting = true
        Task {
            let staged = await Task.detached { LibraryStore.stage(urls) }.value
            library.isImporting = false
            if staged.count > 1 {
                stagedURLs = staged
                showGroupingDialog = true
            } else if !staged.isEmpty {
                await library.importStaged(staged, asSingleBook: true)
            } else {
                library.importMessage = "Couldn't copy the selected files."
            }
        }
    }

    private func importStaged(single: Bool) {
        let urls = stagedURLs
        stagedURLs = []
        Task { await library.importStaged(urls, asSingleBook: single) }
    }

    private func delete(_ book: Book) {
        if player.book?.id == book.id { player.unload() }
        library.delete(book)
    }

    private func setFinished(_ book: Book, _ finished: Bool) {
        if player.book?.id == book.id { player.setFinished(finished) } else { library.setFinished(book, finished) }
    }

    private func resetProgress(_ book: Book) {
        if player.book?.id == book.id { player.resetProgress() } else { library.resetProgress(book) }
    }
}

private struct BookRow: View {
    let book: Book
    let isCurrent: Bool
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 12) {
            CoverView(book: book, cornerRadius: 6)
                .frame(width: 60, height: 60)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if isCurrent {
                        Image(systemName: isPlaying ? "speaker.wave.2.fill" : "speaker.fill")
                            .font(.caption)
                            .foregroundStyle(.tint)
                    }
                    Text(book.title)
                        .font(.headline)
                        .lineLimit(2)
                }
                Text(book.author)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if book.isFinished {
                    Label("Finished", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    ProgressView(value: book.progress)
                        .tint(.orange)
                    Text(statusLine)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var statusLine: String {
        let chapters = book.chapters.count > 1 ? " · \(book.chapters.count) chapters" : ""
        if book.position < 1 { return "\(TimeFormat.short(book.duration))\(chapters)" }
        return "\(Int(book.progress * 100))% · \(TimeFormat.short(book.remaining)) left\(chapters)"
    }
}

struct MiniPlayerView: View {
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var settings: AppSettings
    var onTap: () -> Void

    var body: some View {
        if let book = player.book {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    CoverView(book: book, cornerRadius: 6)
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(book.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(player.currentChapter?.title ?? book.author)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Button { player.skipBackward() } label: {
                        Image(systemName: SkipIcon.name(back: true, seconds: settings.skipBackInterval))
                            .font(.title3)
                            .frame(width: 36, height: 36)
                    }
                    Button { player.togglePlayPause() } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2)
                            .frame(width: 40, height: 40)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                ProgressView(value: book.duration > 0 ? player.currentTime / book.duration : 0)
                    .tint(.orange)
                    .scaleEffect(x: 1, y: 0.6)
            }
            .buttonStyle(.plain)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
            .padding(.horizontal, 10)
            .padding(.bottom, 4)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
        }
    }
}
