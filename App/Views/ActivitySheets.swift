import SwiftUI

// MARK: - Listener levels

/// The Cosmos ladder: your planet on top, then every level as a planet along a dotted path.
/// Reached levels are lit (with a tick), the current one is the highlighted card, and the
/// ones ahead show their hours and how far away they are. No theme picker (Cosmos only).
struct LevelsSheet: View {
    let lifetime: Double
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let track = LevelTrack.cosmos
        let current = track.levelIndex(for: lifetime)
        let level = track.levels[current]

        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.l) {
                    VStack(spacing: Spacing.xs) {
                        PlanetBadge(level: level, size: 96, index: current)
                            .padding(.vertical, Spacing.s)
                        Text("LEVEL \(current + 1) OF \(track.levels.count)")
                            .font(.caption2.weight(.bold)).tracking(1.6)
                            .foregroundStyle(Theme.readable(level.color))
                        Text(level.name)
                            .font(Theme.title(.title))
                        Text(level.tagline)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                        Text("\(ActivityFormat.hours(lifetime)) listened")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.secondaryText)
                            .padding(.top, 2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, Spacing.xs)

                    VStack(spacing: 0) {
                        ForEach(Array(track.levels.enumerated()), id: \.element.id) { index, rung in
                            LevelRow(level: rung, index: index, current: current, lifetime: lifetime,
                                     isLast: index == track.levels.count - 1)
                        }
                    }
                }
                .padding(.horizontal, Spacing.m)
                .padding(.bottom, Spacing.xl)
            }
            .background { ThemedPageBackground() }
            .navigationTitle("Listener Levels")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// One level on the ladder, with a dotted path down to the next. The current level is a
/// highlighted card (no label needed); reached ones get a tick; ones ahead show their hours.
private struct LevelRow: View {
    let level: ListenerLevel
    let index: Int
    let current: Int
    let lifetime: Double
    let isLast: Bool

    var body: some View {
        let unlocked = index <= current
        let isCurrent = index == current

        HStack(alignment: .top, spacing: Spacing.s) {
            VStack(spacing: 0) {
                PlanetBadge(level: level, size: 40, index: index, locked: !unlocked, interactive: false)
                    .frame(width: 64, height: 56)
                if !isLast {
                    DottedLine()
                        .stroke(index < current ? level.color.opacity(0.6) : Color.primary.opacity(0.15),
                                style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [0.1, 6]))
                        .frame(width: 2, height: 22)
                }
            }
            .frame(width: 64)

            HStack(alignment: .center, spacing: Spacing.xs) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(level.name)
                        .font(.headline)
                        .foregroundStyle(unlocked ? Color.primary : Theme.secondaryText)
                    Text(level.tagline)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: Spacing.xs)
                if !unlocked {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(Int(level.hours))h")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.secondaryText)
                        Text("\(ActivityFormat.hours(level.hours * 3600 - lifetime)) to go")
                            .font(.caption2)
                            .foregroundStyle(Theme.tertiaryText)
                    }
                } else if !isCurrent {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(Theme.readable(level.color))
                        .accessibilityLabel("Reached")
                }
            }
            .padding(.vertical, Spacing.s)
            .padding(.horizontal, Spacing.s)
            .frame(minHeight: 56)
            .background {
                if isCurrent {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(level.color.opacity(0.14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(level.color.opacity(0.6), lineWidth: 1.5)
                        }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

private struct DottedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return p
    }
}

// MARK: - Goals

/// Daily minutes and books per year.
struct GoalsSheet: View {
    @Binding var dailyGoal: Int
    @Binding var yearlyGoal: Int
    @Environment(\.dismiss) private var dismiss

    private let dailyOptions = [5, 10, 15, 20, 30, 45, 60, 90, 120]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    SettingsSection("Daily listening") {
                        VStack(alignment: .leading, spacing: Spacing.s) {
                            Text("\(dailyGoal) minutes a day")
                                .font(.headline)
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.xs), count: 3),
                                      spacing: Spacing.xs) {
                                ForEach(dailyOptions, id: \.self) { minutes in
                                    let selected = minutes == dailyGoal
                                    Button { dailyGoal = minutes } label: {
                                        Text(minutes < 60 ? "\(minutes) min" : TimeFormat.short(Double(minutes) * 60))
                                            .font(.subheadline.weight(.semibold))
                                            .frame(maxWidth: .infinity, minHeight: 44)
                                            .background(selected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.primary.opacity(0.05)),
                                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                            .foregroundStyle(selected ? Theme.onAccent : .primary)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityAddTraits(selected ? .isSelected : [])
                                }
                            }
                        }
                        .padding(.vertical, Spacing.s)
                    }

                    SettingsSection("Books this year") {
                        Stepper(value: $yearlyGoal, in: 1...200) {
                            Text("\(yearlyGoal) \(yearlyGoal == 1 ? "book" : "books")")
                                .font(.headline)
                        }
                        .padding(.vertical, Spacing.xs)
                    }
                }
                .padding(.horizontal, Spacing.l)
                .padding(.vertical, Spacing.m)
                .sensoryFeedback(.selection, trigger: dailyGoal)
            }
            .background { ThemedPageBackground() }
            .navigationTitle("Listening Goals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
