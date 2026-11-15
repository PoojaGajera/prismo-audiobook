import Foundation
import Combine
import UIKit

/// Global settings, saved to UserDefaults.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    static let skipOptions: [Double] = [5, 10, 15, 20, 30, 45, 60, 90]
    static let smartRewindOptions: [Double] = [5, 10, 15, 20, 30, 45, 60]
    static let speedPresets: [Double] = [0.75, 1.0, 1.1, 1.2, 1.25, 1.3, 1.5, 1.6, 1.75, 2.0, 2.5, 3.0]
    /// The speed buttons shown in the player's speed sheet when nothing has been chosen yet.
    static let defaultSpeedButtons: [Double] = [1.0, 1.25, 1.5]
    /// At most this many speed buttons fit in one row.
    static let maxSpeedButtons = 5

    // Playback
    @Published var skipBackInterval: Double { didSet { save(skipBackInterval, "skipBackInterval") } }
    @Published var skipForwardInterval: Double { didSet { save(skipForwardInterval, "skipForwardInterval") } }
    @Published var defaultSpeed: Double { didSet { save(defaultSpeed, "defaultSpeed") } }
    @Published var rememberSpeedPerBook: Bool { didSet { save(rememberSpeedPerBook, "rememberSpeedPerBook") } }
    /// The quick speed buttons in the player's speed sheet (from `speedPresets`), in ascending order.
    @Published var speedButtons: [Double] { didSet { save(speedButtons, "speedButtons") } }

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

    // Book details
    /// The store edition (UK by default) that new books' covers and details come from.
    /// Raw value of `CoverRegion`. Each book's cover can still be changed in Edit Details.
    @Published var coverRegion: String { didSet { save(coverRegion, "coverRegion") } }

    // Appearance
    /// Light, dark, or match the iPhone. Raw value of `AppAppearance`.
    @Published var appearance: String {
        didSet {
            save(appearance, "appearance")
            applyAppearance(animated: true)
        }
    }
    /// The prism background drifts and shimmers, and the mascot moves.
    @Published var backgroundMotionEnabled: Bool {
        didSet {
            save(backgroundMotionEnabled, "backgroundMotionEnabled")
            Theme.motionEnabled = backgroundMotionEnabled
        }
    }

    private init() {
        let d = UserDefaults.standard
        skipBackInterval = d.object(forKey: "skipBackInterval") as? Double ?? 15
        skipForwardInterval = d.object(forKey: "skipForwardInterval") as? Double ?? 30
        defaultSpeed = d.object(forKey: "defaultSpeed") as? Double ?? 1.0
        rememberSpeedPerBook = d.object(forKey: "rememberSpeedPerBook") as? Bool ?? true
        let storedButtons = (d.array(forKey: "speedButtons") as? [Double])?.filter { Self.speedPresets.contains($0) }
        speedButtons = (storedButtons?.isEmpty == false ? storedButtons! : Self.defaultSpeedButtons).sorted()
        smartRewindEnabled = d.object(forKey: "smartRewindEnabled") as? Bool ?? true
        smartRewindLimit = d.object(forKey: "smartRewindLimit") as? Double ?? 30
        useChapterContext = d.object(forKey: "useChapterContext") as? Bool ?? true
        useRemainingTime = d.object(forKey: "useRemainingTime") as? Bool ?? true
        showTotalRemaining = d.object(forKey: "showTotalRemaining") as? Bool ?? true
        adjustForSpeed = d.object(forKey: "adjustForSpeed") as? Bool ?? true
        backgroundMotionEnabled = d.object(forKey: "backgroundMotionEnabled") as? Bool ?? true
        coverRegion = d.string(forKey: "coverRegion") ?? CoverRegion.standard.rawValue
        appearance = d.string(forKey: "appearance") ?? AppAppearance.system.rawValue
        // All stored properties are set; `self` can be read from here on.
        Theme.motionEnabled = backgroundMotionEnabled
        resetAlternateIcon()
    }

    /// Puts the Home Screen icon back to the default, in case the archived Owl theme had switched it.
    private func resetAlternateIcon() {
        let app = UIApplication.shared
        guard app.supportsAlternateIcons, app.alternateIconName != nil else { return }
        app.setAlternateIconName(nil) { error in
            if let error { print("Couldn't reset the app icon: \(error.localizedDescription)") }
        }
    }

    /// Applies the chosen appearance to every window (so sheets, alerts and system controls follow it too).
    func applyAppearance(animated: Bool = false) {
        let style = (AppAppearance(rawValue: appearance) ?? .system).interfaceStyle
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows where window.overrideUserInterfaceStyle != style {
                if animated {
                    UIView.transition(with: window, duration: 0.3, options: .transitionCrossDissolve) {
                        window.overrideUserInterfaceStyle = style
                    }
                } else {
                    window.overrideUserInterfaceStyle = style
                }
            }
        }
    }

    /// Shows or hides one speed button, keeping at least one and at most `maxSpeedButtons`.
    func toggleSpeedButton(_ speed: Double) {
        if let i = speedButtons.firstIndex(of: speed) {
            guard speedButtons.count > 1 else { return }
            speedButtons.remove(at: i)
        } else {
            guard speedButtons.count < Self.maxSpeedButtons else { return }
            speedButtons = (speedButtons + [speed]).sorted()
        }
    }

    private func save(_ value: Any, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}

/// The app's light / dark setting.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "Automatic"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
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
