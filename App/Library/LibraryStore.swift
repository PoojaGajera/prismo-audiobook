import Foundation
import UIKit
import UniformTypeIdentifiers

/// Owns the list of books and the audio files on disk.
@MainActor
final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()

    @Published private(set) var books: [Book] = []
    @Published var isImporting = false
    @Published var importMessage: String?

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
    func importStaged(_ urls: [URL], asSingleBook: Bool) async {
        guard !urls.isEmpty else { return }
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

        if imported.isEmpty {
            importMessage = "Those files couldn't be read as audio."
        } else if imported.count == 1, let book = imported.first {
            switch book.chapterSource {
            case .embedded:
                importMessage = "Imported “\(book.title)”. Found \(book.chapters.count) chapters in the file."
            case .perFile:
                importMessage = "Imported “\(book.title)” with \(book.chapters.count) chapters (one per file)."
            case .none:
                importMessage = "Imported “\(book.title)”. This file has no chapter markers."
            }
        } else {
            let chaptered = imported.filter { $0.chapterSource == .embedded }.count
            importMessage = "Imported \(imported.count) books. \(chaptered) of them have chapter markers."
        }
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
