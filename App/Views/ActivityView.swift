import SwiftUI
import Charts

/// The Activity tab, in the Cosmos theme: your listener level (a planet you can poke), today,
/// your streak and week, a listening chart you can switch between week, month and year, this
/// month's three challenges, the year's reading goal, and the trophy shelf.
/// Built from `ListeningLog` (sessions recorded by the player) and the library.
struct ActivityView: View {
    @ObservedObject private var log = ListeningLog.shared
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: AppSettings

    @AppStorage(ActivityKeys.dailyGoal) private var dailyGoal = 30
    @AppStorage(ActivityKeys.yearlyGoal) private var yearlyGoal = 12

    @State private var showLevels = false
    @State private var showGoals = false

    var body: some View {
        let stats = ActivityStats(log: log, books: library.books, dailyGoalMinutes: dailyGoal)
        let track = LevelTrack.cosmos
        let earnedNow = Challenge.monthly.filter { $0.progress(stats) >= $0.target }.map { $0.key(stats) }

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    Text("Activity")
                        .font(Theme.title(.largeTitle))
                        .padding(.top, Spacing.s)
                        .padding(.bottom, Spacing.xs)
                        .accessibilityAddTraits(.isHeader)

                    LevelHeroCard(track: track, lifetime: stats.lifetimeSeconds) { showLevels = true }

                    TodayCard(stats: stats, dailyGoal: dailyGoal) { showGoals = true }

                    ListeningCard(stats: stats, dailyGoal: dailyGoal)

                    ChallengesCard(stats: stats, earnedCount: log.earnedChallenges.count)

                    YearGoalCard(stats: stats, yearlyGoal: yearlyGoal) { showGoals = true }

                    TrophiesCard(trophies: Trophy.all(stats, challengesEarned: log.earnedChallenges.count))
                }
                .padding(.horizontal, Spacing.m)
                .padding(.bottom, Spacing.xl)
            }
            .scrollIndicators(.hidden)
            .background { PrismBackground(style: .plain) }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) { BottomBarSpace() }
        }
        .id(settings.playerBackground)
        .task(id: earnedNow) { log.markEarned(earnedNow) }
        .sheet(isPresented: $showLevels) {
            LevelsSheet(lifetime: stats.lifetimeSeconds)
                .environmentObject(settings)
                .tint(Theme.accent)
        }
        .sheet(isPresented: $showGoals) {
            GoalsSheet(dailyGoal: $dailyGoal, yearlyGoal: $yearlyGoal)
                .tint(Theme.accent)
        }
    }
}

/// UserDefaults keys for the Activity page's choices.
enum ActivityKeys {
    static let dailyGoal = "activity.dailyGoalMinutes"
    static let yearlyGoal = "activity.yearlyBooksGoal"
}

// MARK: - Building blocks

/// The Activity page's card: a solid surface with a hairline edge, a short title and an optional
/// note on the right.
private struct ActivityCard<Content: View>: View {
    var title: String?
    var trailing: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            if let title {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: Spacing.xs)
                    if let trailing {
                        Text(trailing)
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            }
            content
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 22)
    }
}

/// Cards that open a sheet shrink slightly while pressed.
struct ActivityPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}

/// A ring that fills to `value` (0…1).
struct ProgressRing<RingLabel: View>: View {
    var value: Double
    var color: Color
    var lineWidth: CGFloat = 10
    @ViewBuilder var label: RingLabel

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.07), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.003, min(1, value)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(duration: 0.8, bounce: 0.2), value: value)
            label
        }
    }
}

// MARK: - Planet

/// A level as a little planet: a glossy sphere in the level's colour, a ring from Orbit upwards,
/// and a tiny moon circling it. Tap it and it bounces and throws off a few sparkles.
/// Holds still with Reduce Motion or with animations off in Settings.
struct PlanetBadge: View {
    let level: ListenerLevel
    var size: CGFloat = 80
    /// Index on the ladder (bigger planets get a ring and a faster moon).
    var index: Int = 0
    var locked = false
    var interactive = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.pageIsVisible) private var pageIsVisible
    @State private var bounce = false
    @State private var sparkleBurst = 0
    private static let start = Date()

    private var moving: Bool { Theme.motionEnabled && !reduceMotion && !locked && pageIsVisible }

    var body: some View {
        let color = locked ? Theme.Activity.slate : level.color
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !moving)) { context in
            let t = context.date.timeIntervalSince(Self.start)
            // The moon's angle (one lap every ~6 s), and the planet's slow breathing.
            let angle = t * (0.9 + Double(index) * 0.08)
            let breathe = moving ? 1 + 0.02 * sin(t * 1.3) : 1
            let moonX = cos(angle) * size * 0.62
            let moonY = sin(angle) * size * 0.22
            let moonInFront = sin(angle) > 0

            ZStack {
                if !moonInFront { moon(color).offset(x: moonX, y: moonY) }

                if index >= 3 {
                    Ellipse()
                        .strokeBorder(color.opacity(locked ? 0.25 : 0.55), lineWidth: size * 0.05)
                        .frame(width: size * 1.5, height: size * 0.46)
                        .rotationEffect(.degrees(-14))
                }

                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [color.opacity(0.75), color, color.opacity(0.85)],
                                             center: UnitPoint(x: 0.35, y: 0.3),
                                             startRadius: 0, endRadius: size * 0.7))
                    // A soft highlight, like light from one side.
                    Circle()
                        .fill(RadialGradient(colors: [.white.opacity(locked ? 0.15 : 0.45), .clear],
                                             center: UnitPoint(x: 0.3, y: 0.25),
                                             startRadius: 0, endRadius: size * 0.45))
                    Image(systemName: level.symbol)
                        .font(.system(size: size * 0.38, weight: .semibold))
                        .foregroundStyle(.white.opacity(locked ? 0.6 : 1))
                        .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
                }
                .frame(width: size, height: size)
                .scaleEffect(breathe * (bounce ? 1.12 : 1))
                .shadow(color: color.opacity(locked ? 0 : 0.45), radius: size * 0.16, y: size * 0.06)

                if moonInFront { moon(color).offset(x: moonX, y: moonY) }

                SparkleBurst(trigger: sparkleBurst, color: color, radius: size * 0.75)
            }
            .frame(width: size * 1.6, height: size * 1.1)
        }
        .contentShape(Circle().scale(0.8))
        .onTapGesture {
            guard interactive, !locked else { return }
            sparkleBurst += 1
            withAnimation(.spring(duration: 0.25, bounce: 0.6)) { bounce = true }
            withAnimation(.spring(duration: 0.5, bounce: 0.5).delay(0.12)) { bounce = false }
        }
        .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: sparkleBurst)
        .accessibilityHidden(true)
    }

    private func moon(_ color: Color) -> some View {
        Circle()
            .fill(RadialGradient(colors: [.white, color.opacity(0.6)],
                                 center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.1))
            .frame(width: size * 0.17, height: size * 0.17)
            .opacity(locked ? 0 : 1)
    }
}

/// Six little sparkles that fly out from the centre and fade, each time `trigger` changes.
private struct SparkleBurst: View {
    let trigger: Int
    let color: Color
    let radius: CGFloat

    @State private var shown: Int?

    var body: some View {
        ZStack {
            if let shown {
                ForEach(0..<6, id: \.self) { i in
                    let angle = Double(i) / 6 * 2 * .pi - .pi / 2
                    Image(systemName: i % 2 == 0 ? "sparkle" : "star.fill")
                        .font(.system(size: i % 2 == 0 ? 11 : 7, weight: .bold))
                        .foregroundStyle(i % 3 == 0 ? Theme.Activity.gold : color)
                        .modifier(Fly(angle: angle, radius: radius))
                        .id("\(shown)-\(i)")
                }
            }
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) { _, _ in
            shown = trigger
            Task {
                try? await Task.sleep(for: .seconds(0.8))
                if shown == trigger { shown = nil }
            }
        }
    }

    private struct Fly: ViewModifier {
        let angle: Double
        let radius: CGFloat
        @State private var out = false

        func body(content: Content) -> some View {
            content
                .offset(x: out ? cos(angle) * radius : 0, y: out ? sin(angle) * radius : 0)
                .opacity(out ? 0 : 1)
                .scaleEffect(out ? 0.5 : 1)
                .onAppear { withAnimation(.easeOut(duration: 0.7)) { out = true } }
        }
    }
}

// MARK: - Level

private struct LevelHeroCard: View {
    let track: LevelTrack
    let lifetime: Double
    let onOpen: () -> Void

    var body: some View {
        let index = track.levelIndex(for: lifetime)
        let level = track.levels[index]
        let next = track.levels.indices.contains(index + 1) ? track.levels[index + 1] : nil
        let hours = lifetime / 3600
        let fraction = next.map { (hours - level.hours) / ($0.hours - level.hours) } ?? 1

        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(spacing: Spacing.s) {
                // The planet reacts to taps on its own; the rest of the card opens the levels.
                PlanetBadge(level: level, size: 72, index: index)
                    .frame(width: 104)

                Button(action: onOpen) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("LEVEL \(index + 1)")
                                .font(.caption2.weight(.bold))
                                .tracking(1.4)
                                .foregroundStyle(Theme.readable(level.color))
                            Text(level.name)
                                .font(Theme.title(.title3))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text(level.tagline)
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                                .lineLimit(1)
                        }
                        Spacer(minLength: Spacing.xs)
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(ActivityFormat.hours(lifetime))
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text("listened")
                                .font(.caption2)
                                .foregroundStyle(Theme.secondaryText)
                        }
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.tertiaryText)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(ActivityPressStyle())
                .accessibilityLabel("Level \(index + 1), \(level.name), \(ActivityFormat.hours(lifetime)) listened")
                .accessibilityHint("Shows every level")
            }

            // The way to the next level, as a little orbit: the planet dot moves along it.
            if let next {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    GeometryReader { geo in
                        let x = max(6, geo.size.width * min(1, max(0, fraction)))
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.07))
                            Capsule()
                                .fill(LinearGradient(colors: [level.color, next.color], startPoint: .leading, endPoint: .trailing))
                                .frame(width: x)
                            Circle()
                                .fill(.white)
                                .frame(width: 10, height: 10)
                                .shadow(color: next.color.opacity(0.6), radius: 3)
                                .offset(x: x - 7)
                        }
                        .animation(.spring(duration: 0.8, bounce: 0.2), value: fraction)
                    }
                    .frame(height: 8)
                    HStack {
                        Text("\(ActivityFormat.hours(next.hours * 3600 - lifetime)) to \(next.name)")
                        Spacer()
                        Label(next.name, systemImage: next.symbol)
                            .labelStyle(.iconOnly)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.readable(next.color))
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(Spacing.m)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Theme.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(LinearGradient(colors: [level.color.opacity(0.18), level.color.opacity(0.03)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(level.color.opacity(0.3), lineWidth: 1)
        }
        .shadow(color: level.color.opacity(0.14), radius: 14, y: 6)
    }
}

// MARK: - Today, streak, week

/// Today's listening against the daily goal, in one row: the mascot in a ring (sleepy, listening,
/// excited), the time, and how much is left. Tap to change the goal.
private struct TodayCard: View {
    let stats: ActivityStats
    let dailyGoal: Int
    let onEditGoal: () -> Void

    var body: some View {
        let today = stats.todaySeconds
        let goal = Double(dailyGoal) * 60
        let done = today >= goal
        let left = max(0, goal - today)

        Button(action: onEditGoal) {
            HStack(spacing: Spacing.m) {
                ProgressRing(value: today / goal, color: done ? Theme.Activity.gold : Theme.accent, lineWidth: 6) {
                    MascotView(size: 36, mood: done ? .excited : (today > 0 ? .listening : .sleepy),
                               headphones: today > 0)
                }
                .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 2) {
                    Text("TODAY")
                        .font(.caption2.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(Theme.secondaryText)
                    Text(done ? "Goal reached!" : ActivityFormat.duration(today))
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(done ? "\(dailyGoal) min goal" : "\(ActivityFormat.duration(left)) to your \(dailyGoal) min goal")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer(minLength: Spacing.xs)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.tertiaryText)
            }
            .padding(Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(ActivityPressStyle())
        .accessibilityLabel("Today: \(ActivityFormat.duration(today)) of \(dailyGoal) minutes")
        .accessibilityHint("Change your goals")
    }
}

// MARK: - Listening (week / month / year)

private struct ListeningCard: View {
    let stats: ActivityStats
    let dailyGoal: Int

    enum Range: String, CaseIterable { case week = "Week", month = "Month", year = "Year" }
    @AppStorage("activity.listeningRange") private var rangeRaw = Range.week.rawValue

    var body: some View {
        let range = Range(rawValue: rangeRaw) ?? .week
        let days: [(day: Date, seconds: Double)] = switch range {
        case .week: (0..<7).map { offset in
            let day = stats.calendar.date(byAdding: .day, value: offset, to: stats.week.start)!
            return (day: day, seconds: stats.seconds(on: day))
        }
        case .month: stats.recentDays(30)
        case .year: stats.recentDays(365)
        }
        let active = days.filter { $0.day <= stats.today && $0.seconds >= 60 }.count
        let total = days.reduce(0) { $0 + $1.seconds }

        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack {
                Text("Listening")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                RangePicker(selection: $rangeRaw)
            }

            HStack(alignment: .firstTextBaseline, spacing: Spacing.l) {
                figure(ActivityFormat.duration(total), "listened")
                figure("\(active)", active == 1 ? "active day" : "active days")
                if active > 0 {
                    figure(ActivityFormat.duration(total / Double(active)), "per day")
                }
            }

            Group {
                switch range {
                case .week: DayBars(days: days, goalMinutes: dailyGoal, stats: stats, labelEvery: 1)
                case .month: DayBars(days: days, goalMinutes: dailyGoal, stats: stats, labelEvery: 7)
                case .year: YearHeatmap(stats: stats)
                }
            }
            .animation(.snappy, value: rangeRaw)
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 22)
    }

    private func figure(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(Theme.title(.title3))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A small pill picker: Week · Month · Year.
private struct RangePicker: View {
    @Binding var selection: String
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ListeningCard.Range.allCases, id: \.rawValue) { option in
                let selected = option.rawValue == selection
                Button {
                    withAnimation(.snappy(duration: 0.25)) { selection = option.rawValue }
                } label: {
                    Text(option.rawValue)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(selected ? Theme.onAccent : Theme.secondaryText)
                        .padding(.horizontal, Spacing.s)
                        .frame(height: 28)
                        .background {
                            if selected {
                                Capsule().fill(Theme.accent)
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.06), in: Capsule())
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// Minutes per day as bars, with the daily goal as a dashed line.
private struct DayBars: View {
    let days: [(day: Date, seconds: Double)]
    let goalMinutes: Int
    let stats: ActivityStats
    /// Label every Nth day (1 = weekday initials, 7 = dates a week apart).
    let labelEvery: Int

    var body: some View {
        let goal = Double(goalMinutes)
        Chart {
            ForEach(days, id: \.day) { entry in
                BarMark(x: .value("Day", entry.day, unit: .day),
                        y: .value("Minutes", entry.seconds / 60),
                        width: labelEvery == 1 ? .fixed(22) : .automatic)
                    .foregroundStyle(entry.seconds >= goal * 60 ? Theme.Activity.mint : Theme.accent.opacity(0.7))
                    .cornerRadius(4)
            }
            RuleMark(y: .value("Goal", goal))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(Theme.Activity.coral.opacity(0.8))
        }
        .chartXAxis {
            if labelEvery == 1 {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                }
            } else {
                AxisMarks(values: .stride(by: .day, count: labelEvery)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
                AxisValueLabel {
                    if let minutes = value.as(Double.self) { Text("\(Int(minutes))m") }
                }
            }
        }
        .frame(height: 140)
        .accessibilityLabel("Minutes listened each day; goal \(goalMinutes) minutes")
    }
}

/// The last 12 months as a calendar of listening days (one square per day, Monday first).
private struct YearHeatmap: View {
    let stats: ActivityStats

    private let cell: CGFloat = 11
    private let gap: CGFloat = 3

    var body: some View {
        let cal = stats.calendar
        let thisWeek = cal.dateInterval(of: .weekOfYear, for: stats.now)!.start
        let weeks: [Date] = (0..<53).reversed().map { cal.date(byAdding: .weekOfYear, value: -$0, to: thisWeek)! }

        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .top, spacing: gap) {
                VStack(spacing: gap) {
                    Color.clear.frame(height: 12)
                    ForEach(Array(["M", "", "W", "", "F", "", "S"].enumerated()), id: \.offset) { _, d in
                        Text(d)
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Theme.secondaryText)
                            .frame(width: 10, height: cell)
                    }
                }
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: gap) {
                        ForEach(weeks, id: \.self) { week in
                            VStack(spacing: gap) {
                                Text(cal.component(.day, from: week) <= 7 ? week.formatted(.dateTime.month(.abbreviated)) : "")
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundStyle(Theme.secondaryText)
                                    .fixedSize()
                                    .frame(width: cell, height: 12, alignment: .leading)
                                ForEach(0..<7, id: \.self) { d in
                                    let day = cal.date(byAdding: .day, value: d, to: week)!
                                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                        .fill(day > stats.today ? Color.clear : shade(stats.seconds(on: day)))
                                        .frame(width: cell, height: cell)
                                }
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .defaultScrollAnchor(.trailing)
            }
            HStack(spacing: 3) {
                Text("Less")
                ForEach([0, 600, 1800, 3600, 7200], id: \.self) { s in
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(shade(Double(s)))
                        .frame(width: 10, height: 10)
                }
                Text("More")
            }
            .font(.caption2)
            .foregroundStyle(Theme.secondaryText)
        }
        .frame(height: 140, alignment: .top)
        .accessibilityHidden(true)
    }

    private func shade(_ seconds: Double) -> Color {
        switch seconds {
        case ..<60: Color.primary.opacity(0.06)
        case ..<(20 * 60): Theme.accent.opacity(0.3)
        case ..<(45 * 60): Theme.accent.opacity(0.5)
        case ..<(90 * 60): Theme.accent.opacity(0.75)
        default: Theme.accent
        }
    }
}

// MARK: - Challenges

private struct ChallengesCard: View {
    let stats: ActivityStats
    let earnedCount: Int

    var body: some View {
        ActivityCard(title: "\(stats.now.formatted(.dateTime.month(.wide))) challenges",
                     trailing: earnedCount > 0 ? "\(earnedCount) won" : Challenge.monthly[0].timeLeft(stats)) {
            VStack(spacing: Spacing.s) {
                ForEach(Challenge.monthly) { challenge in
                    ChallengeRow(challenge: challenge, stats: stats)
                }
            }
        }
    }
}

private struct ChallengeRow: View {
    let challenge: Challenge
    let stats: ActivityStats

    var body: some View {
        let value = challenge.progress(stats)
        let done = value >= challenge.target

        HStack(spacing: Spacing.s) {
            ZStack {
                Circle().fill(challenge.color.opacity(done ? 1 : 0.14))
                Image(systemName: done ? "checkmark" : challenge.symbol)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(done ? Color.white : challenge.color)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(challenge.title)
                    .font(.subheadline.weight(.semibold))
                Text(done ? "Won!" : challenge.progressText(stats))
                    .font(.caption)
                    .foregroundStyle(done ? AnyShapeStyle(Theme.readable(challenge.color)) : AnyShapeStyle(Theme.secondaryText))
            }
            Spacer(minLength: Spacing.xs)
            ProgressRing(value: value / challenge.target, color: challenge.color, lineWidth: 4) {
                Text("\(Int((min(1, value / challenge.target) * 100).rounded()))")
                    .font(.system(size: 9, weight: .bold).monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
            }
            .frame(width: 32, height: 32)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(challenge.title): \(done ? "won" : challenge.progressText(stats))")
    }
}

// MARK: - Year goal

private struct YearGoalCard: View {
    let stats: ActivityStats
    let yearlyGoal: Int
    let onEdit: () -> Void

    var body: some View {
        let finished = stats.booksFinished(in: stats.year).count
        let fraction = Double(finished) / Double(max(1, yearlyGoal))
        let yearFraction = stats.now.timeIntervalSince(stats.year.start) / stats.year.duration
        let expected = Int((Double(yearlyGoal) * yearFraction).rounded())
        let onTrack = finished >= expected

        Button(action: onEdit) {
            HStack(spacing: Spacing.m) {
                ProgressRing(value: fraction, color: Theme.Activity.coral, lineWidth: 9) {
                    VStack(spacing: 0) {
                        Text("\(finished)")
                            .font(Theme.title(.title2))
                        Text("of \(yearlyGoal)")
                            .font(.caption2)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                .frame(width: 84, height: 84)

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(String(stats.yearNumber)) reading goal")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(finished >= yearlyGoal ? "Goal reached!"
                         : onTrack ? "On track" : "\(expected - finished) \(expected - finished == 1 ? "book" : "books") behind")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.readable(finished >= yearlyGoal ? Theme.Activity.gold : onTrack ? Theme.Activity.mint : Theme.Activity.coral))
                    HStack(spacing: Spacing.m) {
                        Label(ActivityFormat.duration(stats.seconds(in: stats.year)), systemImage: "headphones")
                        Label("\(stats.bestStreak) day best", systemImage: "flame")
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.top, 2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.tertiaryText)
            }
            .padding(Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(ActivityPressStyle())
        .accessibilityLabel("\(stats.yearNumber) reading goal: \(finished) of \(yearlyGoal) books")
        .accessibilityHint("Change your goals")
    }
}

// MARK: - Trophies

private struct TrophiesCard: View {
    let trophies: [Trophy]
    @State private var showAll = false
    @State private var wiggled: String?

    var body: some View {
        let earned = trophies.filter(\.isEarned).count
        let shown = showAll ? trophies : Array(trophies.prefix(6))

        ActivityCard(title: "Trophy shelf", trailing: "\(earned) of \(trophies.count)") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.xs), count: 3),
                      spacing: Spacing.m) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, trophy in
                    VStack(spacing: Spacing.xs) {
                        TrophyBadge(trophy: trophy, shape: index % 4)
                            .rotationEffect(.degrees(wiggled == trophy.id ? 8 : 0))
                            .onTapGesture {
                                guard trophy.isEarned else { return }
                                withAnimation(.spring(duration: 0.3, bounce: 0.7)) { wiggled = trophy.id }
                                withAnimation(.spring(duration: 0.5, bounce: 0.6).delay(0.15)) { wiggled = nil }
                            }
                        Text(trophy.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(trophy.isEarned ? Color.primary : Theme.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(trophy.detail)
                            .font(.caption2)
                            .foregroundStyle(Theme.tertiaryText)
                            .multilineTextAlignment(.center)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .sensoryFeedback(.impact(weight: .light), trigger: wiggled == trophy.id)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(trophy.title), \(trophy.detail). \(trophy.isEarned ? "Earned" : "\(Int(trophy.fraction * 100)) percent")")
                }
            }
            if trophies.count > 6 {
                Button(showAll ? "Show fewer" : "Show all \(trophies.count)") {
                    withAnimation(.snappy) { showAll.toggle() }
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
            }
        }
    }
}

/// A medal in the trophy's own colour. Four shapes take turns (circle, hexagon, seal, shield).
/// Earned: a glossy gradient with a white symbol. Not yet: a faint tint, the symbol in colour,
/// and an arc showing how close it is.
private struct TrophyBadge: View {
    let trophy: Trophy
    let shape: Int
    private let size: CGFloat = 60

    var body: some View {
        let color = trophy.color
        ZStack {
            if !trophy.isEarned {
                Circle()
                    .trim(from: 0, to: trophy.fraction)
                    .stroke(color.opacity(0.7), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: size + 10, height: size + 10)
            }
            medal
                .fill(trophy.isEarned
                      ? AnyShapeStyle(LinearGradient(colors: [color.opacity(0.8), color, color.opacity(0.7)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                      : AnyShapeStyle(color.opacity(0.14)))
                .frame(width: size, height: size)
            if trophy.isEarned {
                medal
                    .fill(LinearGradient(colors: [.white.opacity(0.45), .clear], startPoint: .top, endPoint: .center))
                    .frame(width: size, height: size)
                medal
                    .stroke(.white.opacity(0.5), lineWidth: 1.5)
                    .frame(width: size - 8, height: size - 8)
            }
            Image(systemName: trophy.symbol)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(trophy.isEarned ? Color.white : Theme.readable(color, ratio: 3))
                .shadow(color: .black.opacity(trophy.isEarned ? 0.15 : 0), radius: 1, y: 1)
        }
        .frame(width: size + 10, height: size + 10)
        .shadow(color: color.opacity(trophy.isEarned ? 0.4 : 0), radius: 8, y: 4)
    }

    private var medal: AnyShape {
        switch shape {
        case 1: AnyShape(PolygonShape(sides: 6))
        case 2: AnyShape(SealShape(points: 12))
        case 3: AnyShape(ShieldShape())
        default: AnyShape(Circle())
        }
    }
}

/// A regular polygon with `sides` sides, pointing up.
struct PolygonShape: Shape {
    var sides: Int
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        var p = Path()
        for i in 0..<sides {
            let a = Double(i) / Double(sides) * 2 * .pi - .pi / 2
            let pt = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

/// A scalloped seal (like a rosette) with `points` bumps.
struct SealShape: Shape {
    var points: Int
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.86
        var p = Path()
        let steps = points * 2
        for i in 0...steps {
            let a = Double(i) / Double(steps) * 2 * .pi - .pi / 2
            let r = i % 2 == 0 ? outer : inner
            let pt = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

/// A rounded shield.
struct ShieldShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + w * 0.12, y: rect.minY + h * 0.08))
        p.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY + h * 0.02), control: CGPoint(x: rect.minX + w * 0.3, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - w * 0.12, y: rect.minY + h * 0.08), control: CGPoint(x: rect.maxX - w * 0.3, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - w * 0.1, y: rect.midY), control: CGPoint(x: rect.maxX, y: rect.minY + h * 0.2))
        p.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.maxY), control: CGPoint(x: rect.maxX - w * 0.1, y: rect.maxY - h * 0.12))
        p.addQuadCurve(to: CGPoint(x: rect.minX + w * 0.1, y: rect.midY), control: CGPoint(x: rect.minX + w * 0.1, y: rect.maxY - h * 0.12))
        p.addQuadCurve(to: CGPoint(x: rect.minX + w * 0.12, y: rect.minY + h * 0.08), control: CGPoint(x: rect.minX, y: rect.minY + h * 0.2))
        p.closeSubpath()
        return p
    }
}
