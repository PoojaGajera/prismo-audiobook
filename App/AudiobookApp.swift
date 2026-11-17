import SwiftUI
import UIKit

@main
struct AudiobookApp: App {
    @StateObject private var library = LibraryStore.shared
    @StateObject private var player = PlayerController.shared
    @StateObject private var settings = AppSettings.shared
    @StateObject private var router = AppRouter.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSplash = true

    init() {
        Self.styleNavigationBars()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                if showSplash {
                    SplashView { showSplash = false }
                        .zIndex(1)
                }
            }
                .environmentObject(library)
                .environmentObject(player)
                .environmentObject(settings)
                .environmentObject(router)
                .tint(Theme.accent)
                // Light / dark / automatic, from Settings → Appearance.
                .onAppear {
                    settings.applyAppearance()
                    // One spelling per name in found chapter titles ("Bri", "Bree" → "Brie").
                    ChapterScanner.shared.tidyChapterNames()
                    // Chapter searches that were running when the app was closed carry on.
                    ChapterScanner.shared.resumeInterrupted()
                    // The Apple Watch remote.
                    WatchBridge.shared.start()
                }
                .onOpenURL { url in
                    if url.isFileURL {
                        Task { await library.importOpenedFile(url) }
                    } else if url.scheme == SharedConfig.urlScheme, player.book != nil {
                        router.tab = .library
                        router.showPlayer = true
                    }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                player.savePosition(markPlayed: player.isPlaying)
                player.refreshWidget()
            }
            if phase == .active {
                settings.applyAppearance()
                Task { await FolderSync.shared.sync() }
                // Looks up books that haven't been yet (new, or missed while offline).
                MetadataEnricher.shared.enqueue(library.books)
                // Local and quick: chapter names still showing raw file names.
                for book in library.books { library.tidyChapterTitles(book.id) }
            }
        }
    }

    /// Navigation titles in the system font.
    private static func styleNavigationBars() {
        // Apple's default font (SF Pro) at the standard sizes, a little bolder.
        func font(_ style: UIFont.TextStyle, _ weight: UIFont.Weight) -> UIFont {
            UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: style).pointSize, weight: weight)
        }
        let appearance = UINavigationBar.appearance()
        appearance.largeTitleTextAttributes = [.font: font(.largeTitle, .bold)]
        appearance.titleTextAttributes = [.font: font(.headline, .semibold)]
    }
}

/// Simple app-wide navigation state (lets the widget open the player).
@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()
    @Published var showPlayer = false
    /// The selected tab (Library or Activity).
    @Published var tab: AppTab = .library
    /// A book whose details card is shown over everything (the player's More → About This Book).
    /// The library shows its own (with the book's menu); see `BookCard`.
    @Published var bookCard: UUID?
    /// Bumped by Settings → Import Audiobooks: the library opens the Files picker.
    @Published var importRequest = 0
}
