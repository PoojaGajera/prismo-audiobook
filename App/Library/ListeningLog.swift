import Foundation

/// One stretch of listening to one book (pauses under 90 s don't split it).
struct ListeningSession: Codable, Hashable, Identifiable {
    var id = UUID()
    var bookID: UUID
    /// Copied when the session starts, so stats survive the book being deleted.
    var title: String
    var genre: String?
    var start: Date
    var end: Date
    /// Real time spent listening, in seconds.
    var seconds: Double
    /// Book time covered (real time × speed).
    var bookSeconds: Double
    /// Chapters played through to their end during this session.
    var chapters: Int = 0
}

/// Everything the Activity page knows about listening: a list of sessions recorded by the player,
/// plus an estimate of what was listened to before tracking began (so levels don't start at zero).
/// Saved as JSON at `Application Support/Activity/listening.json`.
///
/// The player calls `record` on every time-observer tick. To keep the Activity page from redrawing
/// twice a second, the session being recorded is only published every 30 s, on pause and on
/// leaving the app (`save()`).
@MainActor
final class ListeningLog: ObservableObject {
    static let shared = ListeningLog()

    @Published private(set) var sessions: [ListeningSession] = []
    /// Listening before tracking began, estimated once from every book's progress.
    @Published private(set) var baselineSeconds: Double = 0
    @Published private(set) var trackingSince = Date()
    /// Challenges completed, as "<period key>.<challenge id>" (e.g. "2026-W47.nightOwl").
    @Published private(set) var earnedChallenges: Set<String> = []

    /// The session being recorded right now (published into `sessions` on each flush).
    private var live: ListeningSession?
    private var lastFlush = Date.distantPast
    private var dirty = false

    private struct Stored: Codable {
        var sessions: [ListeningSession]
        var baselineSeconds: Double
        var trackingSince: Date
        var earnedChallenges: [String]
    }

    private init() {
        load()
    }

    // MARK: - Recording

    /// Adds `seconds` of real listening to `book` (called by the player while it plays).
    func record(book: Book, seconds: Double, speed: Double, at now: Date = Date()) {
        // Ticks come every half second or so; anything long is a gap (paused, seek, suspended).
        guard seconds > 0, seconds < 5 else { return }
        if var session = live,
           session.bookID == book.id,
           now.timeIntervalSince(session.end) < 90,
           Calendar.current.isDate(session.start, inSameDayAs: now) {
            session.end = now
            session.seconds += seconds
            session.bookSeconds += seconds * speed
            live = session
        } else {
            flush()
            live = ListeningSession(bookID: book.id, title: book.title, genre: book.genre,
                                    start: now.addingTimeInterval(-seconds), end: now,
                                    seconds: seconds, bookSeconds: seconds * speed)
        }
        dirty = true
        if now.timeIntervalSince(lastFlush) > 30 { save() }
    }

    /// A chapter of `book` was played through to its end.
    func chapterFinished(book: Book) {
        guard var session = live, session.bookID == book.id else { return }
        session.chapters += 1
        live = session
        dirty = true
    }

    /// Publishes the live session and writes everything to disk (if anything changed).
    func save() {
        flush()
        guard dirty else { return }
        dirty = false
        let stored = Stored(sessions: sessions, baselineSeconds: baselineSeconds,
                            trackingSince: trackingSince, earnedChallenges: Array(earnedChallenges).sorted())
        do {
            try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            try JSONEncoder().encode(stored).write(to: Self.fileURL, options: .atomic)
        } catch {
            print("Could not save listening log: \(error)")
        }
    }

    /// Remembers newly completed challenges (the Activity page calls this when it sees them).
    func markEarned(_ keys: [String]) {
        let new = Set(keys).subtracting(earnedChallenges)
        guard !new.isEmpty else { return }
        earnedChallenges.formUnion(new)
        dirty = true
        save()
    }

    private func flush() {
        lastFlush = Date()
        guard let live else { return }
        if let index = sessions.lastIndex(where: { $0.id == live.id }) {
            if sessions[index] != live { sessions[index] = live }
        } else {
            sessions.append(live)
        }
    }

    // MARK: - Disk

    private static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Activity", isDirectory: true)
    }

    private static var fileURL: URL { folder.appendingPathComponent("listening.json") }

    private func load() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            sessions = stored.sessions
            baselineSeconds = stored.baselineSeconds
            trackingSince = stored.trackingSince
            earnedChallenges = Set(stored.earnedChallenges)
            return
        }
        // First run: estimate earlier listening from how far into each book the listener got.
        baselineSeconds = LibraryStore.shared.books.reduce(0) { total, book in
            let heard = book.isFinished ? book.duration : book.position
            return total + heard / max(0.5, book.speed ?? 1)
        }
        trackingSince = Date()
        dirty = true
        save()
    }
}
