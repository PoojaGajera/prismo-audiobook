import SwiftUI

/// What a finished book opens instead of the player: its cover and details, with Listen Again,
/// Mark as Unfinished and Edit. Reads the book live from the library, so edits show straight away.
struct FinishedBookView: View {
    let bookID: UUID

    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss

    @State private var editing = false

    private var book: Book? { library.book(id: bookID) }

    var body: some View {
        NavigationStack {
            Group {
                if let book {
                    ScrollView { content(book) }
                } else {
                    // Deleted meanwhile.
                    Color.clear.onAppear { dismiss() }
                }
            }
            .background { ThemedPageBackground() }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Edit") { editing = true }
                        .disabled(book == nil)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $editing) {
                if let book {
                    BookDetailsView(book: book)
                        .environmentObject(settings)
                        .tint(Theme.accent)
                }
            }
        }
    }

    private func content(_ book: Book) -> some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            CoverView(book: book, cornerRadius: 8, fullSize: true)
                .frame(width: 220, height: 220)
                .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(book.title)
                    .font(.title2.bold())
                Text(book.author)
                    .font(.body)
                    .foregroundStyle(Theme.secondaryText)
                if let series = book.series, !series.isEmpty {
                    Text(series)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
                Label("Finished", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.blush)
                    .padding(.top, Spacing.xs)
            }

            facts(book)

            if let summary = book.summary, !summary.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Description")
                        .font(.headline)
                    Text(summary)
                        .font(.body)
                        .foregroundStyle(Theme.secondaryText)
                }
            }

            if !book.hasAudio {
                Label("The audio was removed from this iPhone. Add the file again to listen again.",
                      systemImage: "speaker.slash")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            } else {
            VStack(spacing: Spacing.s) {
                Button { listenAgain(book) } label: {
                    Label("Listen Again", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Theme.accent, in: Capsule())
                        .foregroundStyle(Theme.onAccent)
                }
                Button { markUnfinished(book) } label: {
                    Text("Mark as Unfinished")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            .buttonStyle(.plain)
            .padding(.top, Spacing.xs)
            }
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.m)
    }

    /// Length, genre, year and publisher, as a small card of label/value rows (only those known).
    private func facts(_ book: Book) -> some View {
        let rows: [(String, String)] = [
            ("Length", TimeFormat.short(book.duration)),
            ("Chapters", book.chapters.count > 1 ? "\(book.chapters.count)" : ""),
            ("Genre", book.genre ?? ""),
            ("Year", book.year ?? ""),
            ("Publisher", book.publisher ?? ""),
        ].filter { !$0.1.isEmpty }
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(alignment: .firstTextBaseline, spacing: Spacing.m) {
                    Text(row.0)
                        .foregroundStyle(Theme.secondaryText)
                    Spacer(minLength: Spacing.m)
                    Text(row.1)
                        .multilineTextAlignment(.trailing)
                }
                .font(.subheadline)
                .padding(.vertical, Spacing.s)
                if index < rows.count - 1 { Divider() }
            }
        }
        .padding(.horizontal, Spacing.m)
        .glassCard(cornerRadius: 20)
    }

    /// Starts the book again from the beginning and opens the player. It moves back to the library.
    private func listenAgain(_ book: Book) {
        if player.book?.id == book.id {
            player.resetProgress()
            player.play()
        } else {
            library.resetProgress(book)
            if let fresh = library.book(id: book.id) { player.load(fresh, autoplay: true) }
        }
        dismiss()
        router.showPlayer = true
    }

    private func markUnfinished(_ book: Book) {
        if player.book?.id == book.id { player.setFinished(false) } else { library.setFinished(book, false) }
        dismiss()
    }
}
