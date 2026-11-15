import Foundation

/// Runs Find Chapters automatically on newly imported books that have no chapter markers.
/// Books are scanned one at a time while the app is open; the library cards show progress.
@MainActor
final class ChapterScanner: ObservableObject {
    static let shared = ChapterScanner()

    /// Every book that is queued or being scanned. The value is the scan progress (0…1).
    @Published private(set) var progress: [UUID: Double] = [:]
    /// The book being scanned right now; the others in `progress` are waiting.
    @Published private(set) var current: UUID?

    private var queue: [UUID] = []
    private var task: Task<Void, Never>?

    private init() {}

    /// Failure reasons already shown this session, so a broken recognizer is reported once,
    /// not once per book.
    private var reportedFailures: Set<String> = []

    /// Queues the books that have no chapters of their own. Books too short to hold two
    /// chapters (announcements must be at least `minimumGap` apart) are skipped.
    func enqueue(_ books: [Book]) {
        for book in books where book.chapterSource == .none && progress[book.id] == nil
            && book.duration >= 2 * ChapterDetector.minimumGap {
            queue.append(book.id)
            progress[book.id] = 0
        }
        runNext()
    }

    /// Stops scanning a book (e.g. because it was deleted).
    func cancel(_ id: UUID) {
        queue.removeAll { $0 == id }
        if current == id {
            task?.cancel()
        } else {
            progress[id] = nil
        }
    }

    private func runNext() {
        guard task == nil, !queue.isEmpty else { return }
        let id = queue.removeFirst()
        let library = LibraryStore.shared
        guard let book = library.book(id: id), book.chapterSource == .none else {
            progress[id] = nil
            runNext()
            return
        }

        let sources = book.files.map {
            ChapterDetector.Source(url: library.fileURL(for: book, file: $0), start: $0.start, duration: $0.duration)
        }
        let total = book.duration
        current = id

        task = Task {
            do {
                let result = try await ChapterDetector.detect(sources: sources, totalDuration: total) { _, fraction in
                    Task { @MainActor in ChapterScanner.shared.report(id, fraction) }
                }
                finish(id, title: book.title, outcome: Task.isCancelled ? .cancelled : .found(result.chapters))
            } catch is CancellationError {
                finish(id, title: book.title, outcome: .cancelled)
            } catch {
                finish(id, title: book.title, outcome: .failed(error.localizedDescription))
            }
        }
    }

    private func report(_ id: UUID, _ fraction: Double) {
        guard current == id else { return }
        let rounded = (min(1, max(0, fraction)) * 100).rounded() / 100
        if progress[id] != rounded { progress[id] = rounded }
    }

    private enum Outcome {
        case found([Chapter])
        case failed(String)
        case cancelled
    }

    private func finish(_ id: UUID, title: String, outcome: Outcome) {
        task = nil
        current = nil
        progress[id] = nil
        let library = LibraryStore.shared
        if library.book(id: id) != nil {
            switch outcome {
            case .found(let chapters) where chapters.count >= 2:
                if apply(chapters, to: id) {
                    library.post("Found \(chapters.count) chapters in “\(title)”.")
                }
            case .found:
                library.post("I listened to “\(title)” but didn't hear the narrator announce any chapters. It stays as one long chapter.")
            case .failed(let message):
                if reportedFailures.insert(message).inserted {
                    library.post("Couldn't look for chapters in “\(title)”. \(message)")
                }
            case .cancelled:
                break
            }
        }
        runNext()
    }

    /// Uses the found chapters, unless the book got chapters some other way in the meantime.
    /// Returns false when the book already had chapters, so nothing was changed.
    @discardableResult
    private func apply(_ chapters: [Chapter], to id: UUID) -> Bool {
        let player = PlayerController.shared
        if let loaded = player.book, loaded.id == id {
            guard loaded.chapterSource == .none else { return false }
            player.replaceChapters(chapters, source: .detected)
            return true
        }
        return LibraryStore.shared.replaceChapters(of: id, with: chapters, source: .detected)
    }
}
