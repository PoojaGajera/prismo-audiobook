import SwiftUI
import UniformTypeIdentifiers

/// Settings: plain rows in rounded cards, grouped under short headings. Headings and row text
/// share the same left edge.
struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var folderSync = FolderSync.shared
    @ObservedObject private var enricher = MetadataEnricher.shared
    @ObservedObject private var library = LibraryStore.shared
    @State private var choosingFolder = false
    @AppStorage(LibraryView.layoutKey) private var layout = "list"

    /// A section to scroll to when opening (e.g. the player's "Playback Settings").
    var scrollTo: String? = nil
    /// True on the Settings tab (no Done button; room for the tab bar). False in a sheet.
    var embedded = false
    static let playbackSection = "playback"

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: Spacing.l) {
                        SettingsSection("Library") {
                            pickerRow("View", selection: $layout, options: ["list", "tiles"]) {
                                $0 == "tiles" ? "Tiles" : "List"
                            }
                            buttonRow(library.isImporting ? "Adding…" : "Import Audiobooks…") {
                                // The picker opens from the library (it also asks how to group files).
                                AppRouter.shared.tab = .library
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    AppRouter.shared.importRequest += 1
                                }
                                if !embedded { dismiss() }
                            }
                            .disabled(library.isImporting)
                            HStack {
                                buttonRow("Sync Books & Details") {
                                    Task { await LibraryView.syncAll() }
                                }
                                if folderSync.isSyncing || enricher.isRefreshing { ProgressView() }
                            }
                            .disabled(folderSync.isSyncing || enricher.isRefreshing)
                        }

                        SettingsSection("Playback") {
                            pickerRow("Skip back", selection: $settings.skipBackInterval,
                                      options: AppSettings.skipOptions) { "\(Int($0)) sec" }
                            pickerRow("Skip forward", selection: $settings.skipForwardInterval,
                                      options: AppSettings.skipOptions) { "\(Int($0)) sec" }
                            Toggle("Smart rewind", isOn: $settings.smartRewindEnabled)
                            if settings.smartRewindEnabled {
                                pickerRow("Rewind limit", selection: $settings.smartRewindLimit,
                                          options: AppSettings.smartRewindOptions) { "\(Int($0)) sec" }
                            }
                        }
                        .id(Self.playbackSection)

                        SettingsSection("Speed") {
                            pickerRow("Default speed", selection: $settings.defaultSpeed,
                                      options: AppSettings.speedPresets) { TimeFormat.speed($0) }
                            Toggle("Remember speed per book", isOn: $settings.rememberSpeedPerBook)
                            NavigationLink {
                                SpeedButtonsSettingsView()
                            } label: {
                                navigationRow("Speed buttons",
                                              value: settings.speedButtons.map(TimeFormat.speed).joined(separator: ", "))
                            }
                            .buttonStyle(.plain)
                        }

                        SettingsSection("Progress") {
                            Toggle("Chapter progress", isOn: $settings.useChapterContext)
                            Toggle("Adjust times for speed", isOn: $settings.adjustForSpeed)
                        }

                        SettingsSection("Appearance") {
                            pickerRow("App theme", selection: $settings.playerBackground,
                                      options: PlayerBackgroundStyle.allCases.map(\.rawValue)) {
                                PlayerBackgroundStyle(rawValue: $0)?.label ?? $0
                            }
                            // (No light/dark choice: every theme is light now.)
                            // Named after the theme's floating details (hearts, leaves, bubbles…).
                            Toggle(Theme.current.particles.name, isOn: $settings.snowfall)
                            if settings.snowfall {
                                pickerRow("Amount", selection: $settings.particleCount,
                                          options: AppSettings.particleCountOptions) {
                                    $0 < 14 ? "A few" : ($0 < 24 ? "Some" : "Lots")
                                }
                                pickerRow("Speed", selection: $settings.particleSpeed,
                                          options: AppSettings.particleSpeedOptions) {
                                    $0 < 0.8 ? "Slow" : ($0 < 1.3 ? "Gentle" : "Lively")
                                }
                            }
                            Toggle("Animations", isOn: $settings.backgroundMotionEnabled)
                        }

                        SettingsSection("Audiobooks Folder") {
                            folderRows
                        }

                        // (Book Details → Cover store was removed at the user's request; covers use the
                        // saved/default store, UK, via `AppSettings.coverRegion`.)
                    }
                    // Rebuilt when the app theme changes, so every card takes the new colours at once
                    // (one card kept Pink smoke's white under Cosmos, with white text on it).
                    .id(settings.playerBackground)
                    .padding(.horizontal, Spacing.m)
                    .padding(.top, Spacing.s)
                    .padding(.bottom, Spacing.xl)
                }
                .onAppear {
                    if let scrollTo {
                        DispatchQueue.main.async { withAnimation { proxy.scrollTo(scrollTo, anchor: .top) } }
                    }
                }
            }
            // Live (moving) on the Settings tab; still when opened as a sheet.
            .background { ThemedPageBackground(live: embedded) }
            .safeAreaInset(edge: .bottom) { if embedded { BottomBarSpace() } }
            .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result {
                    Task { await folderSync.choose(url) }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !embedded {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
    }

    // MARK: - Rows

    /// A title on the left and the current choice on the right (tap to pick from a menu).
    private func pickerRow<Value: Hashable>(_ title: String, selection: Binding<Value>, options: [Value],
                                            label: @escaping (Value) -> String) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: Spacing.s)
            Picker(title, selection: selection) {
                ForEach(options, id: \.self) { Text(label($0)).tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(Theme.secondaryText)
        }
    }

    private func navigationRow(_ title: String, value: String) -> some View {
        HStack(spacing: Spacing.xs) {
            Text(title)
            Spacer(minLength: Spacing.s)
            Text(value)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.tertiaryText)
        }
        .contentShape(Rectangle())
    }

    private func buttonRow(_ title: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            Text(title)
                .foregroundStyle(role == .destructive ? Color.red : Theme.accent)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var folderRows: some View {
        if let name = folderSync.folderName {
            HStack(spacing: Spacing.s) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                    Text(checkedLine)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                if folderSync.isSyncing { ProgressView() }
            }
            .padding(.vertical, Spacing.xs)
            // (No "Check Now": Library → Sync Books & Details checks the folder too.)
            buttonRow("Change Folder") { choosingFolder = true }
            buttonRow("Stop Watching", role: .destructive) { folderSync.stopWatching() }
        } else {
            buttonRow("Choose Folder") { choosingFolder = true }
        }
    }

    private var checkedLine: String {
        guard let date = folderSync.lastChecked else { return "Not checked yet" }
        return "Checked \(date.formatted(.relative(presentation: .named)))"
    }
}

// MARK: - Section

/// A short heading above a rounded card of rows, with hairlines between rows. The heading and
/// the rows' text start at the same point.
struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
                .padding(.horizontal, Spacing.m)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                Group(subviews: content) { rows in
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        if index > 0 {
                            Divider().padding(.leading, Spacing.m)
                        }
                        row
                            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                            .padding(.horizontal, Spacing.m)
                    }
                }
            }
            // The app's one card style (lit and lifted under Cosmos).
            .glassCard(cornerRadius: 20)
        }
    }
}

// MARK: - Speed buttons

/// Choose which quick speed buttons the player's speed sheet shows (1 to 5 of them).
struct SpeedButtonsSettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        ScrollView {
            SettingsSection("Show in the player") {
                ForEach(AppSettings.speedPresets, id: \.self) { speed in
                    let shown = settings.speedButtons.contains(speed)
                    let locked = shown ? settings.speedButtons.count == 1
                                       : settings.speedButtons.count >= AppSettings.maxSpeedButtons
                    Button {
                        settings.toggleSpeedButton(speed)
                    } label: {
                        HStack {
                            Text(TimeFormat.speed(speed))
                                .foregroundStyle(locked ? Theme.secondaryText : Color.primary)
                            Spacer()
                            if shown {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(locked)
                    .accessibilityAddTraits(shown ? .isSelected : [])
                }
            }
            .padding(.horizontal, Spacing.m)
            .padding(.top, Spacing.s)
            .padding(.bottom, Spacing.xl)
        }
        .background { ThemedPageBackground() }
        .navigationTitle("Speed Buttons")
        .navigationBarTitleDisplayMode(.inline)
    }
}
