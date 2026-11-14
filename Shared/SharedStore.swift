import Foundation
import UIKit

/// Values shared by the app and the widget extension.
enum SharedConfig {
    /// Read from Info.plist (filled in from Config/Config.xcconfig at build time).
    static let appGroupID: String =
        (Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String) ?? "group.com.example.audiobooks"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static var containerURL: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            return url
        }
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    static let widgetKind = "NowPlayingWidget"
    static let controlKind = "PlayPauseControl"
    static let urlScheme = "audiobookplayer"
}

/// A small, self-contained description of what's playing, written by the app and read by the widget.
struct NowPlayingSnapshot: Codable, Equatable {
    var hasBook: Bool
    var bookID: String
    var bookTitle: String
    var author: String
    var chapterTitle: String
    var chapterIndex: Int
    var chapterCount: Int
    var isPlaying: Bool
    var bookElapsed: Double
    var bookDuration: Double
    var chapterElapsed: Double
    var chapterDuration: Double
    var speed: Double
    var skipBack: Double
    var skipForward: Double
    var useChapterContext: Bool
    var adjustForSpeed: Bool
    var updatedAt: Date

    static let empty = NowPlayingSnapshot(
        hasBook: false, bookID: "", bookTitle: "", author: "", chapterTitle: "",
        chapterIndex: 0, chapterCount: 0, isPlaying: false,
        bookElapsed: 0, bookDuration: 0, chapterElapsed: 0, chapterDuration: 0,
        speed: 1, skipBack: 15, skipForward: 30, useChapterContext: true, adjustForSpeed: true,
        updatedAt: .distantPast)

    static let placeholder = NowPlayingSnapshot(
        hasBook: true, bookID: "placeholder", bookTitle: "The Long Way Home", author: "A. Author",
        chapterTitle: "Chapter 4: The River", chapterIndex: 3, chapterCount: 24, isPlaying: false,
        bookElapsed: 9_000, bookDuration: 36_000, chapterElapsed: 600, chapterDuration: 1_500,
        speed: 1, skipBack: 15, skipForward: 30, useChapterContext: true, adjustForSpeed: true,
        updatedAt: Date())

    /// Estimates where playback will be at `date` (used to keep the widget's progress moving).
    func extrapolated(to date: Date) -> NowPlayingSnapshot {
        guard isPlaying else { return self }
        let delta = max(0, date.timeIntervalSince(updatedAt)) * speed
        var copy = self
        copy.bookElapsed = min(bookDuration, bookElapsed + delta)
        copy.chapterElapsed = min(chapterDuration, chapterElapsed + delta)
        copy.updatedAt = date
        return copy
    }

    private var useChapter: Bool { useChapterContext && chapterCount > 1 }
    var scopeElapsed: Double { useChapter ? chapterElapsed : bookElapsed }
    var scopeDuration: Double { useChapter ? chapterDuration : bookDuration }
    var scopeProgress: Double { scopeDuration > 0 ? min(1, scopeElapsed / scopeDuration) : 0 }
    var scopeRemaining: Double { max(0, scopeDuration - scopeElapsed) / (adjustForSpeed ? speed : 1) }
    var bookRemaining: Double { max(0, bookDuration - bookElapsed) / (adjustForSpeed ? speed : 1) }
}

enum SharedStore {
    private static let snapshotKey = "nowPlayingSnapshot.v1"

    static func loadSnapshot() -> NowPlayingSnapshot? {
        guard let data = SharedConfig.defaults.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(NowPlayingSnapshot.self, from: data)
    }

    static func saveSnapshot(_ snapshot: NowPlayingSnapshot) {
        if let data = try? JSONEncoder().encode(snapshot) {
            SharedConfig.defaults.set(data, forKey: snapshotKey)
        }
    }

    static var coverURL: URL {
        SharedConfig.containerURL.appendingPathComponent("widget-cover.jpg")
    }

    static func saveCover(_ data: Data?) {
        if let data {
            try? data.write(to: coverURL, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: coverURL)
        }
    }

    static func loadCover() -> UIImage? {
        UIImage(contentsOfFile: coverURL.path)
    }
}

enum TimeFormat {
    /// 1:02:03 or 12:03
    static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "--:--" }
        let s = Int(max(0, seconds).rounded(.down))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    /// 5h 12m, 12m, 40s
    static func short(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "–" }
        let s = Int(max(0, seconds).rounded())
        let h = s / 3600, m = (s % 3600) / 60
        if h > 0 { return m > 0 ? "\(h)h \(m)m" : "\(h)h" }
        if m > 0 { return "\(m)m" }
        return "\(s)s"
    }

    /// 1×, 1.25×, 1.5×
    static func speed(_ value: Double) -> String {
        var text = String(format: "%.2f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text + "×"
    }
}
