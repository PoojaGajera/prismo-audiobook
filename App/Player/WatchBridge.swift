import Foundation
import Combine
import UIKit
import WatchConnectivity

/// The iPhone side of the Apple Watch remote. It sends the watch what's playing (book, chapter,
/// position, speed, chapter list and a small cover) and carries out the watch's commands
/// (play/pause, skip, chapters, speed). The audio always plays on the iPhone.
///
/// The watch app sends `["command": …]` messages (see `Command`) and reads the latest state from
/// the application context (`WatchState` keys), which iOS delivers even when the watch app
/// wasn't running.
@MainActor
final class WatchBridge: NSObject {
    static let shared = WatchBridge()

    /// Commands the watch can send, as the message's "command" value.
    enum Command: String {
        case toggle, play, pause, skipBack, skipForward, previousChapter, nextChapter, jumpToChapter, setSpeed, refresh
    }

    private var cancellables: Set<AnyCancellable> = []
    private var lastSent: [String: Any] = [:]
    private var lastCoverKey: String?
    private var lastCover: Data?

    private override init() { super.init() }

    /// Call once at launch.
    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()

        // Send whenever playback changes (throttled: position only moves the watch's clock).
        PlayerController.shared.objectWillChange
            .throttle(for: .seconds(1), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in Task { @MainActor in self?.sendState() } }
            .store(in: &cancellables)
    }

    // MARK: State

    /// What the watch shows. Times are book seconds; the watch moves the clock on by itself
    /// while `isPlaying`, from `sentAt`.
    private func state() -> [String: Any] {
        let player = PlayerController.shared
        guard let book = player.book else { return ["hasBook": false] }
        var state: [String: Any] = [
            "hasBook": true,
            "bookID": book.id.uuidString,
            "title": book.title,
            "author": book.author,
            "isPlaying": player.isPlaying,
            "time": player.currentTime,
            "duration": book.duration,
            "speed": player.speed,
            "chapterIndex": player.currentChapterIndex,
            "chapterTitles": player.chapters.map(\.title),
            "chapterStarts": player.chapters.map(\.start),
            "skipBack": AppSettings.shared.skipBackInterval,
            "skipForward": AppSettings.shared.skipForwardInterval,
            "sentAt": Date().timeIntervalSince1970,
        ]
        if let cover = cover(for: book) { state["cover"] = cover }
        return state
    }

    /// A cover for the watch background (about 360 px, roughly 30 KB).
    private func cover(for book: Book) -> Data? {
        let key = "\(book.id)#\(book.coverVersion ?? 0)"
        if key == lastCoverKey { return lastCover }
        lastCoverKey = key
        lastCover = CoverCache.image(for: book, fullSize: false)
            .flatMap { ImageUtils.jpegData($0, maxDimension: 360, quality: 0.65) }
        return lastCover
    }

    private func sendState(force: Bool = false) {
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        let state = state()
        // Skip sends that change nothing but the clock (the watch keeps time itself).
        if !force, Self.sameExceptClock(state, lastSent) { return }
        lastSent = state
        try? session.updateApplicationContext(state)
        if session.isReachable {
            session.sendMessage(["state": state], replyHandler: nil, errorHandler: nil)
        }
    }

    private static func sameExceptClock(_ a: [String: Any], _ b: [String: Any]) -> Bool {
        guard !b.isEmpty else { return false }
        let keys = ["hasBook", "bookID", "title", "isPlaying", "speed", "chapterIndex", "chapterTitles"]
        for key in keys where "\(a[key] ?? "")" != "\(b[key] ?? "")" { return false }
        // Position: only a jump (seek), not normal playing, needs a send.
        let time = a["time"] as? Double ?? 0, lastTime = b["time"] as? Double ?? 0
        let elapsed = (a["sentAt"] as? Double ?? 0) - (b["sentAt"] as? Double ?? 0)
        let expected = lastTime + ((b["isPlaying"] as? Bool ?? false) ? elapsed * (b["speed"] as? Double ?? 1) : 0)
        return abs(time - expected) < 5
    }

    // MARK: Commands

    private func perform(_ message: [String: Any]) {
        let player = PlayerController.shared
        guard let raw = message["command"] as? String, let command = Command(rawValue: raw) else { return }
        switch command {
        case .toggle: player.togglePlayPause()
        case .play: if !player.isPlaying { player.play() }
        case .pause: if player.isPlaying { player.pause() }
        case .skipBack: player.skipBackward()
        case .skipForward: player.skipForward()
        case .previousChapter: player.previousChapter()
        case .nextChapter: player.nextChapter()
        case .jumpToChapter:
            if let index = message["index"] as? Int {
                player.jumpToChapter(index)
                if !player.isPlaying { player.play() }
            }
        case .setSpeed:
            if let speed = message["speed"] as? Double { player.setSpeed(speed) }
        case .refresh: break
        }
        sendState(force: true)
    }
}

extension WatchBridge: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        Task { @MainActor in self.sendState(force: true) }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Switched to another watch: start again with it.
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.sendState(force: true) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.sendState(force: true) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let copy = message as NSDictionary
        Task { @MainActor in self.perform(copy as? [String: Any] ?? [:]) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        let copy = message as NSDictionary
        Task { @MainActor in
            self.perform(copy as? [String: Any] ?? [:])
            replyHandler(["ok": true])
        }
    }
}
