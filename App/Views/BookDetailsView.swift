import SwiftUI
import PhotosUI

/// Edit Details: title, author, series, genre, year, publisher, description and cover.
/// Opened by long-pressing a book in the library.
struct BookDetailsView: View {
    let book: Book

    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Book
    @State private var pendingCover: UIImage?
    @State private var search: SearchMode?
    @State private var photoItem: PhotosPickerItem?

    enum SearchMode: String, Identifiable {
        case cover, details
        var id: String { rawValue }
    }

    init(book: Book) {
        self.book = book
        _draft = State(initialValue: book)
    }

    var body: some View {
        NavigationStack {
            Form {
                coverSection

                Section("Book") {
                    field("Title", $draft.title)
                    field("Author", $draft.author)
                    field("Series", optional($draft.series))
                }

                Section("More") {
                    field("Genre", optional($draft.genre))
                    field("Year", optional($draft.year))
                        .keyboardType(.numberPad)
                    field("Publisher", optional($draft.publisher))
                }

                Section("Description") {
                    // A fixed-height box that scrolls, so long descriptions can be read and edited in full.
                    TextEditor(text: optional($draft.summary))
                        .frame(height: 240)
                        .scrollContentBackground(.hidden)
                        .overlay(alignment: .topLeading) {
                            if (draft.summary ?? "").isEmpty {
                                Text("Description")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                }

                Section {
                    Button {
                        search = .details
                    } label: {
                        Label("Look Up Details Online…", systemImage: "magnifyingglass")
                    }
                } footer: {
                    Text("Searches Apple Books and Open Library. You choose what to use before anything changes.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Edit Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(item: $search) { mode in
                MetadataSearchView(title: searchTitle, author: draft.hasKnownAuthor ? draft.author : nil, mode: mode) { match, cover in
                    apply(match, cover: cover)
                }
                .environmentObject(settings)
                .tint(Theme.accent)
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        pendingCover = image
                    }
                    photoItem = nil
                }
            }
        }
    }

    // MARK: - Cover

    private var coverSection: some View {
        Section {
            HStack(spacing: 16) {
                Group {
                    if let pendingCover {
                        Image(uiImage: pendingCover)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 110, height: 110)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    } else {
                        CoverView(book: book, cornerRadius: 14)
                            .frame(width: 110, height: 110)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Theme.hairline, lineWidth: 0.75)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Button {
                        search = .cover
                    } label: {
                        Label("Change Cover…", systemImage: "photo.on.rectangle.angled")
                    }
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("From Photos", systemImage: "photo")
                    }
                }
                .buttonStyle(.borderless)
                .font(.subheadline.weight(.semibold))
            }
            .padding(.vertical, 4)
        } footer: {
            Text("Shows the publisher covers of every English edition of this book.")
        }
    }

    // MARK: - Helpers

    private var searchTitle: String {
        let author = draft.hasKnownAuthor ? draft.author : nil
        return TitleCleaner.searchCore(TitleCleaner.splitSeries(TitleCleaner.clean(draft.title, author: author)).title)
    }

    /// Label on top, value underneath, both left-aligned: long titles wrap onto more lines
    /// instead of squeezing beside the label.
    private func field(_ label: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(label, text: text, axis: .vertical)
                .lineLimit(1...4)
        }
        .padding(.vertical, 2)
    }

    /// Edits an optional string as plain text; empty means nil.
    private func optional(_ value: Binding<String?>) -> Binding<String> {
        Binding(get: { value.wrappedValue ?? "" },
                set: { value.wrappedValue = $0.isEmpty ? nil : $0 })
    }

    /// `match` is nil when only the cover was picked.
    private func apply(_ match: MetadataMatch?, cover: UIImage?) {
        if let cover { pendingCover = cover }
        guard let match else { return }
        draft.title = match.title
        if let author = match.author { draft.author = author }
        draft.series = match.series ?? draft.series
        draft.genre = match.genre ?? draft.genre
        draft.year = match.year ?? draft.year
        draft.publisher = match.publisher ?? draft.publisher
        draft.summary = match.summary ?? draft.summary
    }

    private func save() {
        let library = LibraryStore.shared
        var edited = draft
        edited.title = edited.title.trimmingCharacters(in: .whitespacesAndNewlines)
        edited.author = edited.author.trimmingCharacters(in: .whitespacesAndNewlines)
        if edited.author.isEmpty { edited.author = "Unknown Author" }
        for keyPath in [\Book.series, \.genre, \.year, \.publisher, \.summary] {
            let trimmed = edited[keyPath: keyPath]?.trimmingCharacters(in: .whitespacesAndNewlines)
            edited[keyPath: keyPath] = (trimmed?.isEmpty ?? true) ? nil : trimmed
        }
        if let pendingCover, library.writeCover(pendingCover, for: edited) {
            edited.hasCover = true
            edited.coverVersion = (edited.coverVersion ?? 0) + 1
            edited.coverOrigin = "user"
        }
        edited.detailsChecked = true
        edited.detailsEdited = true // hand-edited: the automatic lookup leaves it alone
        library.saveDetails(edited)
        dismiss()
    }
}

// MARK: - Online search

/// Cover mode: every cover of this exact book (same title and author), from all the English
/// Apple Books stores and English print editions on Open Library, without duplicates.
/// Details mode: a list of matching books whose details can be copied in.
struct MetadataSearchView: View {
    var mode: BookDetailsView.SearchMode
    var author: String?
    /// Called with the chosen match (nil for "cover only") and the downloaded cover, if wanted.
    var onPick: (MetadataMatch?, UIImage?) -> Void

    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var query: String
    @State private var results: [MetadataMatch] = []
    @State private var state: LoadState = .idle
    @State private var choosing: MetadataMatch?
    @State private var downloading: UUID?

    enum LoadState { case idle, loading, loaded, failed }

    /// `title` is the book's title; `author` (when known) narrows covers to the right book.
    init(title: String, author: String?, mode: BookDetailsView.SearchMode,
         onPick: @escaping (MetadataMatch?, UIImage?) -> Void) {
        _query = State(initialValue: mode == .cover ? title : [title, author].compactMap { $0 }.joined(separator: " "))
        self.author = author
        self.mode = mode
        self.onPick = onPick
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                content
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(mode == .cover ? "Choose a Cover" : "Look Up Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .confirmationDialog(choosing?.title ?? "", isPresented: Binding(
                get: { choosing != nil }, set: { if !$0 { choosing = nil } }), titleVisibility: .visible) {
                if let match = choosing {
                    if match.coverURL != nil {
                        Button("Use Details and Cover") { pick(match, withCover: true, detailsToo: true) }
                    }
                    Button("Use Details Only") { pick(match, withCover: false, detailsToo: true) }
                    if match.coverURL != nil {
                        Button("Use Cover Only") { pick(match, withCover: true, detailsToo: false) }
                    }
                }
            }
        }
        .task { await runSearch() }
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(mode == .cover ? "Book title" : "Title and author", text: $query)
                .submitLabel(.search)
                .onSubmit { Task { await runSearch() } }
                .autocorrectionDisabled()
        }
        .padding(10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            VStack(spacing: 10) {
                ProgressView()
                Text(mode == .cover ? "Finding every edition…" : "Searching…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            ContentUnavailableView("Couldn't connect", systemImage: "wifi.slash",
                                   description: Text("Check your internet connection and try again."))
        case .loaded where results.isEmpty:
            ContentUnavailableView(mode == .cover ? "No covers found" : "No matches", systemImage: "books.vertical",
                                   description: Text(mode == .cover
                                                     ? "Only covers of this exact title\(author.map { " by \($0)" } ?? "") are shown. Check the title, or choose one from Photos."
                                                     : "Try fewer words."))
        case .loaded:
            if mode == .cover { coverGrid } else { matchList }
        }
    }

    private var coverGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 14)], spacing: 18) {
                ForEach(results) { match in
                    Button {
                        pick(match, withCover: true, detailsToo: false)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            thumbnail(match, size: nil)
                            Text(editionLine(match))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(downloading != nil)
                }
            }
            .padding(16)
        }
    }

    /// "Audiobook · 2015" or "Bloomsbury · 1998": what kind of edition the cover is from.
    private func editionLine(_ match: MetadataMatch) -> String {
        let kind: String?
        switch match.edition {
        case .ebook: kind = "Publisher edition"
        case .print: kind = match.publisher ?? "Print edition"
        case .audiobook: kind = "Audiobook"
        }
        return [kind, match.year].compactMap { $0 }.joined(separator: " · ")
    }

    private var matchList: some View {
        List(results) { match in
            Button {
                choosing = match
            } label: {
                HStack(spacing: 12) {
                    thumbnail(match, size: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(match.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                        if let author = match.author {
                            Text(author).font(.caption).foregroundStyle(.secondary)
                        }
                        Text([match.genre, match.year, match.series].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)
            .listRowBackground(Theme.surface)
            .disabled(downloading != nil)
        }
        .scrollContentBackground(.hidden)
    }

    private func thumbnail(_ match: MetadataMatch, size: CGFloat?) -> some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .frame(width: size, height: size)
            .overlay {
                AsyncImage(url: match.thumbnailURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Rectangle().fill(Color.primary.opacity(0.06))
                        .overlay { Image(systemName: "book.closed").foregroundStyle(.secondary) }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                if downloading == match.id {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.black.opacity(0.3))
                    ProgressView().tint(.white)
                }
            }
    }

    private func runSearch() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        state = .loading
        let preferred = CoverRegion(rawValue: settings.coverRegion) ?? .standard
        let found = mode == .cover
            ? await MetadataLookup.coverOptions(title: text, author: author, preferred: preferred)
            : await MetadataLookup.detailOptions(text, preferred: preferred)
        guard text == query.trimmingCharacters(in: .whitespaces) else { return } // a newer search replaced this one
        results = found ?? []
        state = found == nil ? .failed : .loaded
    }

    private func pick(_ match: MetadataMatch, withCover: Bool, detailsToo: Bool) {
        downloading = match.id
        Task {
            var image: UIImage?
            if withCover {
                // Audiobook art isn't used as a cover: look up the publisher's cover for that book.
                var url = match.coverURL
                if match.edition == .audiobook {
                    let region = CoverRegion(rawValue: settings.coverRegion) ?? .standard
                    url = await MetadataLookup.publisherCover(title: match.title, author: match.author, region: region)
                }
                if let url { image = await MetadataLookup.downloadImage(url) }
            }
            var chosen = match
            if detailsToo {
                // The physical book's description, not the store's narration or ebook text.
                chosen.summary = await MetadataLookup.bookDescription(title: match.title, author: match.author,
                                                                       fallback: match.summary)
            }
            downloading = nil
            onPick(detailsToo ? chosen : nil, image)
            dismiss()
        }
    }
}

extension MetadataMatch {
    /// A small version of the cover for lists and grids.
    var thumbnailURL: URL? {
        guard let coverURL else { return nil }
        let text = coverURL.absoluteString
            .replacingOccurrences(of: "1200x1200bb", with: "300x300bb")
            .replacingOccurrences(of: "-L.jpg", with: "-M.jpg")
        return URL(string: text)
    }
}
