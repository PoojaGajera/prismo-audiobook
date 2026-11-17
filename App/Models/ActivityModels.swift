import SwiftUI

// MARK: - Stats

/// Numbers for the Activity page, worked out once per redraw from the listening log and the library.
struct ActivityStats {
    let sessions: [ListeningSession]
    let books: [Book]
    let baselineSeconds: Double
    let dailyGoalSeconds: Double
    let now: Date
    let calendar: Calendar
    /// Seconds listened per day (keyed by the start of the day).
    let byDay: [Date: Double]

    @MainActor
    init(log: ListeningLog, books: [Book], dailyGoalMinutes: Int, now: Date = Date()) {
        var calendar = Calendar.current
        calendar.firstWeekday = 2 // weeks start on Monday
        self.calendar = calendar
        self.sessions = log.sessions
        self.books = books
        self.baselineSeconds = log.baselineSeconds
        self.dailyGoalSeconds = Double(max(1, dailyGoalMinutes)) * 60
        self.now = now
        var byDay: [Date: Double] = [:]
        for session in log.sessions {
            byDay[calendar.startOfDay(for: session.start), default: 0] += session.seconds
        }
        self.byDay = byDay
    }

    var today: Date { calendar.startOfDay(for: now) }

    func seconds(on day: Date) -> Double { byDay[calendar.startOfDay(for: day)] ?? 0 }

    var todaySeconds: Double { seconds(on: now) }

    var lifetimeSeconds: Double { baselineSeconds + sessions.reduce(0) { $0 + $1.seconds } }

    /// The day `offset` days before today.
    func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: -offset, to: today)! }

    func sessions(in interval: DateInterval) -> [ListeningSession] {
        sessions.filter { interval.contains($0.start) }
    }

    func seconds(in interval: DateInterval) -> Double {
        sessions(in: interval).reduce(0) { $0 + $1.seconds }
    }

    /// The last `days` days, oldest first, with their seconds.
    func recentDays(_ days: Int) -> [(day: Date, seconds: Double)] {
        (0..<days).reversed().map { (day: day($0), seconds: seconds(on: day($0))) }
    }

    /// A day counts towards the streak with at least a minute of listening.
    func isActive(_ day: Date) -> Bool { seconds(on: day) >= 60 }

    /// Days in a row with listening, ending today (or yesterday, if today hasn't started yet).
    var currentStreak: Int {
        var offset = isActive(today) ? 0 : 1
        var count = 0
        while isActive(day(offset)) { count += 1; offset += 1 }
        return count
    }

    var bestStreak: Int {
        let days = byDay.filter { $0.value >= 60 }.keys.sorted()
        var best = 0, run = 0
        var previous: Date?
        for day in days {
            if let previous, calendar.dateComponents([.day], from: previous, to: day).day == 1 {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = day
        }
        return best
    }

    var week: DateInterval { calendar.dateInterval(of: .weekOfYear, for: now)! }
    var month: DateInterval { calendar.dateInterval(of: .month, for: now)! }
    var year: DateInterval { calendar.dateInterval(of: .year, for: now)! }
    var yearNumber: Int { calendar.component(.year, from: now) }

    /// Books finished in `interval` (books finished before `finishedAt` existed count by last play).
    func booksFinished(in interval: DateInterval) -> [Book] {
        books.filter { book in
            guard book.isFinished, let date = book.finishedAt ?? book.lastPlayed else { return false }
            return interval.contains(date)
        }
    }

    var booksFinishedEver: Int { books.filter(\.isFinished).count }

    // MARK: Genres

    /// Listening time per genre family, most first (all time, plus finished books before tracking).
    var genres: [(genre: GenreFamily, seconds: Double)] {
        var totals: [GenreFamily: Double] = [:]
        for session in sessions {
            let genre = books.first(where: { $0.id == session.bookID })?.genre ?? session.genre
            totals[GenreFamily(genre), default: 0] += session.seconds
        }
        return totals.map { (genre: $0.key, seconds: $0.value) }.sorted { $0.seconds > $1.seconds }
    }

    func genreCount(in interval: DateInterval) -> Int {
        Set(sessions(in: interval).compactMap { session -> GenreFamily? in
            let family = GenreFamily(books.first(where: { $0.id == session.bookID })?.genre ?? session.genre)
            return family == .other ? nil : family
        }).count
    }

    // MARK: Time of day

    /// Share of listening in each part of the day, all time.
    var dayParts: [(part: DayPart, seconds: Double)] {
        var totals: [DayPart: Double] = [:]
        for session in sessions {
            totals[DayPart(hour: calendar.component(.hour, from: session.start)), default: 0] += session.seconds
        }
        return DayPart.allCases.map { (part: $0, seconds: totals[$0] ?? 0) }
    }

    /// Days in `interval` with listening that started in `part`.
    func days(in interval: DateInterval, part: DayPart) -> Int {
        Set(sessions(in: interval)
            .filter { DayPart(hour: calendar.component(.hour, from: $0.start)) == part && $0.seconds >= 300 }
            .map { calendar.startOfDay(for: $0.start) }).count
    }

    func sessionCount(part: DayPart) -> Int {
        sessions.filter { DayPart(hour: calendar.component(.hour, from: $0.start)) == part && $0.seconds >= 300 }.count
    }

    var longestSession: Double { sessions.map(\.seconds).max() ?? 0 }

    /// The book listened to most in `interval`.
    func topBook(in interval: DateInterval) -> (title: String, seconds: Double)? {
        var totals: [UUID: (String, Double)] = [:]
        for session in sessions(in: interval) {
            let title = books.first(where: { $0.id == session.bookID })?.title ?? session.title
            totals[session.bookID, default: (title, 0)].1 += session.seconds
        }
        return totals.values.max(by: { $0.1 < $1.1 }).map { (title: $0.0, seconds: $0.1) }
    }
}

// MARK: - Formatting

enum ActivityFormat {
    /// 13h 44m, 45m, 0m (never seconds: these are totals).
    static func duration(_ seconds: Double) -> String {
        let minutes = Int((max(0, seconds) / 60).rounded(.down))
        let h = minutes / 60, m = minutes % 60
        if h > 0 { return m > 0 && h < 100 ? "\(h)h \(m)m" : "\(h)h" }
        return "\(m)m"
    }

    /// Whole hours, for levels: "30h".
    static func hours(_ seconds: Double) -> String { "\(Int(max(0, seconds) / 3600))h" }
}

// MARK: - Levels

/// One rung on a level track.
struct ListenerLevel: Identifiable {
    let name: String
    let tagline: String
    let symbol: String
    let color: Color
    /// Lifetime hours needed.
    let hours: Double
    var id: String { name }
}

/// The Cosmos ladder of listener levels: eight stops from Stardust to Cosmos.
struct LevelTrack {
    let levels: [ListenerLevel]

    /// Lifetime hours at each level.
    static let thresholds: [Double] = [0, 5, 15, 40, 100, 200, 400, 1000]

    private typealias A = Theme.Activity

    /// Computed each time, so the level colours follow the current app theme.
    static var cosmos: LevelTrack {
        let rungs: [(String, String, String, Color)] = [
            ("Stardust", "Tiny, but made of stars.", "sparkle", A.violet),
            ("Moonbeam", "A soft glow in the dark.", "moon.fill", A.sky),
            ("Shooting Star", "Blink and a chapter's gone.", "star.fill", A.gold),
            ("Orbit", "Stories pull you round and round.", "atom", A.teal),
            ("Nebula", "Where new worlds are born.", "cloud.fill", A.coral),
            ("Supernova", "Bright enough to see from Earth.", "sun.max.fill", A.flame),
            ("Galaxy", "Billions of words and counting.", "hurricane", A.violet),
            ("Cosmos", "The whole universe of books.", "moon.stars.fill", A.sky),
        ]
        return LevelTrack(levels: zip(rungs, thresholds).map {
            ListenerLevel(name: $0.0, tagline: $0.1, symbol: $0.2, color: $0.3, hours: $1)
        })
    }

    func levelIndex(for seconds: Double) -> Int {
        let hours = seconds / 3600
        return (Self.thresholds.lastIndex { hours >= $0 }) ?? 0
    }
}

// MARK: - Genres

/// Book genres folded into a few families (the lookup's genre strings vary a lot).
enum GenreFamily: String, CaseIterable {
    case fantasy, scifi, mystery, romance, horror, history, selfHelp, science, kids, literary, other

    init(_ genre: String?) {
        let g = (genre ?? "").lowercased()
        func has(_ words: String...) -> Bool { words.contains { g.contains($0) } }
        if g.isEmpty { self = .other }
        else if has("fantasy", "magic", "dragon") { self = .fantasy }
        else if has("sci", "science fiction", "space", "dystop") { self = has("popular science") ? .science : .scifi }
        else if has("mystery", "thriller", "crime", "detective", "suspense") { self = .mystery }
        else if has("romance", "love") { self = .romance }
        else if has("horror", "ghost", "paranormal") { self = .horror }
        else if has("history", "historical", "biograph", "memoir", "war") { self = .history }
        else if has("self", "business", "psycholog", "health", "personal", "money", "productiv") { self = .selfHelp }
        else if has("science", "nature", "technology", "philosoph", "nonfiction", "non-fiction") { self = .science }
        else if has("child", "kids", "young adult", "teen", "juvenile") { self = .kids }
        else if has("fiction", "literary", "classic", "novel", "literature") { self = .literary }
        else { self = .other }
    }

    var name: String {
        switch self {
        case .fantasy: "Fantasy"
        case .scifi: "Sci-fi"
        case .mystery: "Mystery & Thriller"
        case .romance: "Romance"
        case .horror: "Horror"
        case .history: "History & Lives"
        case .selfHelp: "Self-improvement"
        case .science: "Science & Ideas"
        case .kids: "Young readers"
        case .literary: "Fiction"
        case .other: "Other"
        }
    }

    /// The listener's persona when this is their top genre.
    var persona: String {
        switch self {
        case .fantasy: "Realm Walker"
        case .scifi: "Star Navigator"
        case .mystery: "Midnight Detective"
        case .romance: "Hopeless Romantic"
        case .horror: "Fearless Listener"
        case .history: "Time Traveller"
        case .selfHelp: "Level-Up Seeker"
        case .science: "Curious Mind"
        case .kids: "Story Keeper"
        case .literary: "Story Connoisseur"
        case .other: "Genre Explorer"
        }
    }

    var symbol: String {
        switch self {
        case .fantasy: "wand.and.stars"
        case .scifi: "antenna.radiowaves.left.and.right"
        case .mystery: "magnifyingglass"
        case .romance: "heart.fill"
        case .horror: "moon.haze.fill"
        case .history: "hourglass"
        case .selfHelp: "figure.mind.and.body"
        case .science: "atom"
        case .kids: "teddybear.fill"
        case .literary: "book.fill"
        case .other: "safari.fill"
        }
    }

    var color: Color {
        typealias A = Theme.Activity
        switch self {
        case .fantasy: return A.violet
        case .scifi: return A.teal
        case .mystery: return Theme.accent
        case .romance: return A.coral
        case .horror: return A.slate
        case .history: return A.gold
        case .selfHelp: return A.mint
        case .science: return A.sky
        case .kids: return A.flame
        case .literary: return Theme.lilac
        case .other: return A.slate
        }
    }
}

// MARK: - Time of day

enum DayPart: CaseIterable {
    case morning, afternoon, evening, night

    init(hour: Int) {
        switch hour {
        case 5..<12: self = .morning
        case 12..<17: self = .afternoon
        case 17..<22: self = .evening
        default: self = .night
        }
    }

    var name: String {
        switch self {
        case .morning: "Morning"
        case .afternoon: "Afternoon"
        case .evening: "Evening"
        case .night: "Night"
        }
    }

    var persona: String {
        switch self {
        case .morning: "Early Bird"
        case .afternoon: "Lunch-break Listener"
        case .evening: "Evening Unwinder"
        case .night: "Night Owl"
        }
    }

    var symbol: String {
        switch self {
        case .morning: "sunrise.fill"
        case .afternoon: "sun.max.fill"
        case .evening: "sunset.fill"
        case .night: "moon.stars.fill"
        }
    }

    var color: Color {
        switch self {
        case .morning: Theme.Activity.gold
        case .afternoon: Theme.Activity.flame
        case .evening: Theme.Activity.coral
        case .night: Theme.Activity.violet
        }
    }
}

// MARK: - Challenges

/// A monthly challenge: three each month, the same three every month.
struct Challenge: Identifiable {
    let id: String
    let title: String
    let blurb: String
    let symbol: String
    let color: Color
    let target: Double
    /// How the progress reads: "3 of 20 hours".
    let unit: String
    let measure: (ActivityStats, DateInterval) -> Double

    func progress(_ stats: ActivityStats) -> Double { measure(stats, stats.month) }

    /// The key it's saved under once earned, e.g. "2026-M11.finishBook".
    func key(_ stats: ActivityStats) -> String {
        let c = stats.calendar
        return "\(c.component(.year, from: stats.now))-M\(c.component(.month, from: stats.now)).\(id)"
    }

    /// "3 of 20 hours", "1 of 1 book".
    func progressText(_ stats: ActivityStats) -> String {
        let value = Int(min(progress(stats), target).rounded(.down))
        return "\(value) of \(Int(target)) \(unit)"
    }

    private typealias A = Theme.Activity

    /// Computed each time, so the colours follow the current app theme.
    static var monthly: [Challenge] { [
        Challenge(id: "finishBook", title: "The End", blurb: "Finish a book this month",
                  symbol: "book.closed.fill", color: A.gold, target: 1, unit: "book") { s, i in
            Double(s.booksFinished(in: i).count)
        },
        Challenge(id: "twentyHours", title: "Twenty Hours", blurb: "Twenty hours of stories",
                  symbol: "hourglass", color: A.teal, target: 20, unit: "hours") { s, i in
            s.seconds(in: i) / 3600
        },
        Challenge(id: "twelveDays", title: "Regular", blurb: "Listen on twelve days",
                  symbol: "calendar", color: A.coral, target: 12, unit: "days") { s, i in
            Double(Set(s.sessions(in: i).filter { $0.seconds >= 60 }.map { s.calendar.startOfDay(for: $0.start) }).count)
        },
    ] }

    /// Time left in the month: "3 days left", "Ends today".
    func timeLeft(_ stats: ActivityStats) -> String {
        let days = stats.calendar.dateComponents([.day], from: stats.today, to: stats.month.end).day ?? 0
        if days <= 1 { return "Ends today" }
        return "\(days) days left"
    }
}

// MARK: - Trophies

/// Lifetime achievements, worked out from the stats (nothing extra is stored).
struct Trophy: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let color: Color
    let target: Double
    let value: Double

    var isEarned: Bool { value >= target }
    var fraction: Double { min(1, value / target) }

    static func all(_ s: ActivityStats, challengesEarned: Int) -> [Trophy] {
        typealias A = Theme.Activity
        let hours = s.lifetimeSeconds / 3600
        return [
            Trophy(id: "firstHour", title: "First Hour", detail: "Listen for an hour", symbol: "headphones",
                   color: A.sky, target: 1, value: hours),
            Trophy(id: "finisher", title: "Finisher", detail: "Finish a book", symbol: "book.closed.fill",
                   color: A.gold, target: 1, value: Double(s.booksFinishedEver)),
            Trophy(id: "shelf", title: "Full Shelf", detail: "Finish 10 books", symbol: "books.vertical.fill",
                   color: A.coral, target: 10, value: Double(s.booksFinishedEver)),
            Trophy(id: "onFire", title: "On Fire", detail: "A 7-day streak", symbol: "flame.fill",
                   color: A.flame, target: 7, value: Double(s.bestStreak)),
            Trophy(id: "unstoppable", title: "Unstoppable", detail: "A 30-day streak", symbol: "bolt.fill",
                   color: A.violet, target: 30, value: Double(s.bestStreak)),
            Trophy(id: "century", title: "Century", detail: "100 hours listened", symbol: "hourglass",
                   color: A.teal, target: 100, value: hours),
            Trophy(id: "nightOwl", title: "Night Owl", detail: "10 late-night sessions", symbol: "moon.stars.fill",
                   color: A.violet, target: 10, value: Double(s.sessionCount(part: .night))),
            Trophy(id: "earlyBird", title: "Early Bird", detail: "10 morning sessions", symbol: "sunrise.fill",
                   color: A.gold, target: 10, value: Double(s.sessionCount(part: .morning))),
            Trophy(id: "explorer", title: "Explorer", detail: "Listen to 5 genres", symbol: "safari.fill",
                   color: A.mint, target: 5, value: Double(s.genres.filter { $0.genre != .other }.count)),
            Trophy(id: "marathoner", title: "Marathoner", detail: "3 hours in one go", symbol: "figure.run",
                   color: A.coral, target: 180, value: s.longestSession / 60),
            Trophy(id: "challenger", title: "Challenger", detail: "Complete 10 challenges", symbol: "medal.fill",
                   color: A.gold, target: 10, value: Double(challengesEarned)),
            Trophy(id: "goalStreak", title: "Committed", detail: "Hit your goal 30 days", symbol: "target",
                   color: A.mint, target: 30, value: Double(s.byDay.values.filter { $0 >= s.dailyGoalSeconds }.count)),
        ]
    }
}
