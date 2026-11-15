import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var folderSync = FolderSync.shared
    @State private var choosingFolder = false

    /// A section to scroll to when opening (e.g. the player's "More" button opens the playback settings).
    var scrollTo: String? = nil
    static let playbackSection = "playback"

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            Form {
                folderSection

                Section {
                    Picker("Default cover edition", selection: $settings.coverRegion) {
                        ForEach(CoverRegion.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                } header: {
                    Text("Book Details")
                } footer: {
                    Text("New books get their cover and details from this Apple Books store. To use another cover for one book, long-press it and choose Edit Details → Change Cover.")
                }

                Section {
                    Picker("Skip back", selection: $settings.skipBackInterval) {
                        ForEach(AppSettings.skipOptions, id: \.self) { Text("\(Int($0)) seconds").tag($0) }
                    }
                    Picker("Skip forward", selection: $settings.skipForwardInterval) {
                        ForEach(AppSettings.skipOptions, id: \.self) { Text("\(Int($0)) seconds").tag($0) }
                    }
                } header: {
                    Text("Skip Intervals")
                        .id(Self.playbackSection)
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
                    NavigationLink {
                        SpeedButtonsSettingsView()
                    } label: {
                        LabeledContent("Speed buttons",
                                       value: settings.speedButtons.map(TimeFormat.speed).joined(separator: ", "))
                    }
                } header: {
                    Text("Playback Speed")
                } footer: {
                    Text("Speed buttons are the quick choices in the player's speed sheet.")
                }

                Section {
                    Toggle("Use chapter context", isOn: $settings.useChapterContext)
                    Toggle("Adjust times for speed", isOn: $settings.adjustForSpeed)
                } header: {
                    Text("Progress")
                } footer: {
                    Text("Chapter context: the progress bar and Lock Screen scrubber cover the current chapter instead of the whole book. Adjust for speed: remaining times reflect your playback speed. In the player, tap the time left to switch between the chapter and the whole book.")
                }

                Section {
                    Picker("Theme", selection: $settings.appearance) {
                        ForEach(AppAppearance.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    Toggle(isOn: $settings.backgroundMotionEnabled) {
                        Label("Shimmer & mascot animations", systemImage: "sparkles")
                    }
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("Automatic follows your iPhone's light or dark setting. The prism glass on the opening screen drifts and shimmers, and the mascot blinks and bobs along. Everything stays still when Reduce Motion is on.")
                }

                Section {
                    Label("Home Screen & Lock Screen: long-press the Home Screen, tap Edit › Add Widget, choose Audiobooks.", systemImage: "square.grid.2x2")
                    Label("Control Center: swipe down, tap +, Add a Control, choose Audiobooks.", systemImage: "switch.2")
                } header: {
                    Text("Widgets")
                }
                .font(.footnote)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result {
                    Task { await folderSync.choose(url) }
                }
            }
            .onAppear {
                if let scrollTo {
                    DispatchQueue.main.async { withAnimation { proxy.scrollTo(scrollTo, anchor: .top) } }
                }
            }
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

extension SettingsView {
    @ViewBuilder
    var folderSection: some View {
        Section {
            if let name = folderSync.folderName {
                HStack(spacing: 12) {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                        Text(checkedLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if folderSync.isSyncing { ProgressView() }
                }
                Button("Check Now") {
                    Task { await folderSync.sync(announceNothingNew: true) }
                }
                .disabled(folderSync.isSyncing)
                Button("Choose a Different Folder…") { choosingFolder = true }
                Button("Stop Watching", role: .destructive) { folderSync.stopWatching() }
            } else {
                Button {
                    choosingFolder = true
                } label: {
                    Label("Choose Folder…", systemImage: "folder.badge.plus")
                }
            }
        } header: {
            Text("Audiobooks Folder")
        } footer: {
            Text("Pick the folder in Files where you keep your audiobooks. New books there are added whenever you open the app: each audio file is a book, and each subfolder of audio files is one book. Books already in your library, or ones you deleted here, aren't added again.")
        }
    }

    private var checkedLine: String {
        guard let date = folderSync.lastChecked else { return "Checked when you open the app" }
        return "Checked \(date.formatted(.relative(presentation: .named)))"
    }
}

/// Choose which quick speed buttons the player's speed sheet shows (1 to 5 of them).
struct SpeedButtonsSettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section {
                ForEach(AppSettings.speedPresets, id: \.self) { speed in
                    let shown = settings.speedButtons.contains(speed)
                    let locked = shown ? settings.speedButtons.count == 1
                                       : settings.speedButtons.count >= AppSettings.maxSpeedButtons
                    Button {
                        settings.toggleSpeedButton(speed)
                    } label: {
                        HStack {
                            Text(TimeFormat.speed(speed))
                                .foregroundStyle(locked ? Color.secondary : Color.primary)
                            Spacer()
                            if shown {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .disabled(locked)
                    .accessibilityAddTraits(shown ? .isSelected : [])
                }
            } footer: {
                Text("Pick up to \(AppSettings.maxSpeedButtons). You can still choose any speed with the slider.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Speed Buttons")
        .navigationBarTitleDisplayMode(.inline)
    }
}
