import WidgetKit
import SwiftUI
import AppIntents

/// Control Center / Lock Screen / Action Button control (iOS 18+).
struct PlayPauseControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: SharedConfig.controlKind, provider: Provider()) { isPlaying in
            ControlWidgetToggle("Audiobook", isOn: isPlaying, action: SetPlayingIntent()) { isOn in
                Label(isOn ? "Playing" : "Paused", systemImage: isOn ? "pause.fill" : "play.fill")
            }
            .tint(Theme.accent)
        }
        .displayName("Play/Pause Audiobook")
        .description("Plays or pauses your current audiobook.")
    }

    struct Provider: ControlValueProvider {
        var previewValue: Bool { false }

        func currentValue() async throws -> Bool {
            SharedStore.loadSnapshot()?.isPlaying ?? false
        }
    }
}
