import SwiftUI

@main
struct AudiobookApp: App {
    @StateObject private var library = LibraryStore.shared
    @StateObject private var player = PlayerController.shared
    @StateObject private var settings = AppSettings.shared
    @StateObject private var router = AppRouter.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environmentObject(library)
                .environmentObject(player)
                .environmentObject(settings)
                .environmentObject(router)
                .tint(.orange)
                .onOpenURL { url in
                    if url.isFileURL {
                        Task { await library.importOpenedFile(url) }
                    } else if url.scheme == SharedConfig.urlScheme, player.book != nil {
                        router.showPlayer = true
                    }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { player.savePosition() }
        }
    }
}

/// Simple app-wide navigation state (lets the widget open the player).
@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()
    @Published var showPlayer = false
}
