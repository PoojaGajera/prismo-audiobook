import Foundation
import UIKit

/// Fills in a book's details: cleans the title, then looks the book up (Apple Books in the
/// default store, Open Library as a fallback) to add the author if missing, a cover if there
/// is none, and genre, year, publisher, series and description. Covers are always the
/// publisher's (ebook or print edition), never audiobook art with "Narrated by …".
///
/// Automatically, each book is looked up once (`Book.detailsChecked`): after any import (+,
/// Files, share sheet, the watched folder) and, for books missed while offline, when the app
/// opens. `refreshAll()` (the Sync button) re-checks every book and updates what changed.
/// Details saved in Edit Details are never touched.
@MainActor
final class MetadataEnricher: ObservableObject {
    static let shared = MetadataEnricher()

    /// The book being looked up right now.
    @Published private(set) var current: UUID?
    /// True while the Sync button's full refresh runs.
    @Published private(set) var isRefreshing = false

    enum Outcome { case updated, unchanged, failed, skipped }

    /// Bumped when lookups improve, so books looked up before get one more automatic pass.
    /// 2: the description came from the ebook listing instead of the audiobook's.
    /// 3: the description is the physical book's (Open Library), like on Goodreads.
    /// 4: Open Library source footnotes removed from descriptions.
    static let lookupVersion = 4

    private var queue: [UUID] = []
    private var running = false

    private init() {}

    func enqueue(_ books: [Book]) {
        for book in books where Self.needsLookup(book) && !queue.contains(book.id) && current != book.id {
            queue.append(book.id)
        }
        guard !running, !queue.isEmpty else { return }
        running = true
        Task {
            while !queue.isEmpty {
                let id = queue.removeFirst()
                current = id
                _ = await enrich(id, force: false)
                current = nil
            }
            running = false
        }
    }

    /// Re-checks every book (except ones edited by hand) and updates its details.
    /// Returns how many changed, and how many couldn't be checked (offline or rate-limited).
    func refreshAll() async -> (checked: Int, updated: Int, failed: Int) {
        guard !isRefreshing else { return (0, 0, 0) }
        isRefreshing = true
        defer { isRefreshing = false }

        var checked = 0, updated = 0, failed = 0
        for book in LibraryStore.shared.books where book.detailsEdited != true {
            switch await enrich(book.id, force: true) {
            case .updated: updated += 1; checked += 1
            case .unchanged: checked += 1
            case .failed: failed += 1
            case .skipped: break
            }
            // Apple's search allows about 20 requests a minute; stay well under it.
            try? await Task.sleep(for: .milliseconds(700))
        }
        return (checked, updated, failed)
    }

    /// Not looked up yet, or looked up but the title still carries extras like "[Opus 5.1ch Encode]"
    /// (e.g. from before the cleaner knew them). Books edited by hand are left alone.
    static func needsLookup(_ book: Book) -> Bool {
        if book.detailsEdited == true { return false }
        if book.detailsChecked != true { return true }
        // Covers added before publisher covers were used may be audiobook art ("Narrated by …").
        if book.publisherCoverChecked != true && book.coverOrigin != "user" { return true }
        if (book.lookupVersion ?? 0) < lookupVersion { return true }
        let author = book.hasKnownAuthor ? book.author : nil
        return TitleCleaner.clean(book.title, author: author) != book.title
    }

    /// `force` (Sync) re-checks a book that was already looked up, and lets a confident
    /// match replace genre, year, publisher, series and description. Without it, only gaps are filled.
    private func enrich(_ id: UUID, force: Bool) async -> Outcome {
        let library = LibraryStore.shared
        guard let book = library.book(id: id), book.detailsEdited != true,
              force || Self.needsLookup(book) else { return .skipped }

        let knownAuthor = book.hasKnownAuthor ? book.author : nil
        let cleaned = TitleCleaner.splitSeries(TitleCleaner.clean(book.title, author: knownAuthor))
        // Search without any bracketed part, so leftover extras can't stop the store finding the book.
        let core = TitleCleaner.searchCore(cleaned.title)
        let region = CoverRegion(rawValue: AppSettings.shared.coverRegion) ?? .standard
        let query = [core, knownAuthor].compactMap { $0 }.joined(separator: " ")

        guard let appleResults = await MetadataLookup.searchApple(query, region: region) else { return .failed } // offline: retry later
        var match = MetadataLookup.bestMatch(in: appleResults, title: core, author: knownAuthor)
        // Open Library lists many obscure books with the same titles, so only trust it
        // when the author is known too.
        if match == nil, knownAuthor != nil, let openLibrary = await MetadataLookup.searchOpenLibrary(query) {
            match = MetadataLookup.bestMatch(in: openLibrary, title: core, author: knownAuthor)
        }

        // The publisher's edition (ebook, else print): its description is about the book, and
        // its cover is the publisher's artwork. The cover replaces one from the file or an
        // earlier lookup, but never one you chose.
        let edition = await MetadataLookup.publisherEdition(title: match?.title ?? core,
                                                            author: knownAuthor ?? match?.author, region: region)
        var cover: UIImage?
        if book.coverOrigin != "user", book.coverOrigin != "publisher", let url = edition?.coverURL {
            cover = await MetadataLookup.downloadImage(url)
        }
        // The physical book's description (as on Goodreads), else the store text without
        // narration or ebook lines.
        let bookSummary = await MetadataLookup.bookDescription(title: match?.title ?? core,
                                                               author: knownAuthor ?? match?.author,
                                                               fallback: edition?.summary ?? match?.summary)
        // Descriptions from older lookups came from the audiobook listing: replace them once.
        let replaceSummary = force || (book.lookupVersion ?? 0) < Self.lookupVersion

        // Re-read: the book may have been edited or deleted while we were waiting.
        guard var updated = library.book(id: id), updated.detailsEdited != true else { return .skipped }
        let before = Self.details(updated)

        updated.title = match?.title ?? cleaned.title
        if !updated.hasKnownAuthor, let author = match?.author { updated.author = author }
        if force, let match {
            updated.series = match.series ?? updated.series ?? cleaned.series
            updated.genre = match.genre ?? updated.genre
            updated.year = match.year ?? updated.year
            updated.publisher = match.publisher ?? updated.publisher
            updated.summary = bookSummary ?? updated.summary
        } else {
            updated.series = updated.series ?? match?.series ?? cleaned.series
            updated.genre = updated.genre ?? match?.genre
            updated.year = updated.year ?? match?.year
            updated.publisher = updated.publisher ?? match?.publisher
            updated.summary = replaceSummary ? (bookSummary ?? updated.summary) : (updated.summary ?? bookSummary)
        }
        if let cover, updated.coverOrigin != "user", library.writeCover(cover, for: updated) {
            updated.hasCover = true
            updated.coverVersion = (updated.coverVersion ?? 0) + 1
            updated.coverOrigin = "publisher"
        }
        updated.detailsChecked = true
        updated.publisherCoverChecked = true
        updated.lookupVersion = Self.lookupVersion
        let changed = Self.details(updated) != before
        library.saveDetails(updated)
        return changed ? .updated : .unchanged
    }

    private static func details(_ b: Book) -> [String?] {
        [b.title, b.author, b.series, b.genre, b.year, b.publisher, b.summary, b.hasCover ? "cover\(b.coverVersion ?? 0)" : nil]
    }
}
