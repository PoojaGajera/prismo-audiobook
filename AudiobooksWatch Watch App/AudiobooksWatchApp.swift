import Combine
import SwiftUI

/// Apple Watch remote for the iPhone app: shows what's playing and controls it.
/// The audio plays on the iPhone (see `WatchBridge` in the iPhone app).
@main
struct AudiobooksWatchApp: App {
    @StateObject private var session = WatchSession.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(session)
                .onAppear { session.start() }
        }
    }
}
