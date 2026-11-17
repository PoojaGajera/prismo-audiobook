import Combine
import Foundation
import WatchConnectivity
import WatchKit

/// What's playing on the iPhone, as `WatchBridge` (iPhone side) sends it.
nonisolated struct NowPlaying: Equatable, Sendable {
    var hasBook = false
    var bookID = ""
    var title = ""
    var author = ""
    var isPlaying = false
    var time: Double = 0
    var duration: Double = 0
    var speed: Double = 1
    var chapterIndex = 0
    var chapterTitles: [String] = []
    var chapterStarts: [Double] = []
    var skipBack: Double = 15
    var skipForward: Double = 30
    /// When the iPhone sent `time` (seconds since 1970). The watch moves the clock on from here.
    var sentAt: Double = 0
    var cover: Data?

    init() {}

    init(_ d: [String: Any]) {
        hasBook = d["hasBook"] as? Bool ?? false
        bookID = d["bookID"] as? String ?? ""
        title = d["title"] as? String ?? ""
        author = d["author"] as? String ?? ""
        isPlaying = d["isPlaying"] as? Bool ?? false
        time = d["time"] as? Double ?? 0
        duration = d["duration"] as? Double ?? 0
        speed = d["speed"] as? Double ?? 1
        chapterIndex = d["chapterIndex"] as? Int ?? 0
        chapterTitles = d["chapterTitles"] as? [String] ?? []
        chapterStarts = d["chapterStarts"] as? [Double] ?? []
        skipBack = d["skipBack"] as? Double ?? 15
        skipForward = d["skipForward"] as? Double ?? 30
        sentAt = d["sentAt"] as? Double ?? Date().timeIntervalSince1970
        cover = d["cover"] as? Data
    }

    var hasChapters: Bool { chapterTitles.count > 1 && chapterStarts.count == chapterTitles.count }

    /// The book position right now, moving on while playing.
    func time(at date: Date) -> Double {
        guard isPlaying else { return time }
        let elapsed = max(0, date.timeIntervalSince1970 - sentAt)
        return min(duration, time + elapsed * speed)
    }

    /// The chapter at a position (falls back to the last one the iPhone reported).
    func chapterIndex(at position: Double) -> Int {
        guard hasChapters else { return 0 }
        return chapterStarts.lastIndex(where: { $0 <= position + 0.5 }) ?? chapterIndex
    }

    /// Start and end of the chapter (or the whole book when there are no chapters).
    func scope(at position: Double) -> (start: Double, end: Double) {
        guard hasChapters else { return (0, duration) }
        let index = chapterIndex(at: position)
        let end = index + 1 < chapterStarts.count ? chapterStarts[index + 1] : duration
        return (chapterStarts[index], end)
    }

    func chapterTitle(at position: Double) -> String? {
        guard hasChapters else { return nil }
        let index = chapterIndex(at: position)
        return chapterTitles.indices.contains(index) ? chapterTitles[index] : nil
    }
}

/// The watch end of the connection: keeps `nowPlaying` up to date and sends commands to the iPhone,
/// where the audio plays. Command names match `WatchBridge.Command`.
@MainActor
final class WatchSession: NSObject, ObservableObject {
    static let shared = WatchSession()

    @Published private(set) var nowPlaying = NowPlaying()
    @Published private(set) var isReachable = false
    @Published private(set) var hasHeardFromPhone = false

    private override init() { super.init() }

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: Commands

    func togglePlayPause() {
        WKInterfaceDevice.current().play(.click)
        // Show the change at once; the iPhone's reply confirms it.
        var state = nowPlaying
        state.time = state.time(at: Date())
        state.sentAt = Date().timeIntervalSince1970
        state.isPlaying.toggle()
        nowPlaying = state
        send("toggle")
    }

    func skipBack() { nudge(by: -nowPlaying.skipBack); send("skipBack") }
    func skipForward() { nudge(by: nowPlaying.skipForward); send("skipForward") }

    func previousChapter() { WKInterfaceDevice.current().play(.click); send("previousChapter") }
    func nextChapter() { WKInterfaceDevice.current().play(.click); send("nextChapter") }

    func jumpToChapter(_ index: Int) {
        WKInterfaceDevice.current().play(.click)
        if nowPlaying.chapterStarts.indices.contains(index) {
            var state = nowPlaying
            state.time = state.chapterStarts[index]
            state.chapterIndex = index
            state.sentAt = Date().timeIntervalSince1970
            state.isPlaying = true
            nowPlaying = state
        }
        send("jumpToChapter", ["index": index])
    }

    func setSpeed(_ speed: Double) {
        var state = nowPlaying
        state.time = state.time(at: Date())
        state.sentAt = Date().timeIntervalSince1970
        state.speed = speed
        nowPlaying = state
        send("setSpeed", ["speed": speed])
    }

    func refresh() { send("refresh") }

    private func nudge(by seconds: Double) {
        WKInterfaceDevice.current().play(.click)
        var state = nowPlaying
        state.time = min(state.duration, max(0, state.time(at: Date()) + seconds))
        state.sentAt = Date().timeIntervalSince1970
        nowPlaying = state
    }

    private func send(_ command: String, _ extra: [String: Any] = [:]) {
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        var message: [String: Any] = ["command": command]
        message.merge(extra) { $1 }
        // Wakes the iPhone app in the background if needed.
        session.sendMessage(message, replyHandler: nil) { _ in
            Task { @MainActor in WKInterfaceDevice.current().play(.failure) }
        }
    }

    // MARK: Incoming

    fileprivate func apply(_ new: NowPlaying) {
        hasHeardFromPhone = true
        // Keep the cover if this update didn't carry one for the same book.
        var merged = new
        if merged.cover == nil, merged.bookID == nowPlaying.bookID { merged.cover = nowPlaying.cover }
        if merged != nowPlaying { nowPlaying = merged }
    }

    fileprivate func updateReachability() {
        isReachable = WCSession.default.isReachable
    }
}

extension WatchSession: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        let context = session.receivedApplicationContext
        let state = NowPlaying(context)
        let hasContext = !context.isEmpty
        Task { @MainActor in
            if hasContext { self.apply(state) }
            self.updateReachability()
            self.refresh()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.updateReachability()
            if self.isReachable { self.refresh() }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let state = NowPlaying(applicationContext)
        Task { @MainActor in self.apply(state) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let context = message["state"] as? [String: Any] else { return }
        let state = NowPlaying(context)
        Task { @MainActor in self.apply(state) }
    }
}
