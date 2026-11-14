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

    var summary: String {
        switch self {
        case .embedded: return "Chapter markers detected in the file"
        case .perFile: return "One chapter per imported file"
        case .none: return "No chapter markers found in this file"
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
