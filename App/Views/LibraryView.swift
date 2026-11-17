import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    /// Not observed here on purpose: the player publishes its position twice a second while
    /// playing, which redrew the whole library and made long-press menus take seconds to open.
    /// The few parts that show live playback (`LiveBook`, `BottomBarSpace`) observe it themselves.
    private var player: PlayerController { PlayerController.shared }
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var router: AppRouter

    @State private var showImporter = false
    @State private var stagedURLs: [URL] = []
    @State private var showGroupingDialog = false
    @State private var bookToDelete: Book?
    @State private var choosingFolder = false
    @State private var bookToEdit: Book?
    /// The book whose long-press menu is open, and the one being pressed (it shrinks slightly).
    @State private var menuBook: UUID?
    @State private var longPressedBook: UUID?
    /// A finished book whose details page is open (finished books don't open the player).
    @State private var finishedBookShown: Book?
    /// True once the big "Library" heading has scrolled under the bar, so the bar shows a small title.
    @State private var headingScrolledAway = false
    /// "list" (default) or "tiles"; chosen in Settings → Library → View.
    @AppStorage(LibraryView.layoutKey) private var layout = "list"
    static let layoutKey = "libraryLayout"
    /// Covers glide between their list and card spots when the view style changes.
    @Namespace private var coverSpace
    /// Live pinch amount (1 = none), for a little give while pinching.
    @State private var pinch: CGFloat = 1
    /// Set once: earlier versions defaulted to tiles; everyone starts on the list view once.
    @AppStorage("libraryLayoutListDefault") private var listDefaultApplied = false
    /// The Finished section can be folded away (tap its heading); remembered between launches.
    @AppStorage("finishedSectionCollapsed") private var finishedCollapsed = false
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
            // Redrawn when the app theme changes, so every card picks up the new colours.
            .id(settings.playerBackground)
            .background { PrismBackground(style: .plain) }
            .navigationTitle("Library")
            // The big heading is drawn in the list itself (so it can sit lower, with room below the
            // buttons); the bar shows a small title only once that heading has scrolled away.
            .navigationBarTitleDisplayMode(.inline)
            // No navigation bar: it had no buttons left (View, Import and Sync are in Settings →
            // Library) and only added an empty gap above the greeting.
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                // Room for the tab bar and the now-playing panel's mini bar, which float above the library.
                BottomBarSpace()
            }
        }
        // Settings → Library → Import Audiobooks.
        .onChange(of: router.importRequest) { _, _ in showImporter = true }
        .onAppear {
            if !listDefaultApplied {
                listDefaultApplied = true
                layout = "list"
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
        .alert(deleteTitle, isPresented: Binding(
            get: { bookToDelete != nil },
            set: { if !$0 { bookToDelete = nil } })) {
            Button(bookToDelete?.hasAudio == false ? "Remove" : "Delete", role: .destructive) {
                if let book = bookToDelete { delete(book) }
                bookToDelete = nil
            }
            Button("Cancel", role: .cancel) { bookToDelete = nil }
        } message: {
            Text(deleteMessage)
        }
        .alert("Import", isPresented: Binding(
            get: { library.importMessage != nil },
            set: { if !$0 { library.importMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(library.importMessage ?? "")
        }
        .sheet(item: $finishedBookShown) { book in
            FinishedBookView(bookID: book.id)
                .environmentObject(library)
                .environmentObject(player)
                .environmentObject(settings)
                .environmentObject(router)
                .tint(Theme.accent)
        }
        .sheet(item: $bookToEdit) { book in
            BookDetailsView(book: book)
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
                .foregroundStyle(Theme.secondaryText)
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
                LibraryGreeting()
                    .padding(.horizontal, Spacing.xxs)
                    .padding(.top, Spacing.xs)

                if !unfinishedBooks.isEmpty {
                    Text("Your books")
                        .font(.title3.bold())
                        .foregroundStyle(.primary)
                        .padding(.horizontal, Spacing.xxs)
                        .padding(.top, Spacing.s)
                        .accessibilityAddTraits(.isHeader)
                }

                bookCollection(unfinishedBooks)

                // Finished books get their own section under the ones still in progress.
                if !finishedBooks.isEmpty {
                    sectionHeader("Finished", font: .title3.bold(), chevron: .subheadline.weight(.semibold),
                                  collapsed: $finishedCollapsed)
                        .padding(.top, Spacing.l)
                    if !finishedCollapsed {
                        bookCollection(finishedBooks)
                    }
                }
            }
            .padding(.horizontal, Spacing.m)
            .padding(.bottom, Spacing.l)
            .environment(\.coverNamespace, coverSpace)
            // A little give while pinching: the books follow the fingers slightly.
            .scaleEffect(min(1.05, max(0.95, 1 + (pinch - 1) * 0.15)), anchor: .top)
            .animation(.spring(duration: 0.5, bounce: 0.18), value: layout)
            .animation(.snappy, value: unfinishedBooks.map(\.id))
            .animation(.snappy, value: finishedBooks.map(\.id))
        }
        .scrollContentBackground(.hidden)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > 56
        } action: { _, scrolledAway in
            headingScrolledAway = scrolledAway
        }
        .refreshable { await syncAll() }
        // Pinch in: cards (tiles). Pinch out: the list. The covers glide to their new spots.
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in pinch = value.magnification }
                .onEnded { value in
                    let target: String? = value.magnification < 0.88 ? "tiles"
                        : value.magnification > 1.12 ? "list" : nil
                    withAnimation(.spring(duration: 0.5, bounce: 0.18)) {
                        if let target, target != layout { layout = target }
                        pinch = 1
                    }
                }
        )
        .sensoryFeedback(.impact(weight: .light), trigger: layout)
    }

    /// A section heading that folds its books away (an accordion). The chevron points down when
    /// open and right when closed.
    private func sectionHeader(_ title: String, font: Font, chevron: Font,
                               collapsed: Binding<Bool>) -> some View {
        Button {
            withAnimation(.snappy) { collapsed.wrappedValue.toggle() }
        } label: {
            HStack(alignment: .center, spacing: Spacing.xs) {
                Text(title)
                    .font(font)
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.down")
                    .font(chevron)
                    .foregroundStyle(Theme.secondaryText)
                    .rotationEffect(.degrees(collapsed.wrappedValue ? -90 : 0))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.xxs)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isHeader)
        .accessibilityValue(collapsed.wrappedValue ? "Collapsed" : "Expanded")
        .accessibilityHint(collapsed.wrappedValue ? "Shows the books" : "Hides the books")
    }

    private var unfinishedBooks: [Book] { library.sortedBooks.filter { !$0.isFinished } }
    private var finishedBooks: [Book] { library.sortedBooks.filter(\.isFinished) }

    /// The books as tiles or list cards, in the chosen layout.
    @ViewBuilder
    private func bookCollection(_ books: [Book]) -> some View {
        if layout == "list" {
            // One card per book, with a gap between them.
            LazyVStack(spacing: Spacing.s) {
                ForEach(books) { book in
                    bookButton(book) {
                        LiveBook(book: book) { position, isCurrent, isPlaying in
                            BookRow(book: book, position: position, isCurrent: isCurrent, isPlaying: isPlaying)
                                .padding(.vertical, Spacing.xxs)
                                .background(Theme.surface.opacity(0.7),
                                            in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }
                    }
                }
            }
        } else {
            LazyVGrid(columns: columns, alignment: .leading, spacing: Spacing.l) {
                ForEach(books) { book in
                    bookButton(book) {
                        LiveBook(book: book) { position, isCurrent, isPlaying in
                            BookTile(book: book, position: position, isCurrent: isCurrent, isPlaying: isPlaying)
                        }
                    }
                }
            }
        }
    }

    /// Tap opens the player (without playing), or the details page for a finished book.
    /// Long-press opens the book's menu in a small pop-up beside the card; the card itself stays
    /// where it is (no lifted preview, and it doesn't turn into the menu). The book's details card
    /// (`BookCard`) is on the open player instead.
    private func bookButton<Content: View>(_ book: Book,
                                           @ViewBuilder content: () -> Content) -> some View {
        Button {
            // The finger lifting after a long-press isn't a tap.
            if longPressedBook == book.id || menuBook == book.id {
                longPressedBook = nil
                return
            }
            open(book)
        } label: {
            content()
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        // Alongside the button (not instead of it), so taps stay instant and scrolling smooth.
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                longPressedBook = book.id
                menuBook = book.id
            }
        )
            .sensoryFeedback(.impact(weight: .medium), trigger: menuBook == book.id) { _, shown in shown }
            .popover(isPresented: Binding(
                get: { menuBook == book.id },
                set: { if !$0 { menuBook = nil; longPressedBook = nil } }
            )) {
                BookActionsMenu(groups: actions(for: book)) { action in
                    menuBook = nil
                    // Let the pop-up close before anything else (a sheet, a dialog) opens.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { action.run() }
                }
                .presentationCompactAdaptation(.popover)
            }
            .accessibilityActions {
                ForEach(actions(for: book).flatMap { $0 }) { action in
                    Button(action.title, action: action.run)
                }
            }
    }

    private func open(_ book: Book) {
        if book.isFinished {
            finishedBookShown = book
        } else {
            player.load(book, autoplay: false)
            router.showPlayer = true
        }
    }

    /// The book's menu items, in groups (a line is drawn between groups).
    private func actions(for book: Book) -> [[BookAction]] {
        if !book.hasAudio {
            // A finished-book record (its audio was removed): details only.
            return [
                [BookAction("Edit Details…", "pencil") { bookToEdit = book }],
                [BookAction("Remove from Finished", "trash", destructive: true) { bookToDelete = book }]
            ]
        }
        var main = [BookAction("Play", "play.fill") { player.load(book, autoplay: true) }]
        if book.isFinished {
            main.append(BookAction("Mark as Unfinished", "circle") { setFinished(book, false) })
        } else {
            main.append(BookAction("Mark as Finished", "checkmark.circle") { setFinished(book, true) })
        }
        main.append(BookAction("Start Over", "arrow.counterclockwise") { resetProgress(book) })
        main.append(BookAction("Edit Details…", "pencil") { bookToEdit = book })
        // Runs in the background; progress shows on the card.
        if ChapterScanner.shared.isScanning(book.id) {
            main.append(BookAction("Stop Finding Chapters", "stop.circle") { ChapterScanner.shared.cancel(book.id) })
        } else {
            main.append(BookAction(book.chapters.count <= 1 ? "Find Chapters" : "Find Chapters Again",
                                   "wand.and.stars") { ChapterScanner.shared.find(book) })
        }
        return [main, [BookAction("Delete", "trash", destructive: true) { bookToDelete = book }]]
    }

    // MARK: - Actions

    private func syncAll() async { await Self.syncAll() }

    static var isSyncing: Bool { FolderSync.shared.isSyncing || MetadataEnricher.shared.isRefreshing }

    /// Sync: new books from the watched folder, then fresh details for every book
    /// (except ones edited by hand; covers already there are kept). Pull to refresh in the
    /// library, or Settings → Library → Sync Books & Details.
    static func syncAll() async {
        guard !isSyncing else { return }
        let folderSync = FolderSync.shared
        let library = LibraryStore.shared
        if folderSync.isWatching { await folderSync.sync() }
        let result = await MetadataEnricher.shared.refreshAll()
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

    private var deleteTitle: String {
        let title = bookToDelete?.title ?? ""
        return bookToDelete?.hasAudio == false ? "Remove “\(title)” from Finished?" : "Delete “\(title)”?"
    }

    private var deleteMessage: String {
        guard let book = bookToDelete else { return "" }
        if !book.hasAudio { return "Its record and details will be removed." }
        if book.isFinished {
            return "The audio is removed from this iPhone. The book stays in Finished with its cover and details."
        }
        return "The audio files, progress and bookmarks will be removed from this iPhone."
    }

    /// A book still being listened to is deleted outright. A finished book keeps a record in
    /// Finished (only its audio goes); deleting that record removes it for good.
    private func delete(_ book: Book) {
        ChapterScanner.shared.forget(book.id)
        if player.book?.id == book.id { player.unload() }
        if book.isFinished && book.hasAudio {
            library.removeAudioKeepingRecord(book)
        } else {
            library.delete(book)
        }
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
    @Environment(\.coverNamespace) private var coverNamespace
    let book: Book
    /// Live position for the loaded book, the saved one otherwise.
    let position: Double
    let isCurrent: Bool
    let isPlaying: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CoverView(book: book, cornerRadius: 18)
                .matchedCover(book.id, coverNamespace)
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
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
            BookProgress(book: book, position: position)
        }
        .contentShape(Rectangle())
    }
}

/// List row: small cover, then title, author and progress.
private struct BookRow: View {
    @Environment(\.coverNamespace) private var coverNamespace
    let book: Book
    let position: Double
    let isCurrent: Bool
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 14) {
            CoverView(book: book, cornerRadius: 10)
                .matchedCover(book.id, coverNamespace)
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
                    .foregroundStyle(Theme.secondaryText)
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
                let found = scanner.foundSoFar[book.id] ?? 0
                // Short, to fit a tile: "Chapters · 34% · 2 found".
                Text(active ? "Chapters · \(Int(scan * 100))%" + (found > 0 ? " · \(found) found" : "")
                            : "Waiting to find chapters")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
            } else if book.isFinished {
                // Finished books sit in their own section: no progress bar, just the length.
                Text(TimeFormat.short(book.duration))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            } else {
                IridescentBar(value: bookProgress, height: 4)
                Text(statusLine)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
    }

    private var bookProgress: Double {
        book.duration > 0 ? min(1, max(0, position / book.duration)) : 0
    }

    /// Book percentage, plus time left in the whole book once it's started ("42% · 5h 12m left"),
    /// at the book's playback speed when "Adjust times for speed" is on.
    private var statusLine: String {
        if position < 1 { return "\(TimeFormat.short(book.duration)) · New" }
        let settings = AppSettings.shared
        let speed = settings.adjustForSpeed ? max(0.5, book.speed ?? settings.defaultSpeed) : 1
        return "\(Int(bookProgress * 100))% · \(TimeFormat.short(max(0, book.duration - position) / speed)) left"
    }
}

// MARK: - Live playback state

/// Gives one book card the player's live position and state. Only the cards observe the player,
/// so the library itself (and its long-press menus) isn't rebuilt on every position update.
private struct LiveBook<Content: View>: View {
    let book: Book
    let content: (_ position: Double, _ isCurrent: Bool, _ isPlaying: Bool) -> Content

    @EnvironmentObject private var player: PlayerController

    init(book: Book, @ViewBuilder content: @escaping (Double, Bool, Bool) -> Content) {
        self.book = book
        self.content = content
    }

    var body: some View {
        let isCurrent = player.book?.id == book.id
        content(isCurrent ? player.currentTime : book.position, isCurrent, player.isPlaying)
    }
}

/// Room at the bottom of the library for the mini bar, while a book is loaded.
// MARK: - Book menu

/// The long-press menu: plain rows (icon on the left, then the title),
/// with a line between groups.
private struct BookActionsMenu: View {
    let groups: [[BookAction]]
    let onSelect: (BookAction) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                if index > 0 {
                    Divider()
                }
                ForEach(group) { action in
                    Button {
                        onSelect(action)
                    } label: {
                        HStack(spacing: Spacing.s) {
                            Image(systemName: action.systemImage)
                                .frame(width: 24)
                            Text(action.title)
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(action.destructive ? Color.red : Color.primary)
                        .padding(.horizontal, Spacing.m)
                        .frame(height: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, Spacing.xxs)
        .frame(width: 250)
    }
}

/// Book cards shrink a little while pressed.
private struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

/// The top of the library: the mascot (it blinks and bobs, and pulls a face when tapped) with a
/// short hello for the time of day. Short and sweet.
private struct LibraryGreeting: View {
    /// The listener's first name, used in the hello.
    @AppStorage("userName") private var name = "Pooja"

    var body: some View {
        // Re-read every few minutes, so the hello follows the time of day.
        TimelineView(.periodic(from: .now, by: 300)) { context in
            let hour = Calendar.current.component(.hour, from: context.date)
            let greeting = Self.greeting(hour: hour, name: name)

            HStack(spacing: Spacing.s) {
                ReactiveMascot(size: 58, mood: greeting.mood, headphones: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(greeting.title)
                        .font(.title2.bold())
                        .foregroundStyle(.primary)
                    Text(greeting.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 64)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        }
    }

    private static func greeting(hour: Int, name: String) -> (title: String, subtitle: String, mood: MascotMood) {
        let name = name.trimmingCharacters(in: .whitespaces)
        let to = name.isEmpty ? "" : ", \(name)"
        switch hour {
        case 5..<12: return ("Good morning\(to)!", "Ready for a story?", .happy)
        case 12..<17: return ("Good afternoon\(to)!", "Time for a chapter?", .curious)
        case 17..<22: return ("Good evening\(to)!", "Settle in with a story.", .listening)
        default: return ("Hello\(to)!", "Up late? One more chapter?", .sleepy)
        }
    }
}

extension EnvironmentValues {
    /// The library's namespace for its covers, so they glide between list and card layouts.
    @Entry var coverNamespace: Namespace.ID? = nil
}

extension View {
    /// Ties this cover to the same book's cover in the other layout (list ⇄ cards).
    @ViewBuilder
    func matchedCover(_ id: UUID, _ namespace: Namespace.ID?) -> some View {
        if let namespace {
            matchedGeometryEffect(id: id, in: namespace)
        } else {
            self
        }
    }
}
