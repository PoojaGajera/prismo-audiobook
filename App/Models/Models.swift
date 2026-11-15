import Foundation

/// One audio file belonging to a book. `start` is where the file begins on the book's timeline.
struct BookFile: Codable, Hashable {
    var fileName: String
    var start: Double
    var duration: Double
}

/// A chapter on the book's global timeline (seconds from the start of the book).
struct Chapter: Codable, Hashable {
    var title: String
    var start: Double
    var duration: Double
    var end: Double { start + duration }
}

struct Bookmark: Codable, Hashable, Identifiable {
    var id = UUID()
    var time: Double
    var note: String
    var chapterTitle: String
    var createdAt = Date()
}

/// How the chapter list was obtained.
enum ChapterSource: String, Codable {
    case embedded   // chapter markers inside the file (M4B chapters, ID3 CHAP frames)
    case perFile    // several files imported as one book: one chapter per file
    case none       // a single file without chapter markers
    case detected   // found by Find Chapters (pauses / spoken titles)
    case interval   // split evenly by Find Chapters

    var summary: String {
        switch self {
        case .embedded: return "Chapter markers found in the file"
        case .perFile: return "One chapter per imported file"
        case .none: return "No chapter markers in this file"
        case .detected: return "Chapters found automatically"
        case .interval: return "Split into equal parts"
        }
    }
}

struct Book: Codable, Hashable, Identifiable {
    var id = UUID()
    var title: String
    var author: String
    var folderName: String
    var files: [BookFile]
    var chapters: [Chapter]
    var chapterSource: ChapterSource
    var duration: Double
    var position: Double = 0
    var speed: Double?
    var bookmarks: [Bookmark] = []
    var addedAt = Date()
    var lastPlayed: Date?
    var isFinished = false
    var hasCover = false
    /// The chapters from before Find Chapters was used, so they can be restored.
    var originalChapters: [Chapter]?
    var originalChapterSource: ChapterSource?

    // Details, filled from the file's tags, an online lookup, or by hand (Edit Details).
    var series: String?
    var genre: String?
    var year: String?
    var publisher: String?
    var summary: String?
    /// Bumped whenever cover.jpg is replaced, so cached images refresh.
    var coverVersion: Int?
    /// True once the online lookup ran (or the details were edited by hand), so it isn't repeated.
    var detailsChecked: Bool?
    /// True once the details were saved in Edit Details: the automatic lookup never touches them again.
    var detailsEdited: Bool?
    /// Where cover.jpg came from: "file" (embedded art), "publisher" (looked up) or "user" (chosen).
    var coverOrigin: String?
    /// True once a publisher cover was looked for, found or not.
    var publisherCoverChecked: Bool?
    /// `MetadataEnricher.lookupVersion` of the last lookup.
    var lookupVersion: Int?

    var hasKnownAuthor: Bool {
        let a = author.trimmingCharacters(in: .whitespaces)
        return !a.isEmpty && a.lowercased() != "unknown author"
    }

    /// Copies the descriptive fields (not progress, files or chapters) from `other`.
    func withDetails(from other: Book) -> Book {
        var b = self
        b.title = other.title
        b.author = other.author
        b.series = other.series
        b.genre = other.genre
        b.year = other.year
        b.publisher = other.publisher
        b.summary = other.summary
        b.hasCover = other.hasCover
        b.coverVersion = other.coverVersion
        b.detailsChecked = other.detailsChecked
        b.detailsEdited = other.detailsEdited
        b.coverOrigin = other.coverOrigin
        b.publisherCoverChecked = other.publisherCoverChecked
        b.lookupVersion = other.lookupVersion
        return b
    }

    var progress: Double { duration > 0 ? min(1, max(0, position / duration)) : 0 }
    var remaining: Double { max(0, duration - position) }

    /// Which file contains `time`, and the offset inside that file.
    func location(for time: Double) -> (track: Int, local: Double) {
        guard !files.isEmpty else { return (0, 0) }
        var index = 0
        for (i, file) in files.enumerated() where file.start <= time {
            index = i
        }
        return (index, max(0, time - files[index].start))
    }

    func chapterIndex(at time: Double) -> Int {
        guard !chapters.isEmpty else { return 0 }
        var index = 0
        for (i, chapter) in chapters.enumerated() where chapter.start <= time + 0.05 {
            index = i
        }
        return index
    }
}
