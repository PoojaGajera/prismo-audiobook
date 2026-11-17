import SwiftUI

/// Launch moment: the prism glass fills the screen, the mascot pops in,
/// its headphones drop on, it winks, then everything dissolves into the library. No text.
struct SplashView: View {
    var onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var patternVisible = false
    @State private var mascotIn = false
    @State private var headphonesOn: CGFloat = 0
    @State private var leaving = false
    @State private var mood: MascotMood = .happy

    var body: some View {
        ZStack {
            PrismBackground(style: .splash)
                .opacity(patternVisible ? 1 : 0)

            // A soft pearly glow so the mascot reads against the pattern.
            RadialGradient(colors: [Theme.background.opacity(0.85), Theme.background.opacity(0)],
                           center: .center, startRadius: 10, endRadius: 260)
                .opacity(patternVisible ? 1 : 0)
                .ignoresSafeArea()

            // Just the mascot (the "Prismo" title and tagline were removed by request).
            MascotView(size: 170, mood: mood, headphones: true, headphonesProgress: headphonesOn)
                .scaleEffect(mascotIn ? 1 : 0.4)
                .opacity(mascotIn ? 1 : 0)
                .shadow(color: Theme.accent.opacity(0.25), radius: 24, y: 12)
                .accessibilityLabel("Prismo")
        }
        .scaleEffect(leaving ? 1.08 : 1)
        .opacity(leaving ? 0 : 1)
        .task { await run() }
    }

    private func run() async {
        if reduceMotion {
            patternVisible = true
            mascotIn = true
            headphonesOn = 1
            try? await Task.sleep(for: .milliseconds(900))
        } else {
            withAnimation(.easeOut(duration: 0.35)) { patternVisible = true }
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(.spring(duration: 0.6, bounce: 0.45)) { mascotIn = true }
            try? await Task.sleep(for: .milliseconds(450))
            withAnimation(.spring(duration: 0.55, bounce: 0.5)) { headphonesOn = 1 }
            try? await Task.sleep(for: .milliseconds(450))
            mood = .wink
            try? await Task.sleep(for: .milliseconds(750))
        }
        withAnimation(.easeInOut(duration: 0.45)) { leaving = true }
        try? await Task.sleep(for: .milliseconds(450))
        onFinished()
    }
}
