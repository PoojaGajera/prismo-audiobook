import SwiftUI

/// The app's tabs.
enum AppTab: String, CaseIterable {
    case library, activity, settings

    var title: String {
        switch self {
        case .library: "Library"
        case .activity: "Activity"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .library: "books.vertical.fill"
        case .activity: "sparkles"
        case .settings: "gearshape.fill"
        }
    }
}

/// Library, Activity and Settings, with a tab bar at the bottom. The now-playing panel floats over
/// everything: collapsed it's a small card just above the tab bar; open it covers the screen.
struct RootView: View {
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var settings: AppSettings
    /// Sheets with a page background are open: the pages underneath pause their animations.
    @ObservedObject private var modal = ModalPresence.shared
    /// Tabs are only built once they've been opened (the library is all that's needed at launch).
    @State private var visited: Set<AppTab> = [.library]

    var body: some View {
        ZStack {
            page(.library) { LibraryView() }
            if visited.contains(.activity) {
                page(.activity) { ActivityView() }
            }
            if visited.contains(.settings) {
                page(.settings) {
                    SettingsView(embedded: true)
                        .environmentObject(settings)
                }
            }
        }
        // A tap anywhere: if it's on a dandelion (Matcha Latte), it bursts into seeds.
        .simultaneousGesture(
            SpatialTapGesture(coordinateSpace: .global).onEnded { value in
                if !router.showPlayer { ParticleField.shared.tap(at: value.location) }
            }
        )
        .overlay(alignment: .bottom) { TabDock() }
        // Mini player ⇄ full player (sheets still present on top of it).
        .overlay { NowPlayingPanel() }
        .onChange(of: router.tab) { _, tab in visited.insert(tab) }
        // The open player's book card (tap the cover, or More → About This Book).
        .bookCard($router.bookCard) { _ in [] }
    }

    /// Every opened tab stays alive (keeping its scroll position); only the selected one shows.
    private func page<Content: View>(_ tab: AppTab, @ViewBuilder content: () -> Content) -> some View {
        let selected = router.tab == tab
        return content()
            // Hidden pages (and pages under the open player) pause their moving backgrounds and
            // animations, so only what's on screen uses the CPU.
            .environment(\.pageIsVisible, selected && !router.showPlayer && modal.count == 0)
            .opacity(selected ? 1 : 0)
            .allowsHitTesting(selected)
            .accessibilityHidden(!selected)
    }
}

/// The row of tab buttons (transparent; `TabDock` gives it a surface).
struct AppTabBar: View {
    /// Height of the tab row above the home indicator: 8 pt of space on top, then 56 pt of buttons.
    static let height: CGFloat = 64
    private static let topSpace: CGFloat = Spacing.xs
    private static let buttonHeight: CGFloat = 56

    @EnvironmentObject private var router: AppRouter
    /// Observed so the tab bar picks up a new app theme straight away.
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                let selected = router.tab == tab
                Button {
                    if router.tab != tab {
                        withAnimation(.snappy(duration: 0.25)) { router.tab = tab }
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 20, weight: .semibold))
                            .symbolEffect(.bounce, options: .nonRepeating, value: selected)
                            .frame(height: 24)
                        Text(tab.title)
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(selected ? Theme.accent : Theme.secondaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.buttonHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.horizontal, Spacing.m)
        .padding(.top, Self.topSpace)
        .frame(height: Self.height, alignment: .top)
        .sensoryFeedback(.selection, trigger: router.tab)
    }
}

/// The tab bar on its surface. With nothing playing it has a hairline along the top; with a book
/// loaded the mini bar sits on it and the mini bar's progress line is the divider.
private struct TabDock: View {
    @ObservedObject private var presence = NowPlayingPresence.shared
    /// Observed so the dock picks up a new app theme straight away.
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        let hasBook = presence.hasBook
        AppTabBar()
            .frame(maxWidth: .infinity)
            .background {
                Theme.surface
                    .overlay(alignment: .top) { Theme.hairline.frame(height: 0.75).opacity(hasBook ? 0 : 1) }
                    .shadow(color: .black.opacity(hasBook ? 0 : 0.08), radius: 12, y: -2)
                    .ignoresSafeArea(edges: .bottom)
            }
    }
}

/// Space at the bottom of each page for the tab bar, plus the floating mini bar while a book is
/// loaded. Pages add it with `.safeAreaInset(edge: .bottom)`.
struct BottomBarSpace: View {
    @ObservedObject private var presence = NowPlayingPresence.shared

    var body: some View {
        Color.clear.frame(height: AppTabBar.height
                          + (presence.hasBook ? NowPlayingPanel.miniBarHeight + NowPlayingPanel.miniGap : 0))
    }
}
