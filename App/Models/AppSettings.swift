import Foundation
import Combine

/// Global settings, saved to UserDefaults.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    static let skipOptions: [Double] = [5, 10, 15, 20, 30, 45, 60, 90]
    static let smartRewindOptions: [Double] = [5, 10, 15, 20, 30, 45, 60]
    static let speedPresets: [Double] = [0.75, 1.0, 1.1, 1.2, 1.25, 1.3, 1.5, 1.75, 2.0, 2.5, 3.0]

    // Playback
    @Published var skipBackInterval: Double { didSet { save(skipBackInterval, "skipBackInterval") } }
    @Published var skipForwardInterval: Double { didSet { save(skipForwardInterval, "skipForwardInterval") } }
    @Published var defaultSpeed: Double { didSet { save(defaultSpeed, "defaultSpeed") } }
    @Published var rememberSpeedPerBook: Bool { didSet { save(rememberSpeedPerBook, "rememberSpeedPerBook") } }

    // Smart rewind
    @Published var smartRewindEnabled: Bool { didSet { save(smartRewindEnabled, "smartRewindEnabled") } }
    @Published var smartRewindLimit: Double { didSet { save(smartRewindLimit, "smartRewindLimit") } }

    // Progress display
    /// Progress bar, time labels and Lock Screen scrubber refer to the current chapter instead of the whole book.
    @Published var useChapterContext: Bool { didSet { save(useChapterContext, "useChapterContext") } }
    /// Right-hand label shows time remaining (-12:34) instead of total duration.
    @Published var useRemainingTime: Bool { didSet { save(useRemainingTime, "useRemainingTime") } }
    /// Show an extra "5h 12m left in book" line.
    @Published var showTotalRemaining: Bool { didSet { save(showTotalRemaining, "showTotalRemaining") } }
    /// Remaining times take playback speed into account.
    @Published var adjustForSpeed: Bool { didSet { save(adjustForSpeed, "adjustForSpeed") } }

    private init() {
        let d = UserDefaults.standard
        skipBackInterval = d.object(forKey: "skipBackInterval") as? Double ?? 15
        skipForwardInterval = d.object(forKey: "skipForwardInterval") as? Double ?? 30
        defaultSpeed = d.object(forKey: "defaultSpeed") as? Double ?? 1.0
        rememberSpeedPerBook = d.object(forKey: "rememberSpeedPerBook") as? Bool ?? true
        smartRewindEnabled = d.object(forKey: "smartRewindEnabled") as? Bool ?? true
        smartRewindLimit = d.object(forKey: "smartRewindLimit") as? Double ?? 30
        useChapterContext = d.object(forKey: "useChapterContext") as? Bool ?? true
        useRemainingTime = d.object(forKey: "useRemainingTime") as? Bool ?? true
        showTotalRemaining = d.object(forKey: "showTotalRemaining") as? Bool ?? true
        adjustForSpeed = d.object(forKey: "adjustForSpeed") as? Bool ?? true
    }

    private func save(_ value: Any, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}

/// How far to rewind when resuming, based on how long playback was paused.
enum SmartRewind {
    static func amount(pausedFor interval: TimeInterval, limit: Double) -> Double {
        let base: Double
        switch interval {
        case ..<5: base = 0              // a quick tap: no rewind
        case ..<60: base = 3             // under a minute
        case ..<300: base = 10           // under 5 minutes
        case ..<1800: base = 20          // under 30 minutes
        case ..<7200: base = 30          // under 2 hours
        default: base = 60               // longer breaks
        }
        return min(base, limit)
    }
}
