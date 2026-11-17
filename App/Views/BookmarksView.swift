import SwiftUI

struct BookmarksView: View {
    @EnvironmentObject private var player: PlayerController
    @Environment(\.dismiss) private var dismiss
    /// The playing book's cover colours (set by the player).
    @Environment(\.coverTheme) private var theme

    @State private var editing: Bookmark?
    @State private var editText = ""

    private var bookmarks: [Bookmark] { player.book?.bookmarks ?? [] }

    var body: some View {
        NavigationStack {
            Group {
                if bookmarks.isEmpty {
                    ContentUnavailableView {
                        Label("No bookmarks yet", systemImage: "bookmark")
                            .font(Theme.title(.title3))
                    } description: {
                        Text("Tap the bookmark button in the player to save your place with an optional note.")
                    } actions: {
                        Button("Bookmark Current Position") { player.addBookmark() }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(bookmarks) { bookmark in
                            Button {
                                player.seek(to: bookmark.time)
                                dismiss()
                            } label: {
                                row(bookmark)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Theme.surface)
                            .swipeActions {
                                Button(role: .destructive) {
                                    player.deleteBookmarks([bookmark.id])
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    editText = bookmark.note
                                    editing = bookmark
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(theme.accent)
                            }
                        }
                    }
                    // Full-width rows on one plain surface, so a swipe (Delete / Edit) only ever
                    // reveals that surface, not the page's coloured background (pink smoke, sky).
                    .listStyle(.plain)
                    .listRowSeparatorTint(Theme.hairline)
                }
            }
            .scrollContentBackground(.hidden)
            .background { Theme.surface.ignoresSafeArea() }
            .navigationTitle("Bookmarks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { player.addBookmark() } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Bookmark current position")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Edit Note", isPresented: Binding(
                get: { editing != nil },
                set: { if !$0 { editing = nil } })) {
                TextField("Note", text: $editText)
                Button("Save") {
                    if let bookmark = editing { player.updateBookmark(bookmark.id, note: editText) }
                    editing = nil
                }
                Button("Cancel", role: .cancel) { editing = nil }
            }
        }
    }

    private func row(_ bookmark: Bookmark) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bookmark.fill")
                .foregroundStyle(Theme.readable(theme.accent, on: Color.white))
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(TimeFormat.clock(bookmark.time))
                        .font(Theme.title(.headline).monospacedDigit())
                    if !bookmark.chapterTitle.isEmpty {
                        Text(bookmark.chapterTitle)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(1)
                    }
                }
                if !bookmark.note.isEmpty {
                    Text(bookmark.note)
                        .font(.system(.body))
                }
                Text(bookmark.createdAt, format: .dateTime.day().month().year().hour().minute())
                    .font(.caption)
                    .foregroundStyle(Theme.tertiaryText)
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }
}
