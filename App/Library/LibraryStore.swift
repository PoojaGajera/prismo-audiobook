import Foundation
import UIKit
import UniformTypeIdentifiers

/// Owns the list of books and the audio files on disk.
@MainActor
final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()

    @Published private(set) var books: [Book] = []
    @Published var isImporting = false
    @Published var importMessage: String? {
        didSet { if importMessage == nil { showNextMessage() } }
    }
    private var queuedMessages: [String] = []

    private let rootURL: URL
    private var booksURL: URL { rootURL.appendingPathComponent("Books", isDirectory: true) }
    private var indexURL: URL { rootURL.appendingPathComponent("library.json") }

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        rootURL = support.appendingPathComponent("Library", isDirectory: true)
        try? FileManager.default.createDirectory(at: rootURL.appendingPathComponent("Books", isDirectory: true),
                                                 withIntermediateDirectories: true)
        load()
    }

    // MARK: - Queries

    var sortedBooks: [Book] {
        books.sorted { ($0.lastPlayed ?? $0.addedAt) > ($1.lastPlayed ?? $1.addedAt) }
    }

    func book(id: UUID) -> Book? { books.first { $0.id == id } }

    func folderURL(for book: Book) -> URL {
        booksURL.appendingPathComponent(book.folderName, isDirectory: true)
    }

    func fileURL(for book: Book, file: BookFile) -> URL {
        folderURL(for: book).appendingPathComponent(file.fileName)
    }

    func coverURL(for book: Book) -> URL? {
        book.hasCover ? folderURL(for: book).appendingPathComponent("cover.jpg") : nil
    }

    // MARK: - Mutations

    func update(_ book: Book) {
        guard let index = books.firstIndex(where: { $0.id == book.id }) else { return }
        books[index] = book
        save()
    }

    func delete(_ book: Book) {
        try? FileManager.default.removeItem(at: folderURL(for: book))
        books.removeAll { $0.id == book.id }
        save()
    }

    /// Replaces a book's chapters, keeping the originals so they can be restored.
    /// Used for books that aren't loaded in the player (otherwise go through `PlayerController`).
    @discardableResult
    func replaceChapters(of id: UUID, with chapters: [Chapter], source: ChapterSource) -> Bool {
        guard var b = book(id: id), b.chapterSource == .none, !chapters.isEmpty else { return false }
        if b.originalChapters == nil {
            b.originalChapters = b.chapters
            b.originalChapterSource = b.chapterSource
        }
        b.chapters = chapters
        b.chapterSource = source
        update(b)
        return true
    }

    /// Saves edited details, through the player when it's the loaded book.
    func saveDetails(_ edited: Book) {
        let player = PlayerController.shared
        if player.book?.id == edited.id {
            player.updateDetails(from: edited)
        } else if let current = book(id: edited.id) {
            update(current.withDetails(from: edited))
        }
        tidyChapterTitles(edited.id)
    }

    /// Chapter names that came from file names follow the book's tidy title:
    /// - a book without chapter markers has one chapter, named after the book;
    /// - a book made of several files has one chapter per file, with the file-name noise
    ///   ("01 - ", "_", "[64kbps]"…) removed.
    /// Chapters from the file's own markers or from Find Chapters are left as they are.
    func tidyChapterTitles(_ id: UUID) {
        guard let current = book(id: id) else { return }
        var chapters = current.chapters
        switch current.chapterSource {
        case .none where chapters.count == 1:
            chapters[0].title = current.title
        case .perFile:
            let author = current.hasKnownAuthor ? current.author : nil
            for i in chapters.indices {
                chapters[i].title = TitleCleaner.clean(chapters[i].title, author: author)
            }
        default:
            return
        }
        guard chapters != current.chapters else { return }
        let player = PlayerController.shared
        if player.book?.id == id {
            player.updateChapterTitles(chapters)
        } else {
            var updated = current
            updated.chapters = chapters
            update(updated)
        }
    }

    /// Writes a new cover.jpg for the book. The caller sets `hasCover` and bumps `coverVersion`.
    func writeCover(_ image: UIImage, for book: Book) -> Bool {
        guard let jpeg = ImageUtils.jpegData(image, maxDimension: 1000) else { return false }
        do {
            try jpeg.write(to: folderURL(for: book).appendingPathComponent("cover.jpg"), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    func setFinished(_ book: Book, _ finished: Bool) {
        var b = book
        b.isFinished = finished
        b.position = finished ? b.duration : b.position
        update(b)
    }

    func resetProgress(_ book: Book) {
        var b = book
        b.isFinished = false
        b.position = 0
        update(b)
    }

    // MARK: - Messages

    /// Shows a message, or queues it if another one is still on screen.
    func post(_ message: String) {
        if importMessage == nil { importMessage = message } else { queuedMessages.append(message) }
    }

    private func showNextMessage() {
        guard !queuedMessages.isEmpty else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400)) // let the previous alert finish dismissing
            if importMessage == nil, !queuedMessages.isEmpty { importMessage = queuedMessages.removeFirst() }
        }
    }

    // MARK: - Import

    /// Copies picked files into a private staging folder. Safe to call off the main thread.
    nonisolated static func stage(_ urls: [URL]) -> [URL] {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("Staging-\(UUID().uuidString)", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        var staged: [URL] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            var dest = dir.appendingPathComponent(url.lastPathComponent)
            var n = 2
            while fm.fileExists(atPath: dest.path) {
                let stem = url.deletingPathExtension().lastPathComponent
                dest = dir.appendingPathComponent("\(stem) (\(n)).\(url.pathExtension)")
                n += 1
            }
            do {
                try fm.copyItem(at: url, to: dest)
                staged.append(dest)
            } catch {
                print("Staging failed for \(url.lastPathComponent): \(error)")
            }
        }
        return staged
    }

    func discardStaged(_ urls: [URL]) {
        let folders = Set(urls.map { $0.deletingLastPathComponent() })
        for folder in folders { try? FileManager.default.removeItem(at: folder) }
    }

    /// Imports staged files, either as one book (each file = a chapter) or one book per file.
    /// With `announce` off, no message is shown; the caller reports the returned books.
    @discardableResult
    func importStaged(_ urls: [URL], asSingleBook: Bool, announce: Bool = true) async -> [Book] {
        guard !urls.isEmpty else { return [] }
        isImporting = true
        defer { isImporting = false }

        let sorted = urls.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
        let groups: [[URL]] = asSingleBook ? [sorted] : sorted.map { [$0] }

        var imported: [Book] = []
        for group in groups {
            if let book = await buildBook(from: group) {
                books.append(book)
                imported.append(book)
            }
        }
        save()
        discardStaged(urls)
        ChapterScanner.shared.enqueue(imported)
        MetadataEnricher.shared.enqueue(imported)
        guard announce else { return imported }

        if imported.isEmpty {
            importMessage = "Those files couldn't be read as audio."
        } else if imported.count == 1, let book = imported.first {
            switch book.chapterSource {
            case .embedded:
                importMessage = "Imported “\(TitleCleaner.clean(book.title))”. Found \(book.chapters.count) chapters in the file."
            case .perFile:
                importMessage = "Imported “\(TitleCleaner.clean(book.title))” with \(book.chapters.count) chapters (one per file)."
            case .none, .detected, .interval:
                if book.duration >= 2 * ChapterDetector.minimumGap {
                    importMessage = "Imported “\(TitleCleaner.clean(book.title))”. It has no chapter markers, so I'm listening for chapter announcements. Keep the app open; you'll see the progress on the book's card."
                } else {
                    importMessage = "Imported “\(TitleCleaner.clean(book.title))”."
                }
            }
        } else {
            let chaptered = imported.filter { $0.chapterSource == .embedded }.count
            importMessage = "Imported \(imported.count) books. \(chaptered) of them have chapter markers."
        }
        return imported
    }

    /// The file names and sizes of every book, to recognise the same audio arriving again.
    func fileSignatures() -> Set<String> {
        Set(books.map { book in
            FolderSync.signature(book.files.map { fileURL(for: book, file: $0) })
        })
    }

    /// Handles a file opened in this app from Files / share sheet.
    func importOpenedFile(_ url: URL) async {
        isImporting = true
        let staged = await Task.detached { LibraryStore.stage([url]) }.value
        isImporting = false
        await importStaged(staged, asSingleBook: true)
    }

    private func buildBook(from urls: [URL]) async -> Book? {
        let fm = FileManager.default
        let folderName = UUID().uuidString
        let folder = booksURL.appendingPathComponent(folderName, isDirectory: true)
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        var analyses: [(name: String, info: BookAnalyzer.FileAnalysis)] = []
        for url in urls {
            let dest = folder.appendingPathComponent(url.lastPathComponent)
            do { try fm.moveItem(at: url, to: dest) } catch { continue }
            let info = await BookAnalyzer.analyze(url: dest)
            guard info.duration > 0 else {
                try? fm.removeItem(at: dest)
                continue
            }
            analyses.append((url.lastPathComponent, info))
        }

        guard !analyses.isEmpty else {
            try? fm.removeItem(at: folder)
            return nil
        }

        let assembled = BookAnalyzer.assemble(analyses)
        var book = Book(title: assembled.title,
                        author: assembled.author,
                        folderName: folderName,
                        files: assembled.files,
                        chapters: assembled.chapters,
                        chapterSource: assembled.source,
                        duration: assembled.duration)

        if let artwork = assembled.artwork,
           let image = UIImage(data: artwork),
           let jpeg = ImageUtils.jpegData(image, maxDimension: 1000) {
            do {
                try jpeg.write(to: folder.appendingPathComponent("cover.jpg"), options: .atomic)
                book.hasCover = true
                book.coverOrigin = "file"
            } catch {}
        }
        return book
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: indexURL) else { return }
        do {
            books = try JSONDecoder().decode([Book].self, from: data)
        } catch {
            print("Could not read library: \(error)")
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(books)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            print("Could not save library: \(error)")
        }
    }
}

enum AudioTypes {
    static var importable: [UTType] {
        var types: [UTType] = [.audio, .mp3, .mpeg4Audio, .mpeg4Movie]
        for ext in ["m4b", "m4a", "aac"] {
            if let type = UTType(filenameExtension: ext), !types.contains(type) {
                types.append(type)
            }
        }
        return types
    }
}
