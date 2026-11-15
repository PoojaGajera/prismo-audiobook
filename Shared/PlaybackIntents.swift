import AppIntents
import Foundation

// These intents are compiled into BOTH the app and the widget extension.
// Because they conform to `AudioPlaybackIntent`, iOS runs them inside the app's
// process (launching it in the background if needed), so the widget buttons can
// start and stop real audio. The `MAIN_APP` flag is only defined for the app target.

struct TogglePlaybackIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Play or Pause Audiobook"
    static var description = IntentDescription("Plays or pauses the current audiobook.")

    init() {}

    func perform() async throws -> some IntentResult {
        #if MAIN_APP
        await MainActor.run { PlayerController.shared.togglePlayPause() }
        #endif
        return .result()
    }
}

struct SkipBackwardIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Skip Back"
    static var description = IntentDescription("Skips back by your skip-back interval.")

    init() {}

    func perform() async throws -> some IntentResult {
        #if MAIN_APP
        await MainActor.run { PlayerController.shared.skipBackward() }
        #endif
        return .result()
    }
}

struct SkipForwardIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Skip Forward"
    static var description = IntentDescription("Skips forward by your skip-forward interval.")

    init() {}

    func perform() async throws -> some IntentResult {
        #if MAIN_APP
        await MainActor.run { PlayerController.shared.skipForward() }
        #endif
        return .result()
    }
}

struct PreviousChapterIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Previous Chapter"
    static var description = IntentDescription("Goes to the start of the chapter, or the one before.")

    init() {}

    func perform() async throws -> some IntentResult {
        #if MAIN_APP
        await MainActor.run { PlayerController.shared.previousChapter() }
        #endif
        return .result()
    }
}

struct NextChapterIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Next Chapter"
    static var description = IntentDescription("Skips to the next chapter.")

    init() {}

    func perform() async throws -> some IntentResult {
        #if MAIN_APP
        await MainActor.run { PlayerController.shared.nextChapter() }
        #endif
        return .result()
    }
}

/// Used by the Control Center / Lock Screen control (iOS 18+).
struct SetPlayingIntent: SetValueIntent, AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Set Audiobook Playing"

    @Parameter(title: "Playing")
    var value: Bool

    init() {}

    func perform() async throws -> some IntentResult {
        #if MAIN_APP
        let shouldPlay = value
        await MainActor.run { PlayerController.shared.setPlaying(shouldPlay) }
        #endif
        return .result()
    }
}
