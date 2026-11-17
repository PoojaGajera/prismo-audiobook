import Foundation

/// Runs Find Chapters in the background, one book at a time: automatically on newly imported
/// books that have no chapter markers, and on any book the user asks for (Find Chapters in the
/// chapter list or the book's long-press menu). Nothing here depends on the player, so the
/// player can be closed, or another book played, while a book is scanned. The library cards and
/// the chapter list show progress.
@MainActor
final class ChapterScanner: ObservableObject {
    static let shared = ChapterScanner()

    /// Every book that is queued or being scanned. The value is the scan progress (0…1).
    @Published private(set) var progress: [UUID: Double] = [:]
    /// The book being scanned right now; the others in `progress` are waiting.
    @Published private(set) var current: UUID?

    /// When the current scan started (this run), and how far it had got then.
    private var runStart: (date: Date, fraction: Double)?
    /// Time spent listening to each book, over all its runs (shown when it's done).
    private var timeSpent: [UUID: TimeInterval] = [:]

    /// Chapters found so far by the scan in progress (0 until a believable run is heard).
    @Published private(set) var foundSoFar: [UUID: Int] = [:]

    /// The result of the last scan the user asked for, per book (shown in the chapter list).
    @Published private(set) var lastOutcome: [UUID: String] = [:]

    /// Scans that stopped part way (you tapped Stop, it failed, or the app was closed) and can
    /// carry on from where they got to. The value is how far they got (0…1). Kept on disk.
    @Published private(set) var paused: [UUID: Double] = [:]
    private var checkpoints: [UUID: ChapterDetector.Checkpoint] = [:]
    private var lastCheckpointWrite = Date.distantPast
    private static var checkpointsURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ChapterScanCheckpoints.json")
    }

    private var queue: [UUID] = []
    /// Books the user asked for: scanned even if they already have chapters, and ahead of the
    /// automatic queue.
    private var requested: Set<UUID> = []
    private var task: Task<Void, Never>?

    private init() {
        if let data = try? Data(contentsOf: Self.checkpointsURL),
           let saved = try? JSONDecoder().decode([UUID: ChapterDetector.Checkpoint].self, from: data) {
            checkpoints = saved
        }
        refreshPaused()
    }

    /// A stopped scan of this book can be resumed.
    func canResume(_ id: UUID) -> Bool { progress[id] == nil && checkpoints[id] != nil }

    /// Carries on with this book's stopped scan from where it got to.
    func resume(_ book: Book) {
        guard checkpoints[book.id] != nil else { return find(book) }
        checkpoints[book.id]?.stoppedBecause = nil
        start(book, fresh: false)
    }

    /// Scans that were running when the app was closed carry on by themselves (call at launch).
    /// Ones you stopped, or that failed, wait for you to tap Resume.
    /// Gives each name in found chapter titles one spelling (see `ChapterNameSpeller`).
    private static func spellNames(_ chapters: [Chapter], of id: UUID) -> [Chapter] {
        let player = PlayerController.shared
        guard let book = (player.book?.id == id ? player.book : LibraryStore.shared.book(id: id)) else { return chapters }
        return ChapterNameSpeller.unify(chapters, book: book)
    }

    /// Fixes names spelled several ways in chapters found before `ChapterNameSpeller` existed
    /// (or found while a book's details were missing). Cheap; run at launch.
    func tidyChapterNames() {
        let player = PlayerController.shared
        for book in LibraryStore.shared.books where book.chapterSource == .detected {
            let current = player.book?.id == book.id ? (player.book ?? book) : book
            let tidied = ChapterNameSpeller.unify(current.chapters, book: current)
            guard tidied != current.chapters else { continue }
            if player.book?.id == book.id {
                player.replaceChapters(tidied, source: .detected)
            } else {
                _ = LibraryStore.shared.replaceChapters(of: book.id, with: tidied, source: .detected, onlyIfUnchaptered: false)
            }
        }
    }

    func resumeInterrupted() {
        let library = LibraryStore.shared
        for (id, checkpoint) in checkpoints where checkpoint.stoppedBecause == nil && progress[id] == nil {
            if let book = library.book(id: id), book.hasAudio {
                start(book, fresh: false, front: false)
            } else {
                forget(id)
            }
        }
    }

    /// Drops everything about a book's scans (it was deleted).
    func forget(_ id: UUID) {
        cancel(id)
        lastOutcome[id] = nil
        checkpoints[id] = nil
        writeCheckpoints()
        refreshPaused()
    }

    func isScanning(_ id: UUID) -> Bool { progress[id] != nil }

    /// A book is being scanned or waiting to be.
    var isBusy: Bool { current != nil || !queue.isEmpty }

    /// Stops everything: the current scan and the queue (when iOS ends the background task, or
    /// you stop it from the system's progress UI). Books can be scanned again later.
    func stopAll() {
        for id in queue { progress[id] = nil }
        queue.removeAll()
        requested.removeAll()
        task?.cancel()
    }

    /// Finds chapters in this book now (well, next), from the beginning: the user asked, so it
    /// goes ahead of the automatic scans and runs even if the book already has chapters.
    func find(_ book: Book) {
        start(book, fresh: true)
    }

    private func start(_ book: Book, fresh: Bool, front: Bool = true) {
        guard book.hasAudio else { return }
        lastOutcome[book.id] = nil
        if fresh, checkpoints[book.id] != nil {
            checkpoints[book.id] = nil
            writeCheckpoints()
        }
        refreshPaused()
        requested.insert(book.id)
        guard progress[book.id] == nil else {
            // Already waiting in the automatic queue: move it to the front.
            if current != book.id, let i = queue.firstIndex(of: book.id) {
                queue.remove(at: i)
                queue.insert(book.id, at: 0)
            }
            return
        }
        if front { queue.insert(book.id, at: 0) } else { queue.append(book.id) }
        progress[book.id] = checkpoints[book.id].map { $0.position / max(book.duration, 1) } ?? 0
        paused[book.id] = nil
        runNext()
    }

    /// Queues the books that have no chapters of their own. Books too short to hold two
    /// chapters (announcements must be at least `minimumGap` apart) are skipped.
    func enqueue(_ books: [Book]) {
        for book in books where book.hasAudio && book.chapterSource == .none && progress[book.id] == nil
            && book.duration >= 2 * ChapterDetector.minimumGap {
            queue.append(book.id)
            progress[book.id] = 0
        }
        runNext()
    }

    /// Stops scanning a book (because the user tapped Stop, or it's being deleted). How far it
    /// got is kept, so it can be resumed.
    func cancel(_ id: UUID) {
        queue.removeAll { $0 == id }
        requested.remove(id)
        if current == id {
            task?.cancel()
        } else {
            progress[id] = nil
        }
    }

    private func runNext() {
        guard task == nil else { return }
        guard !queue.isEmpty else {
            // All done: let iOS stop keeping the app running for us.
            ChapterScanBackground.shared.scanningFinished()
            return
        }
        let id = queue.removeFirst()
        let library = LibraryStore.shared
        guard let book = library.book(id: id), book.chapterSource == .none || requested.contains(id) else {
            progress[id] = nil
            runNext()
            return
        }

        let sources = book.files.map {
            ChapterDetector.Source(url: library.fileURL(for: book, file: $0), start: $0.start, duration: $0.duration)
        }
        let total = book.duration
        let resumeFrom = checkpoints[id]
        current = id
        // Timed from here, so the total shown at the end covers the whole search.
        runStart = (Date(), 0)
        // Keeps going if you leave the app.
        ChapterScanBackground.shared.scanStarted(title: book.title)

        // Low priority, so it gives way to everything else (and runs on the efficiency cores).
        task = Task(priority: .utility) {
            do {
                let result = try await ChapterDetector.detect(
                    sources: sources, totalDuration: total, resume: resumeFrom,
                    save: { checkpoint in
                        Task { @MainActor in ChapterScanner.shared.saveCheckpoint(id, checkpoint) }
                    }
                ) { _, fraction in
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
        let clamped = min(1, max(0, fraction))
        // Finer than the cards show: iOS stops a background task that reports no progress for
        // about 30 seconds.
        ChapterScanBackground.shared.progressed(clamped)
        let rounded = (clamped * 100).rounded() / 100
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
        let reached = progress[id] ?? 0
        progress[id] = nil
        foundSoFar[id] = nil
        if let start = runStart { timeSpent[id, default: 0] += Date().timeIntervalSince(start.date) }
        runStart = nil
        let took = timeSpent[id].map { " in \(TimeFormat.short($0))" } ?? ""
        switch outcome {
        case .found:
            checkpoints[id] = nil
        case .failed, .cancelled:
            // Stop means stop, and a failed search isn't offered for resuming: the next Find
            // Chapters starts from the beginning. (Only a search cut short by the app closing
            // carries on by itself, see `resumeInterrupted`.)
            _ = reached
            checkpoints[id] = nil
        }
        if LibraryStore.shared.book(id: id) == nil { checkpoints[id] = nil }   // deleted meanwhile
        writeCheckpoints()
        refreshPaused()
        let asked = requested.remove(id) != nil
        if LibraryStore.shared.book(id: id) != nil {
            // Quiet either way (no alerts): the chapters just appear. For a scan the user asked
            // for, the chapter list also says how it went.
            switch outcome {
            case .found(let chapters) where chapters.count >= 2:
                if apply(chapters, to: id, replacingExisting: asked), asked {
                    lastOutcome[id] = "Found \(chapters.count) chapters\(took)."
                }
            case .found:
                if asked {
                    let spent = timeSpent[id].map { "Listened for \(TimeFormat.short($0)), but didn't" } ?? "Didn't"
                    lastOutcome[id] = "\(spent) hear the narrator announce any chapters."
                }
            case .failed(let message):
                if asked { lastOutcome[id] = "Couldn't look for chapters. \(message)" }
            case .cancelled:
                break
            }
        }
        // Kept across stops and resumes, so the final time covers the whole search.
        if case .found = outcome { timeSpent[id] = nil }
        runNext()
    }

    /// Uses the found chapters, unless the book got chapters some other way in the meantime.
    /// Returns false when the book already had chapters, so nothing was changed.
    /// With `replacingExisting` (the user asked), existing chapters are replaced; the originals are
    /// kept, so Restore Original Chapters can bring them back.
    @discardableResult
    private func apply(_ found: [Chapter], to id: UUID, replacingExisting: Bool) -> Bool {
        let player = PlayerController.shared
        let chapters = Self.spellNames(found, of: id)
        if let loaded = player.book, loaded.id == id {
            guard replacingExisting || loaded.chapterSource == .none else { return false }
            player.replaceChapters(chapters, source: .detected)
            return true
        }
        return LibraryStore.shared.replaceChapters(of: id, with: chapters, source: .detected,
                                                   onlyIfUnchaptered: !replacingExisting)
    }

    // MARK: - Checkpoints

    /// How far the current scan has got, kept in memory at once and on disk every few seconds
    /// (so a scan can carry on after the app is closed).
    private func saveCheckpoint(_ id: UUID, _ checkpoint: ChapterDetector.Checkpoint) {
        guard current == id else { return }
        let countChanged = checkpoint.mentions.count != checkpoints[id]?.mentions.count
        checkpoints[id] = checkpoint
        if countChanged {
            let found = ChapterDetector.chaptersSoFar(checkpoint.mentions)
            if foundSoFar[id] != found { foundSoFar[id] = found }
        }
        if Date().timeIntervalSince(lastCheckpointWrite) > 10 { writeCheckpoints() }
    }

    private func writeCheckpoints() {
        lastCheckpointWrite = Date()
        let snapshot = checkpoints
        let url = Self.checkpointsURL
        Task.detached(priority: .utility) {
            if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: url, options: .atomic) }
        }
    }

    private func refreshPaused() {
        let library = LibraryStore.shared
        var result: [UUID: Double] = [:]
        for (id, checkpoint) in checkpoints where progress[id] == nil {
            guard let book = library.book(id: id) else { continue }
            result[id] = min(0.99, checkpoint.position / max(book.duration, 1))
        }
        if result != paused { paused = result }
    }

    // MARK: - Scanning one chapter

    /// A chapter being listened to for a missed chapter inside it.
    struct ChapterScan: Equatable {
        var bookID: UUID
        var index: Int
        var progress: Double
    }

    /// How a one-chapter scan went, for the chapter list to show.
    struct ChapterScanOutcome: Identifiable {
        let id = UUID()
        var bookID: UUID
        var message: String
        /// Nothing found: offer to scan the whole book instead.
        var offerWholeBook: Bool
    }

    @Published private(set) var chapterScan: ChapterScan?
    @Published var chapterScanOutcome: ChapterScanOutcome?
    private var chapterTask: Task<Void, Never>?

    /// Listens to all of chapter `index` for a chapter the full search missed (Chapter 1 followed
    /// by Chapter 3: is "Two" in Chapter 1?). If it's found, the chapter is split there.
    func scanChapter(_ book: Book, index: Int) {
        let expected = ChapterDetector.rescanNumbers(in: book.chapters, at: index)
        guard !expected.isEmpty, chapterScan == nil, book.chapters.indices.contains(index) else { return }
        guard progress[book.id] == nil else {
            chapterScanOutcome = ChapterScanOutcome(bookID: book.id,
                message: "Chapters are already being found in this book. Try again when that's done.",
                offerWholeBook: false)
            return
        }
        let library = LibraryStore.shared
        let chapter = book.chapters[index]
        let sources = book.files.map {
            ChapterDetector.Source(url: library.fileURL(for: book, file: $0), start: $0.start, duration: $0.duration)
        }
        let names = expected.map { "Chapter \($0)" }.joined(separator: " or ")
        chapterScan = ChapterScan(bookID: book.id, index: index, progress: 0)

        chapterTask = Task(priority: .utility) {
            do {
                let found = try await ChapterDetector.findMissing(
                    expected, from: chapter.start, to: chapter.end, sources: sources, totalDuration: book.duration
                ) { fraction in
                    Task { @MainActor in
                        let shown = (fraction * 100).rounded() / 100
                        if ChapterScanner.shared.chapterScan?.progress != shown {
                            ChapterScanner.shared.chapterScan?.progress = shown
                        }
                    }
                }
                chapterScan = nil
                if found.isEmpty {
                    chapterScanOutcome = ChapterScanOutcome(bookID: book.id,
                        message: "Didn't hear \(names) in \(chapter.title). You can scan the whole book again.",
                        offerWholeBook: true)
                } else {
                    split(book.id, at: index, with: found)
                    let added = found.map { "Chapter \($0.number)" }.joined(separator: " and ")
                    chapterScanOutcome = ChapterScanOutcome(bookID: book.id,
                        message: "Found \(added) and updated the chapters.", offerWholeBook: false)
                }
            } catch is CancellationError {
                chapterScan = nil
            } catch {
                chapterScan = nil
                chapterScanOutcome = ChapterScanOutcome(bookID: book.id,
                    message: "Couldn't scan \(chapter.title). \(error.localizedDescription)", offerWholeBook: true)
            }
        }
    }

    func cancelChapterScan() {
        chapterTask?.cancel()
        chapterTask = nil
        chapterScan = nil
    }

    /// Splits chapter `index` where the missed chapters start.
    private func split(_ id: UUID, at index: Int, with found: [ChapterDetector.Mention]) {
        let player = PlayerController.shared
        guard let book = (player.book?.id == id ? player.book : LibraryStore.shared.book(id: id)),
              book.chapters.indices.contains(index) else { return }
        let old = book.chapters[index]
        var chapters = book.chapters

        // The next chapter itself was heard inside this one: it really starts earlier, so the
        // boundary moves (nothing is added).
        if index + 1 < chapters.count,
           let nextNumber = ChapterDetector.chapterNumber(inTitle: chapters[index + 1].title),
           let early = found.first(where: { $0.number == nextNumber }), early.time > old.start, early.time < old.end {
            let next = chapters[index + 1]
            chapters[index].duration = early.time - old.start
            chapters[index + 1] = Chapter(title: next.title, start: early.time, duration: next.end - early.time)
            applyEdited(chapters, to: id)
            return
        }

        var pieces: [Chapter] = []
        var start = old.start
        var title = old.title
        for mention in found.sorted(by: { $0.time < $1.time }) where mention.time > start && mention.time < old.end {
            pieces.append(Chapter(title: title, start: start, duration: mention.time - start))
            title = mention.name.map { "Chapter \(mention.number): \($0)" } ?? "Chapter \(mention.number)"
            start = mention.time
        }
        pieces.append(Chapter(title: title, start: start, duration: old.end - start))
        chapters.replaceSubrange(index...index, with: pieces)
        applyEdited(chapters, to: id)
    }

    private func applyEdited(_ edited: [Chapter], to id: UUID) {
        let player = PlayerController.shared
        let chapters = Self.spellNames(edited, of: id)
        if player.book?.id == id {
            player.replaceChapters(chapters, source: .detected)
        } else {
            LibraryStore.shared.replaceChapters(of: id, with: chapters, source: .detected, onlyIfUnchaptered: false)
        }
    }
}
