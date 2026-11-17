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
        let player = await PlayerController.shared
        if await player.isPlaying {
            await player.pause()
        } else {
            // Waits until sound starts, so a background launch isn't suspended first.
            await player.playAndWait()
        }
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
        let player = await PlayerController.shared
        let playing = await player.isPlaying
        // The control shows the last saved state, which can be stale (e.g. the app was closed
        // while playing). A tap on a stale "Playing" sends Pause to a stopped player: play
        // instead, since that's what the tap meant.
        if shouldPlay || !playing {
            // Waits until sound starts, so a background launch isn't suspended first.
            await player.playAndWait()
        } else {
            await player.pause()
        }
        #endif
        return .result()
    }
}

/// Play from the widget: opens the app (in front) and plays the widget's book there, with the
/// player open. Used for the widget's Play (when nothing is playing): the widget can't tell
/// whether the app is still running, and playing from a background launch wasn't reliable, so
/// Play always brings the app up. Pause stays in the background (`SetPlayingIntent`).
struct PlayInAppIntent: AppIntent {
    static var title: LocalizedStringResource = "Play Audiobook"
    static var description = IntentDescription("Opens the app and plays the audiobook.")
    static var openAppWhenRun: Bool = true
    static var isDiscoverable: Bool = false

    @Parameter(title: "Book ID")
    var bookID: String

    init() {}

    init(bookID: String) {
        self.bookID = bookID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if MAIN_APP
        let player = PlayerController.shared
        if let id = UUID(uuidString: bookID), player.book?.id != id,
           let book = LibraryStore.shared.book(id: id), book.hasAudio {
            player.load(book, autoplay: false)
        }
        AppRouter.shared.showPlayer = true
        await player.playAndWait()
        #endif
        return .result()
    }
}
