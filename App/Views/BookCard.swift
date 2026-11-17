import SwiftUI
import PhotosUI

/// One action in a book's menu (the card's "…" button, and VoiceOver actions on library cards).
struct BookAction: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    var destructive = false
    let run: () -> Void

    init(_ title: String, _ systemImage: String, destructive: Bool = false, run: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.destructive = destructive
        self.run = run
    }
}

/// Opens the card for a book: without the full-screen cover's slide, since the card
/// animates itself in.
@MainActor
func showBookCard(_ id: UUID?, in binding: Binding<UUID?>) {
    var t = Transaction()
    t.disablesAnimations = true
    withTransaction(t) { binding.wrappedValue = id }
}

extension View {
    /// Shows `BookCard` for the book whose id is in `bookID`, over everything (it's a full-screen
    /// cover with a clear background, presented without the usual slide: the card animates itself).
    func bookCard(_ bookID: Binding<UUID?>, actions: @escaping (Book) -> [[BookAction]]) -> some View {
        fullScreenCover(isPresented: Binding(get: { bookID.wrappedValue != nil },
                                             set: { if !$0 { bookID.wrappedValue = nil } })) {
            if let id = bookID.wrappedValue {
                BookCard(bookID: id, actions: actions) {
                    var t = Transaction()
                    t.disablesAnimations = true
                    withTransaction(t) { bookID.wrappedValue = nil }
                }
                .environmentObject(LibraryStore.shared)
                .environmentObject(PlayerController.shared)
                .environmentObject(AppSettings.shared)
                .tint(Theme.accent)
                .presentationBackground(.clear)
            }
        }
    }
}

/// A book's details as a card that pops up over a dimmed screen, from the open player (tap the
/// cover, or More → About This Book): the cover (tap it to change it), title, author, progress,
/// a few facts and the description, all in one scrolling card. "…" holds Edit Details, Change
/// Cover and the book's other actions; ✕ (or a tap outside) closes it.
struct BookCard: View {
    let bookID: UUID
    var actions: (Book) -> [[BookAction]] = { _ in [] }
    let onClose: () -> Void

    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 0 = closed (the page turned away), 1 = open. Animated: the card turns in like a page.
    @State private var turn: Double = 0
    @State private var flipped = 0
    @State private var editing = false
    @State private var coverOptions = false
    @State private var findingCover = false
    @State private var photosShown = false
    @State private var photoItem: PhotosPickerItem?
    @State private var coverBump = 0

    var body: some View {
        ZStack {
            // A dim, blurred backdrop so the card stands clear of whatever is behind it.
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.45))
                .opacity(turn)
                .ignoresSafeArea()
                .onTapGesture(perform: close)
                .accessibilityLabel("Close")
                .accessibilityAddTraits(.isButton)

            if let book = library.book(id: bookID) {
                FlipCard(progress: turn, flat: reduceMotion, front: card(book))
                    .padding(.horizontal, Spacing.l)
                    // Clear of the screen's edges on every side.
                    .padding(.vertical, Spacing.xl + Spacing.m)
            }
        }
        .onDisappear { ModalPresence.shared.leave() }
        .onAppear {
            ModalPresence.shared.enter()
            flipped += 1
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.75, bounce: 0.15)) { turn = 1 }
        }
        .sheet(isPresented: $editing) {
            if let book = library.book(id: bookID) {
                BookDetailsView(book: book)
                    .environmentObject(settings)
                    .environmentObject(player)
                    .tint(Theme.accent)
            }
        }
        .sheet(isPresented: $findingCover) {
            if let book = library.book(id: bookID) {
                MetadataSearchView(title: Self.searchTitle(book), author: book.hasKnownAuthor ? book.author : nil,
                                   mode: .cover) { _, image in
                    if let image { setCover(image) }
                }
                .environmentObject(settings)
                .tint(Theme.accent)
            }
        }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.6), trigger: flipped)
        .confirmationDialog("Change Cover", isPresented: $coverOptions, titleVisibility: .visible) {
            Button("Find a Cover…") { findingCover = true }
            Button("Choose from Photos") { photosShown = true }
            Button("Cancel", role: .cancel) {}
        }
        .photosPicker(isPresented: $photosShown, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    setCover(image)
                }
                photoItem = nil
            }
        }
    }

    // MARK: - Card

    private func card(_ book: Book) -> some View {
        // Short books' cards fit as they are; longer ones scroll as a whole.
        ViewThatFits(in: .vertical) {
            cardContent(book)
            ScrollView {
                cardContent(book)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxWidth: 380)
        // Scrolling content stays inside the rounded corners (the paper's shadow isn't clipped).
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .background { CardPaper() }
        .overlay(alignment: .topTrailing) {
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Self.chipInk)
                    .frame(width: 32, height: 32)
                    .background(Self.chipTint.opacity(0.16), in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(Spacing.xs)
            .accessibilityLabel("Close")
        }
        // A white card in every theme, so everything on it (✕ included) is drawn in light mode.
        // (It used to be set before the ✕ was added, which left the ✕ white on white under Cosmos.)
        .environment(\.colorScheme, .light)
    }

    /// The card's colours follow the app theme: the accent for chips and the ✕ (fill), and a
    /// deeper shade of it for their text and icons (readable on the white card).
    static var chipTint: Color { Theme.accent }
    static var chipInk: Color { Theme.accentInk }

    private func cardContent(_ book: Book) -> some View {
        VStack(spacing: Spacing.m) {
            coverButton(book)

            VStack(spacing: Spacing.xxs) {
                Text(book.title)
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                if book.hasKnownAuthor {
                    Text(book.author)
                        .font(.subheadline)
                        .foregroundStyle(Color.primary.opacity(0.75))
                        .lineLimit(1)
                }
            }

            progress(book)

            facts(book)

            if let summary = book.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
                Text(summary)
                    .font(.subheadline)
                    .lineSpacing(3)
                    .foregroundStyle(Color.primary.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, Spacing.l)
        .padding(.top, Spacing.xl)
        .padding(.bottom, Spacing.l)
    }

    /// The cover; tap to change it. A small camera badge says so.
    private func coverButton(_ book: Book) -> some View {
        Button { coverOptions = true } label: {
            CoverView(book: book, cornerRadius: 18, fullSize: true)
                .frame(width: 188, height: 188)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 14, y: 8)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.onAccent)
                        .frame(width: 32, height: 32)
                        .background(Theme.accent, in: Circle())
                        .overlay { Circle().strokeBorder(Color.white, lineWidth: 2) }
                        .offset(x: 8, y: 8)
                }
                .id(coverBump)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
        .buttonStyle(ActivityPressStyle())
        .padding(.top, Spacing.xs)
        .accessibilityLabel("Cover")
        .accessibilityHint("Change the cover")
    }

    private func progress(_ book: Book) -> some View {
        Group {
            if book.isFinished {
                Label("Finished", systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.readable(Theme.Activity.mint))
            } else if book.position > 0 {
                VStack(spacing: 6) {
                    IridescentBar(value: book.progress, height: 4)
                        .frame(width: 180)
                    Text("\(Int(book.progress * 100))% · \(TimeFormat.short(book.remaining)) left")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color.primary.opacity(0.75))
                }
            } else {
                Text("Not started · \(TimeFormat.short(book.duration))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    /// The genre first, in the accent colour (or "Add Genre", which opens Edit Details), then year,
    /// series, length and chapters as plain chips. Missing ones are left out.
    private func facts(_ book: Book) -> some View {
        let genre = book.genre?.trimmingCharacters(in: .whitespaces) ?? ""
        let chips: [(String, String)] = [
            ("calendar", book.year ?? ""),
            ("books.vertical", book.series ?? ""),
            ("clock", TimeFormat.short(book.duration)),
            ("list.bullet", book.chapters.count > 1 ? "\(book.chapters.count) chapters" : ""),
        ].filter { !$0.1.trimmingCharacters(in: .whitespaces).isEmpty }

        return FlowLayout(spacing: 6) {
            Button { editing = true } label: {
                Label(genre.isEmpty ? "Add Genre" : genre, systemImage: genre.isEmpty ? "plus" : "theatermasks.fill")
                    .modifier(ChipText(weight: .semibold))
                    .background(Self.chipTint.opacity(genre.isEmpty ? 0.1 : 0.2), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Self.chipTint.opacity(0.5), lineWidth: genre.isEmpty ? 1 : 0)
                    }
                    .foregroundStyle(Self.chipInk)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(genre.isEmpty ? "Add a genre" : "Genre: \(genre)")

            ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                Label(chip.1, systemImage: chip.0)
                    .modifier(ChipText(weight: .medium))
                    .background(Self.chipTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(Self.chipInk)
            }
        }
    }

    // MARK: - Helpers

    private func close() {
        flipped += 1
        withAnimation(reduceMotion ? .easeIn(duration: 0.15) : .easeInOut(duration: 0.45)) { turn = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.15 : 0.45)) { onClose() }
    }

    /// Saves a new cover chosen by hand (the automatic lookup never replaces it).
    private func setCover(_ image: UIImage) {
        guard var book = library.book(id: bookID), library.writeCover(image, for: book) else { return }
        book.hasCover = true
        book.coverVersion = (book.coverVersion ?? 0) + 1
        book.coverOrigin = "user"
        library.saveDetails(book)
        withAnimation(.spring(duration: 0.4, bounce: 0.3)) { coverBump += 1 }
    }

    private static func searchTitle(_ book: Book) -> String {
        let author = book.hasKnownAuthor ? book.author : nil
        return TitleCleaner.searchCore(TitleCleaner.splitSeries(TitleCleaner.clean(book.title, author: author)).title)
    }
}

/// Lays its children out in rows, wrapping onto the next row when one is full, each row centred.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX + (bounds.width - row.width) / 2
            for index in row.items {
                let size = measure(subviews[index], width: bounds.width)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var items: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    /// A child's size, never wider than the row (a long chip wraps its text instead).
    private func measure(_ subview: LayoutSubview, width: CGFloat) -> CGSize {
        let ideal = subview.sizeThatFits(.unspecified)
        guard ideal.width > width, width.isFinite else { return ideal }
        return subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = measure(subviews[index], width: width)
            let extra = rows[rows.count - 1].items.isEmpty ? size.width : size.width + spacing
            if rows[rows.count - 1].width + extra > width, !rows[rows.count - 1].items.isEmpty {
                rows.append(Row())
            }
            let gap: CGFloat = rows[rows.count - 1].items.isEmpty ? 0 : spacing
            rows[rows.count - 1].items.append(index)
            rows[rows.count - 1].width += gap + size.width
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}

/// Flips the card over from right to left, like turning over a playing card: it starts face
/// down (`CardBack`), its right edge lifts towards you and sweeps over to the left, and the
/// front lands face up. Closing flips it back. With Reduce Motion it just fades.
private struct FlipCard<Front: View>: View, Animatable {
    var progress: Double
    var flat: Bool
    let front: Front

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let p = min(1, max(0, progress))
        // 180° = face down, 0° = face up.
        let angle = flat ? 0 : 180 * (1 - p)
        let faceUp = angle < 90
        front
            .opacity(faceUp ? 1 : 0)
            .overlay {
                CardBack()
                    // Drawn turned round, so it reads the right way while the card is face down.
                    .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                    .opacity(faceUp ? 0 : 1)
                    .allowsHitTesting(false)
            }
            // A slight lift mid-flip.
            .scaleEffect(flat ? 1 : 1 - 0.08 * sin(.pi * (1 - p)))
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), anchor: .center, perspective: 0.5)
            // Fades in at the very start of opening and out at the very end of closing.
            .opacity(flat ? p : min(1, p / 0.12))
    }
}

/// The back of the card, seen while it flips: plain white paper with a hairline edge (no colour).
private struct CardBack: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)
        shape
            .fill(Color.white)
            .overlay { shape.strokeBorder(Color.black.opacity(0.08), lineWidth: 1) }
            .shadow(color: .black.opacity(0.3), radius: 30, y: 14)
    }
}

/// The card's paper: white, with one soft wash of the theme's accent from the top-left corner
/// (only the accent: the lilac and pink washes read as purple in every theme), a fine accent edge
/// and a soft shadow.
private struct CardPaper: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)
        shape
            .fill(Color.white)
            .overlay {
                RadialGradient(colors: [Theme.accent.opacity(0.14), .clear],
                               center: .topLeading, startRadius: 0, endRadius: 340)
                    .clipShape(shape)
            }
            .overlay { shape.strokeBorder(Theme.accent.opacity(0.22), lineWidth: 1) }
            .shadow(color: .black.opacity(0.3), radius: 30, y: 14)
    }
}

/// A chip's label: small text that wraps onto a second line (or more) when it's long.
private struct ChipText: ViewModifier {
    var weight: Font.Weight

    func body(content: Content) -> some View {
        content
            .font(.caption.weight(weight))
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minHeight: 28)
    }
}
