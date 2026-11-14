import SwiftUI

struct BookmarksView: View {
    @EnvironmentObject private var player: PlayerController
    @Environment(\.dismiss) private var dismiss

    @State private var editing: Bookmark?
    @State private var editText = ""

    private var bookmarks: [Bookmark] { player.book?.bookmarks ?? [] }

    var body: some View {
        NavigationStack {
            Group {
                if bookmarks.isEmpty {
                    ContentUnavailableView {
                        Label("No bookmarks", systemImage: "bookmark")
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
                                .tint(.orange)
                            }
                        }
                    }
                }
            }
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
                .foregroundStyle(.tint)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(TimeFormat.clock(bookmark.time))
                        .font(.headline.monospacedDigit())
                    if !bookmark.chapterTitle.isEmpty {
                        Text(bookmark.chapterTitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                if !bookmark.note.isEmpty {
                    Text(bookmark.note)
                        .font(.body)
                }
                Text(bookmark.createdAt, format: .dateTime.day().month().year().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }
}
