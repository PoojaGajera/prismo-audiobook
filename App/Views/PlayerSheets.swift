import SwiftUI
import UIKit

// The player's small sheets (speed, more, bookmark saved). They all share one look:
// a solid background tinted by the cover, a small round close button on the left, a centred
// title, then solid chips and buttons in the cover's colours. No glass or blur. Each sheet is
// exactly as tall as its content (no empty space at the bottom).

// MARK: - Shared pieces

/// The frame every player sheet uses. It sizes the sheet to fit its content.
struct PlayerSheetScaffold<Trailing: View, Content: View>: View {
    let title: String
    let trailing: () -> Trailing
    let content: () -> Content

    @Environment(\.dismiss) private var dismiss
    @State private var contentHeight: CGFloat = 0

    init(title: String,
         @ViewBuilder trailing: @escaping () -> Trailing,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.trailing = trailing
        self.content = content
    }

    var body: some View {
        VStack(spacing: Spacing.l) {
            ZStack {
                Text(title)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                HStack {
                    ChipIconButton(systemName: "xmark", label: "Close", size: ChipIconButton.small) { dismiss() }
                    Spacer()
                    trailing()
                }
            }
            content()
        }
        .padding(.horizontal, Spacing.l)
        .padding(.top, Spacing.m)
        .padding(.bottom, Spacing.s)
        // Measure the content at its natural height, and make the sheet exactly that tall.
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .presentationDetents([.height(max(contentHeight, 120))])
    }
}

extension PlayerSheetScaffold where Trailing == EmptyView {
    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, trailing: { EmptyView() }, content: content)
    }
}

/// A round, solid icon button (close, chevron, −/+). The tap area is always at least 44 points.
struct ChipIconButton: View {
    /// The size used inside sheets (close, settings, − and +).
    static let small: CGFloat = 30

    var systemName: String
    var label: String
    var size: CGFloat = 36
    var action: () -> Void

    @Environment(\.coverTheme) private var theme

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(theme.onChip)
                .frame(width: size, height: size)
                .background(theme.chip, in: Circle())
                .frame(width: max(44, size), height: max(44, size))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// A solid capsule button. `prominent` fills it with the cover's accent (the main action, or
/// the selected choice); otherwise it uses the soft chip colour.
struct SheetButton: View {
    var title: String
    var systemImage: String? = nil
    var prominent = false
    var destructive = false
    var height: CGFloat = 48
    var font: Font = .body.weight(.semibold)
    var action: () -> Void

    @Environment(\.coverTheme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(font)
            .foregroundStyle(prominent ? Color.white : (destructive ? Color.red : theme.onChip))
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(prominent ? theme.accent : theme.chip, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Speed

struct SpeedSheet: View {
    /// Opens the playback settings (where the speed buttons are chosen).
    var onSettings: () -> Void

    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.coverTheme) private var theme

    var body: some View {
        PlayerSheetScaffold(title: "Playback Speed") {
            ChipIconButton(systemName: "gearshape", label: "Playback settings",
                           size: ChipIconButton.small, action: onSettings)
        } content: {
            VStack(spacing: Spacing.m) {
                Text(TimeFormat.speed(player.speed))
                    .font(.system(size: 40, weight: .bold).monospacedDigit())
                    .contentTransition(.numericText(value: player.speed))
                    .animation(.snappy, value: player.speed)

                // − slider +, all on one centre line.
                HStack(alignment: .center, spacing: Spacing.xs) {
                    ChipIconButton(systemName: "minus", label: "Slower", size: ChipIconButton.small) {
                        player.setSpeed(max(0.5, player.speed - 0.05))
                    }
                    Slider(value: Binding(get: { player.speed }, set: { player.setSpeed($0) }),
                           in: 0.5...4.0, step: 0.05)
                        .tint(theme.accent)
                    ChipIconButton(systemName: "plus", label: "Faster", size: ChipIconButton.small) {
                        player.setSpeed(min(4, player.speed + 0.05))
                    }
                }

                // The quick speeds chosen in Settings → Playback Speed → Speed buttons.
                HStack(spacing: Spacing.xs) {
                    ForEach(settings.speedButtons, id: \.self) { preset in
                        SheetButton(title: TimeFormat.speed(preset),
                                    prominent: abs(player.speed - preset) < 0.001,
                                    height: 36,
                                    font: .subheadline.weight(.semibold).monospacedDigit()) {
                            player.setSpeed(preset)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - More

struct MoreSheet: View {
    /// Opens one of the player's other sheets.
    var onSelect: (PlayerView.PlayerSheet) -> Void

    @EnvironmentObject private var player: PlayerController
    @Environment(\.coverTheme) private var theme

    var body: some View {
        PlayerSheetScaffold(title: "More") {
            VStack(spacing: 0) {
                row("Edit Details", systemImage: "square.and.pencil") { onSelect(.editDetails) }
                divider
                row("Bookmarks", systemImage: "bookmark",
                    detail: (player.book?.bookmarks.count).map { $0 > 0 ? "\($0)" : "" }) { onSelect(.bookmarks) }
                divider
                row("Playback Settings", systemImage: "gearshape") { onSelect(.settings) }
            }
            .background(theme.chip, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(theme.onChip.opacity(0.1))
            .frame(height: 1)
            .padding(.leading, 56)
    }

    private func row(_ title: String, systemImage: String, detail: String? = nil,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.s) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .frame(width: 28)
                Text(title)
                    .font(.body.weight(.medium))
                Spacer()
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(theme.onChip.opacity(0.6))
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(theme.onChip.opacity(0.4))
            }
            .foregroundStyle(theme.onChip)
            .padding(.horizontal, Spacing.m)
            .frame(height: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Bookmark saved

/// Shown after tapping the bookmark chip: where it was saved, an optional note, and a way to
/// see all bookmarks. The note is kept however the sheet is closed.
struct BookmarkSavedSheet: View {
    let bookmark: Bookmark
    var onSeeAll: () -> Void

    @EnvironmentObject private var player: PlayerController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.coverTheme) private var theme
    @State private var note = ""
    @State private var noteSaved = false

    var body: some View {
        PlayerSheetScaffold(title: "Bookmark Saved") {
            VStack(spacing: Spacing.m) {
                HStack(spacing: Spacing.s) {
                    Image(systemName: "bookmark.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(theme.accent, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("At \(TimeFormat.clock(bookmark.time))")
                            .font(.headline.monospacedDigit())
                        if !bookmark.chapterTitle.isEmpty {
                            Text(bookmark.chapterTitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }

                TextField("Add a note (optional)", text: $note, axis: .vertical)
                    .lineLimit(1...3)
                    .padding(.horizontal, Spacing.m)
                    .padding(.vertical, Spacing.s)
                    .frame(minHeight: 48)
                    .background(theme.chip, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                HStack(spacing: Spacing.xs) {
                    SheetButton(title: "See Bookmarks") {
                        saveNote()
                        onSeeAll()
                    }
                    SheetButton(title: "Done", prominent: true) {
                        saveNote()
                        dismiss()
                    }
                }
            }
        }
        .onDisappear(perform: saveNote)
    }

    private func saveNote() {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !noteSaved else { return }
        noteSaved = true
        player.updateBookmark(bookmark.id, note: trimmed)
    }
}
