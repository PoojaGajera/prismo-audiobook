import SwiftUI
import UniformTypeIdentifiers

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
    @State private var choosingFolder = false
    @State private var bookToEdit: Book?
    /// True once the big "Library" heading has scrolled under the bar, so the bar shows a small title.
    @State private var headingScrolledAway = false
    /// "tiles" or "list"; remembered between launches.
    @AppStorage("libraryLayout") private var layout = "tiles"
    @ObservedObject private var folderSync = FolderSync.shared
    @ObservedObject private var enricher = MetadataEnricher.shared

    var body: some View {
        NavigationStack {
            Group {
                if library.books.isEmpty {
                    emptyState
                } else {
                    bookList
                }
            }
            .background { PrismBackground(style: .plain) }
            .navigationTitle("Library")
            // The big heading is drawn in the list itself (so it can sit lower, with room below the
            // buttons); the bar shows a small title only once that heading has scrolled away.
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Library")
                        .font(.headline)
                        .opacity(library.books.isEmpty || headingScrolledAway ? 1 : 0)
                        .animation(.easeInOut(duration: 0.2), value: headingScrolledAway)
                }
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                    if !library.books.isEmpty {
                        Button {
                            withAnimation(.snappy) { layout = layout == "list" ? "tiles" : "list" }
                        } label: {
                            Image(systemName: layout == "list" ? "square.grid.2x2" : "list.bullet")
                        }
                        .accessibilityLabel(layout == "list" ? "Show as tiles" : "Show as list")
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !library.books.isEmpty || folderSync.isWatching {
                        Button {
                            Task { await syncAll() }
                        } label: {
                            if isSyncing {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
                        }
                        .disabled(isSyncing)
                        .accessibilityLabel("Sync books and details")
                    }
                    Button { showImporter = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Import audiobook")
                }
            }
            .safeAreaInset(edge: .bottom) {
                // Room for the now-playing panel's mini bar, which floats above the library.
                if player.book != nil {
                    Color.clear.frame(height: NowPlayingPanel.miniBarHeight)
                }
            }
            .overlay {
                if library.isImporting {
                    VStack(spacing: 10) {
                        MascotView(size: 72, mood: .listening, headphones: true)
                        Text("Reading your book…")
                            .font(Theme.title(.subheadline))
                        Text("Looking for chapters")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(24)
                    .glassCard(cornerRadius: 24, material: true)
                }
            }
        }
        // Mini player ⇄ full player, YouTube Music style (sheets below still present on top of it).
        .overlay { NowPlayingPanel() }
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
        .sheet(item: $bookToEdit) { book in
            BookDetailsView(book: book)
                .environmentObject(settings)
                .tint(Theme.accent)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(settings)
                .tint(Theme.accent)
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            ZStack(alignment: .topTrailing) {
                ReactiveMascot(size: 150, mood: .curious, headphones: false)
                Text("Got a story\nfor me?")
                    .font(.system(.footnote).weight(.bold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .glassCard(cornerRadius: 14)
                    .offset(x: 70, y: -26)
            }
            .padding(.top, 20)
            Text("No books yet")
                .font(Theme.title(.title2, weight: .heavy))
            Text("Import MP3, M4B or M4A files from the Files app. Chapters are found automatically.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
            Button {
                showImporter = true
            } label: {
                Label("Import Audiobook", systemImage: "plus")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(Theme.accent, in: Capsule())
                    .foregroundStyle(Theme.onAccent)
                    .shadow(color: Theme.accent.opacity(0.35), radius: 12, y: 6)
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
            if !folderSync.isWatching {
                Button {
                    choosingFolder = true
                } label: {
                    Label("Use My Audiobooks Folder", systemImage: "folder")
                        .font(.subheadline.weight(.semibold))
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
            Spacer(minLength: 0)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                Task { await folderSync.choose(url) }
            }
        }
    }

    private let columns = [GridItem(.flexible(), spacing: 16, alignment: .top), GridItem(.flexible(), spacing: 16, alignment: .top)]

    private var bookList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                Text("Library")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, Spacing.l)
                    .padding(.horizontal, Spacing.xxs)

                if layout == "list" {
                    // One card per book, with a gap between them.
                    LazyVStack(spacing: Spacing.s) {
                        ForEach(library.sortedBooks) { book in
                            bookButton(book) { position, isCurrent in
                                BookRow(book: book, position: position, isCurrent: isCurrent, isPlaying: player.isPlaying)
                                    .padding(.vertical, Spacing.xxs)
                                    .background(Theme.surface.opacity(0.7),
                                                in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            }
                        }
                    }
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: Spacing.l) {
                        ForEach(library.sortedBooks) { book in
                            bookButton(book) { position, isCurrent in
                                BookTile(book: book, position: position, isCurrent: isCurrent, isPlaying: player.isPlaying)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.m)
            .padding(.bottom, Spacing.l)
            .animation(.snappy, value: library.sortedBooks.map(\.id))
        }
        .scrollContentBackground(.hidden)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > 56
        } action: { _, scrolledAway in
            headingScrolledAway = scrolledAway
        }
        .refreshable { await syncAll() }
    }

    /// Tap opens the player (without playing); long-press shows the book's menu.
    private func bookButton<Content: View>(_ book: Book,
                                           @ViewBuilder content: (Double, Bool) -> Content) -> some View {
        let isCurrent = player.book?.id == book.id
        return Button {
            player.load(book, autoplay: false)
            router.showPlayer = true
        } label: {
            content(isCurrent ? player.currentTime : book.position, isCurrent)
        }
        .buttonStyle(.plain)
        .contextMenu { menu(for: book) }
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
        Button { bookToEdit = book } label: { Label("Edit Details…", systemImage: "pencil") }
        Divider()
        Button(role: .destructive) { bookToDelete = book } label: { Label("Delete", systemImage: "trash") }
    }

    // MARK: - Actions

    private var isSyncing: Bool { folderSync.isSyncing || enricher.isRefreshing }

    /// Sync: new books from the watched folder, then fresh details for every book
    /// (except ones edited by hand; covers already there are kept).
    private func syncAll() async {
        guard !isSyncing else { return }
        if folderSync.isWatching { await folderSync.sync() }
        let result = await enricher.refreshAll()
        var message: String
        switch (result.checked, result.updated) {
        case (0, _): message = "No books to check."
        case (_, 0): message = "All \(result.checked) books are up to date."
        case (_, 1): message = "Updated the details of 1 book."
        default: message = "Updated the details of \(result.updated) books."
        }
        if result.failed > 0 {
            if result.checked == 0 {
                message = "Couldn't reach the book catalogue. Check your connection and try again."
            } else {
                message += " \(result.failed) couldn't be checked; try again later."
            }
        }
        library.post(message)
    }

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
        ChapterScanner.shared.cancel(book.id)
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

/// Grid tile. Every tile reserves the same space (two title lines, one author line, one
/// progress row) so covers and progress bars line up across a row; long titles end in "…".
private struct BookTile: View {
    let book: Book
    /// Live position for the loaded book, the saved one otherwise.
    let position: Double
    let isCurrent: Bool
    let isPlaying: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CoverView(book: book, cornerRadius: 18)
                .overlay(alignment: .topTrailing) {
                    BookBadge(book: book, isCurrent: isCurrent, isPlaying: isPlaying)
                        .padding(8)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(isCurrent ? Theme.accent : Theme.hairline, lineWidth: isCurrent ? 2 : 0.75)
                }
                .shadow(color: Theme.accent.opacity(0.14), radius: 12, y: 6)

            VStack(alignment: .leading, spacing: 3) {
                Text(book.title)
                    .font(Theme.title(.subheadline))
                    .lineLimit(2, reservesSpace: true)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(book.author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            BookProgress(book: book, position: position)
        }
        .contentShape(Rectangle())
    }
}

/// List row: small cover, then title, author and progress.
private struct BookRow: View {
    let book: Book
    let position: Double
    let isCurrent: Bool
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 14) {
            CoverView(book: book, cornerRadius: 10)
                .frame(width: 58, height: 58)
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(isCurrent ? Theme.accent : Theme.hairline, lineWidth: isCurrent ? 2 : 0.75)
                }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(book.title)
                        .font(Theme.title(.subheadline))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                    BookBadge(book: book, isCurrent: isCurrent, isPlaying: isPlaying, small: true)
                }
                Text(book.author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                BookProgress(book: book, position: position)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

/// "Now playing" or "Finished" marker.
private struct BookBadge: View {
    let book: Book
    let isCurrent: Bool
    let isPlaying: Bool
    var small = false

    var body: some View {
        if isCurrent {
            Image(systemName: "waveform")
                .font((small ? Font.caption2 : .caption).weight(.bold))
                .foregroundStyle(.white)
                .symbolEffect(.variableColor.iterative, options: .repeating, isActive: isPlaying)
                .padding(small ? 5 : 7)
                .background(Theme.accent, in: Circle())
                .accessibilityLabel(isPlaying ? "Now playing" : "Paused")
        } else if book.isFinished {
            Image(systemName: "checkmark")
                .font((small ? Font.caption2 : .caption).weight(.heavy))
                .foregroundStyle(.white)
                .padding(small ? 5 : 7)
                .background(Theme.blush, in: Circle())
                .accessibilityLabel("Finished")
        }
    }
}

/// Progress bar and one line of status: chapter search, "New", "42% · 12m left in chapter" or "Finished".
private struct BookProgress: View {
    let book: Book
    let position: Double

    @ObservedObject private var scanner = ChapterScanner.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let scan = scanner.progress[book.id] {
                let active = scanner.current == book.id
                IridescentBar(value: active ? scan : 0, height: 4)
                Label(active ? "Finding chapters · \(Int(scan * 100))%" : "Waiting to find chapters",
                      systemImage: "waveform")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                IridescentBar(value: book.isFinished ? 1 : bookProgress, height: 4)
                Text(statusLine)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
    }

    private var bookProgress: Double {
        book.duration > 0 ? min(1, max(0, position / book.duration)) : 0
    }

    /// Book percentage, plus time left in the current chapter once the book is started.
    private var statusLine: String {
        if book.isFinished { return "Finished" }
        if position < 1 { return "\(TimeFormat.short(book.duration)) · New" }
        let percent = "\(Int(bookProgress * 100))%"
        guard book.chapters.count > 1 else {
            return "\(percent) · \(TimeFormat.short(max(0, book.duration - position))) left"
        }
        let chapter = book.chapters[book.chapterIndex(at: position)]
        return "\(percent) · \(TimeFormat.short(max(0, chapter.end - position))) left in chapter"
    }
}
