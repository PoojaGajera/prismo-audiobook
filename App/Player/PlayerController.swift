import Foundation
import AVFoundation
import MediaPlayer
import Combine
import UIKit
import WidgetKit

/// The playback engine. One instance for the whole app (also used by widget intents).
@MainActor
final class PlayerController: ObservableObject {
    static let shared = PlayerController()

    @Published private(set) var book: Book? {
        didSet { NowPlayingPresence.shared.update(hasBook: book != nil) }
    }
    @Published private(set) var isPlaying = false
    /// Position on the book's global timeline, in seconds.
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var currentChapterIndex = 0
    @Published private(set) var speed: Double = 1.0
    @Published var volume: Float {
        didSet {
            player.volume = volume
            UserDefaults.standard.set(volume, forKey: "playerVolume")
        }
    }
    @Published var errorMessage: String?

    private let player = AVPlayer()
    private let library = LibraryStore.shared
    private let settings = AppSettings.shared

    private var trackIndex = 0
    private var pendingSeek: Double?
    private var activeSeeks = 0
    private var pausedAt: Date?
    private var wasPlayingBeforeInterruption = false
    private var lastSave = Date.distantPast
    private var lastSnapshot = Date.distantPast
    private var artwork: MPMediaItemArtwork?
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var cancellables = Set<AnyCancellable>()

    private static let lastBookKey = "lastBookID"

    private init() {
        let storedVolume = UserDefaults.standard.object(forKey: "playerVolume") as? Float
        volume = storedVolume ?? 1.0
        player.volume = volume
        player.automaticallyWaitsToMinimizeStalling = false

        configureAudioSession()
        configureRemoteCommands()
        observeNotifications()
        observeSettings()
        addTimeObserver()
        restoreLastBook()
    }

    // MARK: - Derived values

    var chapters: [Chapter] { book?.chapters ?? [] }
    var duration: Double { book?.duration ?? 0 }

    var currentChapter: Chapter? {
        chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex] : nil
    }

    // MARK: - Loading

    func load(_ newBook: Book, autoplay: Bool = true) {
        if book?.id == newBook.id {
            if autoplay { play() }
            return
        }
        if book != nil {
            // Only a book that was playing counts as just played; opening another book
            // mustn't move this one to the top of the library.
            if isPlaying { pause() } else { savePosition(markPlayed: false) }
        }

        let fresh = library.book(id: newBook.id) ?? newBook
        book = fresh
        speed = settings.rememberSpeedPerBook ? (fresh.speed ?? settings.defaultSpeed) : settings.defaultSpeed
        player.defaultRate = Float(speed)
        currentTime = fresh.isFinished ? 0 : fresh.position
        currentChapterIndex = fresh.chapterIndex(at: currentTime)
        pausedAt = fresh.lastPlayed
        errorMessage = nil

        let location = fresh.location(for: currentTime)
        setTrack(location.track, at: location.local)

        UserDefaults.standard.set(fresh.id.uuidString, forKey: Self.lastBookKey)
        loadArtwork()
        updateNowPlaying()
        updateWidget(reload: true)

        if autoplay { play() }
    }

    func unload() {
        if isPlaying { pause() }
        player.replaceCurrentItem(with: nil)
        statusObservation = nil
        book = nil
        currentTime = 0
        currentChapterIndex = 0
        artwork = nil
        UserDefaults.standard.removeObject(forKey: Self.lastBookKey)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        SharedStore.saveCover(nil)
        updateWidget(reload: true)
    }

    private func restoreLastBook() {
        guard let idString = UserDefaults.standard.string(forKey: Self.lastBookKey),
              let id = UUID(uuidString: idString),
              let saved = library.book(id: id), saved.hasAudio else { return }
        load(saved, autoplay: false)
    }

    // MARK: - Transport

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    func setPlaying(_ playing: Bool) {
        playing ? play() : pause()
    }

    /// Starts playing and waits until audio is actually coming out (or `timeout` passes).
    /// For widget / Control Center / Shortcuts taps: when the app wasn't running, iOS launches it
    /// in the background just for the intent and may suspend it as soon as the intent returns.
    /// The book still has to load and seek first, so returning straight after `play()` meant the
    /// app was put to sleep before any sound started. Waiting here keeps it running until then.
    func playAndWait(timeout: Double = 10) async {
        if book == nil { restoreLastBookIfNeeded() }
        play()
        let deadline = Date().addingTimeInterval(timeout)
        while isPlaying, player.timeControlStatus != .playing, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    /// Loads the last book again if nothing is loaded (e.g. a fresh background launch).
    private func restoreLastBookIfNeeded() {
        guard book == nil else { return }
        restoreLastBook()
    }

    // TEMP DEBUG: trace playback state while investigating "play after relaunch" bug.
    private func trace(_ event: String) {
        let item = player.currentItem
        let pending = pendingSeek.map { String(format: "%.1f", $0) } ?? "nil"
        print("[PlayerDebug] \(event) | isPlaying=\(isPlaying) rate=\(player.rate) tcs=\(player.timeControlStatus.rawValue) wait=\(player.reasonForWaitingToPlay?.rawValue ?? "-") item=\(item.map { String($0.status.rawValue) } ?? "nil") pending=\(pending) active=\(activeSeeks) t=\(String(format: "%.1f", currentTime)) track=\(trackIndex) itemTime=\(String(format: "%.1f", item?.currentTime().seconds ?? -1)) err=\(item?.error?.localizedDescription ?? "-") otherAudio=\(AVAudioSession.sharedInstance().isOtherAudioPlaying)")
    }

    func play() {
        guard var current = book else { return }
        trace("play() begin pausedAt=\(pausedAt.map { String(format: "%.0fs ago", Date().timeIntervalSince($0)) } ?? "nil")")
        holdForStartup()

        if current.isFinished || currentTime >= current.duration - 1 {
            current.isFinished = false
            book = current
            library.update(current)
            pausedAt = nil
            seek(to: 0)
        } else if let pausedAt, settings.smartRewindEnabled {
            let rewind = SmartRewind.amount(pausedFor: Date().timeIntervalSince(pausedAt),
                                            limit: settings.smartRewindLimit)
            if rewind > 0 { seek(to: currentTime - rewind) }
        }

        pausedAt = nil
        isPlaying = true
        // Playing a book puts it first in the library straight away.
        current = book ?? current
        current.lastPlayed = Date()
        book = current
        library.update(current)
        player.defaultRate = Float(speed)
        activateAudioSession { [weak self] in
            guard let self, self.isPlaying else { return }
            self.startPlayerIfReady()
        }
        updateNowPlaying()
        updateWidget(reload: true)
        trace("play() end")
    }

    func pause() {
        trace("pause()")
        endStartupHold()
        player.pause()
        guard isPlaying else { return }
        isPlaying = false
        pausedAt = Date()
        savePosition()
        updateNowPlaying()
        updateWidget(reload: true)
    }

    func skip(by seconds: Double) {
        seek(to: currentTime + seconds)
    }

    func skipBackward() { skip(by: -settings.skipBackInterval) }
    func skipForward() { skip(by: settings.skipForwardInterval) }

    func nextChapter() {
        let next = currentChapterIndex + 1
        guard chapters.indices.contains(next) else { return }
        goToChapter(next)
    }

    // MARK: Chapter memory

    /// Where you were in each chapter you left part way through, per book (this session): going
    /// back to that chapter (previous chapter, the chapter list) carries on from there instead of
    /// its start, so an accidental skip loses nothing.
    private var chapterPositions: [UUID: [Int: Double]] = [:]

    /// Before moving away from the current chapter: remember where you were in it, unless you
    /// were at its very beginning or end (then there's nothing to come back to).
    private func rememberChapterPosition(leavingFor target: Double) {
        guard let id = book?.id, let chapter = currentChapter else { return }
        guard target < chapter.start || target >= chapter.end else { return }   // staying in it
        let into = currentTime - chapter.start
        if into > 10, currentTime < chapter.end - 10 {
            chapterPositions[id, default: [:]][currentChapterIndex] = currentTime
        } else {
            chapterPositions[id]?[currentChapterIndex] = nil
        }
    }

    /// Where to go when moving to chapter `index`: where you left it, or its start.
    private func resumePoint(for index: Int) -> Double {
        let chapter = chapters[index]
        if let id = book?.id, let saved = chapterPositions[id]?[index], saved > chapter.start, saved < chapter.end - 5 {
            return saved
        }
        return chapter.start
    }

    /// Goes to the start of this chapter, or the previous one if we're within 3 seconds of the start.
    func previousChapter() {
        guard let chapter = currentChapter else { seek(to: 0); return }
        // Just arrived in this chapter (by previous / next / the chapter list), even if part way
        // through it: pressing back goes on to the chapter before, not to this one's start.
        let justArrived = arrival.map {
            $0.index == currentChapterIndex && Date().timeIntervalSince($0.date) < 6 && abs(currentTime - $0.time) < 5
        } ?? false
        if currentChapterIndex > 0, justArrived || currentTime - chapter.start <= 3 {
            goToChapter(currentChapterIndex - 1)
        } else {
            seek(to: chapter.start)
        }
    }

    /// When and where the last chapter-to-chapter move landed.
    private var arrival: (index: Int, time: Double, date: Date)?

    /// Moves to chapter `index`, where you left it (or its start), and notes the arrival.
    private func goToChapter(_ index: Int) {
        let target = resumePoint(for: index)
        seek(to: target)
        arrival = (index, target, Date())
    }

    func jumpToChapter(_ index: Int) {
        guard chapters.indices.contains(index) else { return }
        if index == currentChapterIndex { seek(to: chapters[index].start) } else { goToChapter(index) }
    }

    func setSpeed(_ newSpeed: Double) {
        let clamped = min(4.0, max(0.5, (newSpeed * 100).rounded() / 100))
        speed = clamped
        player.defaultRate = Float(clamped)
        if isPlaying { player.rate = Float(clamped) }
        if settings.rememberSpeedPerBook, var current = book {
            current.speed = clamped
            book = current
            library.update(current)
        }
        updateNowPlaying()
        updateWidget(reload: true)
    }

    func seek(to time: Double) {
        guard let current = book else { return }
        let target = min(max(0, time), max(0, current.duration - 0.25))
        let location = current.location(for: target)
        rememberChapterPosition(leavingFor: target)
        currentTime = target
        trace("seek(to: \(String(format: "%.1f", target))) track=\(location.track) local=\(String(format: "%.1f", location.local))")

        if location.track != trackIndex || player.currentItem == nil {
            setTrack(location.track, at: location.local)
        } else if player.currentItem?.status == .readyToPlay && pendingSeek == nil {
            performSeek(local: location.local)
        } else {
            pendingSeek = location.local
        }

        updateChapterIndex()
        savePosition()
        updateNowPlaying()
        updateWidget(reload: true)
    }

    // MARK: - Bookmarks

    /// Adds a bookmark and returns it (so a note can be added to it straight after).
    @discardableResult
    func addBookmark(at time: Double? = nil, note: String = "") -> Bookmark? {
        guard var current = book else { return nil }
        let t = time ?? currentTime
        let chapterTitle = current.chapters.isEmpty ? "" : current.chapters[current.chapterIndex(at: t)].title
        let bookmark = Bookmark(time: t, note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                                chapterTitle: chapterTitle)
        current.bookmarks.append(bookmark)
        current.bookmarks.sort { $0.time < $1.time }
        book = current
        library.update(current)
        return bookmark
    }

    func updateBookmark(_ id: UUID, note: String) {
        guard var current = book, let i = current.bookmarks.firstIndex(where: { $0.id == id }) else { return }
        current.bookmarks[i].note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        book = current
        library.update(current)
    }

    func deleteBookmarks(_ ids: [UUID]) {
        guard var current = book else { return }
        current.bookmarks.removeAll { ids.contains($0.id) }
        book = current
        library.update(current)
    }

    // MARK: - Chapters

    /// Replaces the chapter list (e.g. after Find Chapters), remembering the original once.
    func replaceChapters(_ newChapters: [Chapter], source: ChapterSource) {
        guard var current = book, !newChapters.isEmpty else { return }
        if current.originalChapters == nil {
            current.originalChapters = current.chapters
            current.originalChapterSource = current.chapterSource
        }
        current.chapters = newChapters
        current.chapterSource = source
        applyChapterChange(current)
    }

    func restoreOriginalChapters() {
        guard var current = book, let original = current.originalChapters else { return }
        current.chapters = original
        current.chapterSource = current.originalChapterSource ?? ChapterSource.none
        current.originalChapters = nil
        current.originalChapterSource = nil
        applyChapterChange(current)
    }

    private func applyChapterChange(_ updated: Book) {
        book = updated
        library.update(updated)
        currentChapterIndex = updated.chapterIndex(at: currentTime)
        updateNowPlaying()
        updateWidget(reload: true)
    }

    /// Applies edited details (title, author, cover…) to the loaded book, keeping playback state.
    func updateDetails(from edited: Book) {
        guard let current = book, current.id == edited.id else { return }
        let updated = current.withDetails(from: edited)
        book = updated
        library.update(updated)
        loadArtwork()
        updateNowPlaying()
        updateWidget(reload: true)
    }

    /// Renames the loaded book's chapters (same timings), e.g. after its title was tidied.
    func updateChapterTitles(_ chapters: [Chapter]) {
        guard var current = book, current.chapters.count == chapters.count else { return }
        current.chapters = chapters
        book = current
        library.update(current)
        updateNowPlaying()
        updateWidget(reload: true)
    }

    // MARK: - Library helpers for the loaded book

    func resetProgress() {
        guard var current = book else { return }
        current.isFinished = false
        current.position = 0
        book = current
        library.update(current)
        seek(to: 0)
    }

    func setFinished(_ finished: Bool) {
        guard var current = book else { return }
        if isPlaying { pause() }
        current.isFinished = finished
        book = current
        library.update(current)
        if finished { currentTime = current.duration; savePosition() }
    }

    /// Persists the current position (called every few seconds while playing, and on pause/background).
    /// `markPlayed` also updates "last played", which orders the library and drives smart rewind.
    func savePosition(markPlayed: Bool = true) {
        guard var current = book else { return }
        current.position = currentTime
        if markPlayed { current.lastPlayed = Date() }
        book = current
        library.update(current)
        lastSave = Date()
        ListeningLog.shared.save()
    }

    /// When the last time-observer tick ran (Activity measures listening time between ticks).
    private var lastListenTick = Date()

    // MARK: - AVPlayer plumbing

    private func setTrack(_ index: Int, at local: Double) {
        guard let current = book, current.files.indices.contains(index) else { return }
        trackIndex = index
        let url = library.fileURL(for: current, file: current.files[index])
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let item = AVPlayerItem(asset: asset)
        item.audioTimePitchAlgorithm = .timeDomain
        pendingSeek = local > 0.2 ? local : nil
        player.replaceCurrentItem(with: item)
        trace("setTrack(\(index), at: \(String(format: "%.1f", local)))")

        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            let status = item.status
            let message = item.error?.localizedDescription
            Task { @MainActor [weak self] in
                self?.itemStatusChanged(item, status: status, error: message)
            }
        }
    }

    private func itemStatusChanged(_ item: AVPlayerItem, status: AVPlayerItem.Status, error: String?) {
        trace("itemStatusChanged status=\(status.rawValue) isCurrent=\(item === player.currentItem) error=\(error ?? "-")")
        guard item === player.currentItem else { return }
        switch status {
        case .readyToPlay:
            if let target = pendingSeek {
                applyPendingSeek(target)
            } else {
                startPlayerIfReady()
            }
        case .failed:
            errorMessage = error ?? "This file couldn't be played."
            isPlaying = false
            updateWidget(reload: true)
        default:
            break
        }
    }

    /// Seeks to the pending target; if the user seeked again meanwhile, follows up with the newest target.
    private func applyPendingSeek(_ target: Double) {
        trace("applyPendingSeek(\(String(format: "%.1f", target)))")
        performSeek(local: target) { [weak self] in
            guard let self else { return }
            self.trace("applyPendingSeek completion target=\(String(format: "%.1f", target))")
            if let newer = self.pendingSeek, abs(newer - target) > 0.01 {
                self.applyPendingSeek(newer)
            } else {
                self.pendingSeek = nil
                self.startPlayerIfReady()
            }
        }
    }

    private func performSeek(local: Double, completion: (@MainActor () -> Void)? = nil) {
        activeSeeks += 1
        let time = CMTime(seconds: local, preferredTimescale: 1000)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.activeSeeks = max(0, self.activeSeeks - 1)
                self.trace("performSeek completion local=\(String(format: "%.1f", local)) finished=\(finished)")
                completion?()
            }
        }
    }

    private func startPlayerIfReady() {
        guard isPlaying,
              let item = player.currentItem,
              item.status == .readyToPlay,
              pendingSeek == nil else {
            trace("startPlayerIfReady: NOT starting")
            return
        }
        player.playImmediately(atRate: Float(speed))
        trace("startPlayerIfReady: playImmediately called")
    }

    private func addTimeObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                self?.tick(time)
            }
        }
    }

    private func tick(_ time: CMTime) {
        guard let current = book,
              pendingSeek == nil,
              activeSeeks == 0,
              current.files.indices.contains(trackIndex) else { return }
        let local = time.seconds
        guard local.isFinite else { return }

        let previousTime = currentTime
        let previousChapter = currentChapterIndex
        currentTime = min(current.duration, current.files[trackIndex].start + local)
        updateChapterIndex()

        // Activity: real listening time, and chapters played through to their end (not skipped).
        let now = Date()
        if isPlaying, player.timeControlStatus == .playing {
            ListeningLog.shared.record(book: current, seconds: now.timeIntervalSince(lastListenTick),
                                       speed: speed, at: now)
            if currentChapterIndex == previousChapter + 1,
               current.chapters.indices.contains(previousChapter),
               previousTime >= current.chapters[previousChapter].end - 3,
               currentTime - previousTime < 3 {
                ListeningLog.shared.chapterFinished(book: current)
            }
        }
        lastListenTick = now

        if isPlaying {
            if now.timeIntervalSince(lastSave) > 5 { savePosition(); trace("tick") }
            if now.timeIntervalSince(lastSnapshot) > 20 { updateWidget(reload: false) }
        }
    }

    private func updateChapterIndex() {
        guard let current = book else { return }
        let index = current.chapterIndex(at: currentTime)
        if index != currentChapterIndex {
            currentChapterIndex = index
            updateNowPlaying()
            updateWidget(reload: true)
        }
    }

    private func itemDidFinish(_ item: AVPlayerItem?) {
        guard let item, item === player.currentItem, let current = book else { return }
        if trackIndex + 1 < current.files.count {
            let next = trackIndex + 1
            currentTime = current.files[next].start
            setTrack(next, at: 0) // the status observer resumes playback
            updateChapterIndex()
        } else {
            player.pause()
            isPlaying = false
            pausedAt = nil
            currentTime = current.duration
            var finished = current
            finished.isFinished = true
            finished.position = current.duration
            finished.lastPlayed = Date()
            book = finished
            library.update(finished)
            updateNowPlaying()
            updateWidget(reload: true)
        }
    }

    // MARK: - Audio session

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        } catch {
            print("Audio session category error: \(error)")
        }
    }

    /// Activates the audio session before starting the player without blocking the main thread.
    private func activateAudioSession(completion: @escaping @MainActor () -> Void) {
        let session = AVAudioSession.sharedInstance()

        if #available(iOS 27.0, *) {
            session.activate(options: []) { [weak self] success, error in
                Task { @MainActor [weak self] in
                    self?.logAudioSessionActivationResult(success: success, error: error)
                    completion()
                }
            }
        } else {
            Task.detached {
                do {
                    try session.setActive(true)
                } catch {
                    print("Audio session activation error: \(error)")
                }

                await MainActor.run {
                    completion()
                }
            }
        }
    }

    private func logAudioSessionActivationResult(success: Bool, error: Error?) {
        if let error {
            print("Audio session activation error: \(error)")
            trace("audio session activation FAILED: \(error.localizedDescription)")
        } else if !success {
            trace("audio session activation FAILED without an error")
        }
    }

    /// Keeps the app running while playback is being started from the background (the book's file
    /// may still be loading and seeking), until audio is actually playing or 15 s have passed.
    private var startupTask: UIBackgroundTaskIdentifier = .invalid

    private func holdForStartup() {
        guard UIApplication.shared.applicationState != .active, startupTask == .invalid else { return }
        startupTask = UIApplication.shared.beginBackgroundTask(withName: "Start playback") { [weak self] in
            MainActor.assumeIsolated { self?.endStartupHold() }
        }
        let task = startupTask
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(15))
            if let self, self.startupTask == task { self.endStartupHold() }
        }
    }

    private func endStartupHold() {
        guard startupTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(startupTask)
        startupTask = .invalid
    }

    private func observeNotifications() {
        let center = NotificationCenter.default

        center.publisher(for: AVPlayerItem.didPlayToEndTimeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] note in
                self?.itemDidFinish(note.object as? AVPlayerItem)
            }
            .store(in: &cancellables)

        center.publisher(for: AVAudioSession.interruptionNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] note in
                self?.handleInterruption(note)
            }
            .store(in: &cancellables)

        center.publisher(for: AVAudioSession.routeChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] note in
                guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                      let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
                self?.trace("routeChange reason=\(reason.rawValue) outputs=\(AVAudioSession.sharedInstance().currentRoute.outputs.map(\.portType.rawValue))")
                // Headphones unplugged / Bluetooth disconnected: pause instead of playing out loud.
                if reason == .oldDeviceUnavailable { self?.pause() }
            }
            .store(in: &cancellables)

        // TEMP DEBUG
        for name in [UIApplication.didEnterBackgroundNotification, UIApplication.willEnterForegroundNotification,
                     UIApplication.didBecomeActiveNotification, UIApplication.willResignActiveNotification,
                     AVAudioSession.mediaServicesWereResetNotification, AVAudioSession.mediaServicesWereLostNotification] {
            center.publisher(for: name)
                .receive(on: RunLoop.main)
                .sink { [weak self] note in self?.trace("notification \(note.name.rawValue)") }
                .store(in: &cancellables)
        }
        player.publisher(for: \.timeControlStatus)
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                self?.trace("timeControlStatus -> \(status.rawValue)")
                // Audio is running: the app now stays alive on its own (background audio).
                if status == .playing { self?.endStartupHold() }
            }
            .store(in: &cancellables)

        // If the app is closed while playing, the Control Center button and widget would keep
        // showing "Playing" (and a tap would send Pause). Save the real state on the way out.
        center.publisher(for: UIApplication.willTerminateNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.closing = true
                self?.pause()
                self?.updateWidget(reload: true)   // tells the widget the app is closed
            }
            .store(in: &cancellables)
    }

    private func handleInterruption(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        trace("interruption type=\(type.rawValue) options=\(note.userInfo?[AVAudioSessionInterruptionOptionKey] ?? "-") reason=\(note.userInfo?[AVAudioSessionInterruptionReasonKey] ?? "-")")
        switch type {
        case .began:
            wasPlayingBeforeInterruption = isPlaying
            if isPlaying { pause() }
        case .ended:
            let optionsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
            if wasPlayingBeforeInterruption && options.contains(.shouldResume) { play() }
            wasPlayingBeforeInterruption = false
        @unknown default:
            break
        }
    }

    private func observeSettings() {
        settings.$skipBackInterval
            .sink { MPRemoteCommandCenter.shared().skipBackwardCommand.preferredIntervals = [NSNumber(value: $0)] }
            .store(in: &cancellables)
        settings.$skipForwardInterval
            .sink { MPRemoteCommandCenter.shared().skipForwardCommand.preferredIntervals = [NSNumber(value: $0)] }
            .store(in: &cancellables)
        settings.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.updateNowPlaying()
                    self?.updateWidget(reload: true)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Lock Screen / Control Center

    /// Runs `work` on the main actor: right away if the command arrived on the main thread (it
    /// normally does), so playback starts before the command returns; otherwise as soon as possible.
    private nonisolated static func onMain(_ work: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { work() }
        } else {
            Task { @MainActor in work() }
        }
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            guard self != nil else { return .noActionableNowPlayingItem }
            Self.onMain { self?.play() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Self.onMain { self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Self.onMain { self?.togglePlayPause() }
            return .success
        }

        center.skipBackwardCommand.isEnabled = true
        center.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skipBackward() }
            return .success
        }
        center.skipForwardCommand.isEnabled = true
        center.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skipForward() }
            return .success
        }

        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.nextChapter() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previousChapter() }
            return .success
        }

        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            Task { @MainActor in self?.handleRemoteScrub(to: position) }
            return .success
        }

        center.changePlaybackRateCommand.supportedPlaybackRates = AppSettings.speedPresets.map { NSNumber(value: $0) }
        center.changePlaybackRateCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackRateCommandEvent else { return .commandFailed }
            let rate = Double(event.playbackRate)
            Task { @MainActor in self?.setSpeed(rate) }
            return .success
        }
    }

    private var lockScreenUsesChapter: Bool {
        settings.useChapterContext && chapters.count > 1
    }

    private func handleRemoteScrub(to position: Double) {
        if lockScreenUsesChapter, let chapter = currentChapter {
            seek(to: chapter.start + position)
        } else {
            seek(to: position)
        }
    }

    private func updateNowPlaying() {
        guard let current = book else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        let chapter = currentChapter
        let useChapter = lockScreenUsesChapter && chapter != nil

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: (chapters.count > 1 ? chapter?.title : nil) ?? current.title,
            MPMediaItemPropertyArtist: current.author,
            MPMediaItemPropertyAlbumTitle: current.title,
            MPMediaItemPropertyPlaybackDuration: useChapter ? (chapter?.duration ?? 0) : current.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: useChapter ? currentTime - (chapter?.start ?? 0) : currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? speed : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: speed,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyChapterNumber: currentChapterIndex,
            MPNowPlayingInfoPropertyChapterCount: chapters.count,
        ]
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func loadArtwork() {
        guard let current = book,
              let url = library.coverURL(for: current),
              let image = UIImage(contentsOfFile: url.path) else {
            artwork = nil
            SharedStore.saveCover(nil)
            return
        }
        artwork = Self.makeArtwork(image)
        SharedStore.saveCover(ImageUtils.jpegData(image, maxDimension: 600))
    }

    /// Built outside the main actor because MediaPlayer calls the handler on a background queue.
    private nonisolated static func makeArtwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    // MARK: - Widget

    private func updateWidget(reload: Bool) {
        lastSnapshot = Date()
        guard let current = book else {
            SharedStore.saveSnapshot(.empty)
            reloadWidgets()
            return
        }
        let chapter = currentChapter
        let snapshot = NowPlayingSnapshot(
            hasBook: true,
            bookID: current.id.uuidString,
            bookTitle: current.title,
            author: current.author,
            chapterTitle: chapter?.title ?? current.title,
            chapterIndex: currentChapterIndex,
            chapterCount: chapters.count,
            isPlaying: isPlaying,
            bookElapsed: currentTime,
            bookDuration: current.duration,
            chapterElapsed: currentTime - (chapter?.start ?? 0),
            chapterDuration: chapter?.duration ?? current.duration,
            speed: speed,
            skipBack: settings.skipBackInterval,
            skipForward: settings.skipForwardInterval,
            useChapterContext: settings.useChapterContext,
            adjustForSpeed: settings.adjustForSpeed,
            updatedAt: Date(),
            appClosed: closing ? true : nil)
        SharedStore.saveSnapshot(snapshot)
        if reload { reloadWidgets() }
    }

    /// The app is quitting (the last snapshot says so).
    private var closing = false

    /// Saves a fresh snapshot for the widget and reloads it (e.g. when the app goes to the
    /// background, so the widget knows it's still running).
    func refreshWidget() {
        updateWidget(reload: true)
    }

    private func reloadWidgets() {
        WidgetCenter.shared.reloadTimelines(ofKind: SharedConfig.widgetKind)
        ControlCenter.shared.reloadControls(ofKind: SharedConfig.controlKind)
    }
}

/// Just "is a book loaded?", for views that only need that (the tab bar, the space pages keep for
/// the dock). Observing `PlayerController` itself redraws twice a second while playing.
@MainActor
final class NowPlayingPresence: ObservableObject {
    static let shared = NowPlayingPresence()
    @Published private(set) var hasBook = false

    func update(hasBook value: Bool) {
        if hasBook != value { hasBook = value }
    }
}
