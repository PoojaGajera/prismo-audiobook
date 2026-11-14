import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Skip back", selection: $settings.skipBackInterval) {
                        ForEach(AppSettings.skipOptions, id: \.self) { Text("\(Int($0)) seconds").tag($0) }
                    }
                    Picker("Skip forward", selection: $settings.skipForwardInterval) {
                        ForEach(AppSettings.skipOptions, id: \.self) { Text("\(Int($0)) seconds").tag($0) }
                    }
                } header: {
                    Text("Skip Intervals")
                } footer: {
                    Text("Also used by the Lock Screen, headphones, CarPlay and the widget.")
                }

                Section {
                    Toggle("Smart rewind", isOn: $settings.smartRewindEnabled)
                    Picker("Rewind limit", selection: $settings.smartRewindLimit) {
                        ForEach(AppSettings.smartRewindOptions, id: \.self) { Text("\(Int($0)) seconds").tag($0) }
                    }
                    .disabled(!settings.smartRewindEnabled)
                } header: {
                    Text("Smart Rewind")
                } footer: {
                    Text("When you resume, rewinds a little so you can pick up the thread: 3s after a short pause, up to 60s after a long break, never more than the limit.")
                }

                Section {
                    Picker("Default speed", selection: $settings.defaultSpeed) {
                        ForEach(AppSettings.speedPresets, id: \.self) { Text(TimeFormat.speed($0)).tag($0) }
                    }
                    Toggle("Remember speed per book", isOn: $settings.rememberSpeedPerBook)
                } header: {
                    Text("Playback Speed")
                }

                Section {
                    Toggle("Use chapter context", isOn: $settings.useChapterContext)
                    Toggle("Show remaining time", isOn: $settings.useRemainingTime)
                    Toggle("Show total remaining time", isOn: $settings.showTotalRemaining)
                    Toggle("Adjust times for speed", isOn: $settings.adjustForSpeed)
                } header: {
                    Text("Progress")
                } footer: {
                    Text("Chapter context: the progress bar, time labels and Lock Screen scrubber cover the current chapter instead of the whole book. Remaining time: the right-hand label counts down instead of showing the length. Total remaining: adds a “left in book” line. Adjust for speed: remaining times reflect your playback speed.")
                }

                Section {
                    Label("Home Screen & Lock Screen: long-press the Home Screen, tap Edit › Add Widget, choose Audiobooks.", systemImage: "square.grid.2x2")
                    Label("Control Center: swipe down, tap +, Add a Control, choose Audiobooks.", systemImage: "switch.2")
                } header: {
                    Text("Widgets")
                }
                .font(.footnote)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
