import Foundation
import AVFoundation
import Accelerate
@preconcurrency import Speech

/// Finds chapters in audiobooks that have none by listening for the narrator
/// announcing them: "Chapter one", "Chapter 2", "Chapter twenty-three"… or, for narrators who
/// skip the word "Chapter", just the number said on its own between pauses: "… [pause] Seven. [pause] …".
///
/// The whole book is transcribed on the device. On iOS 26 and later this uses
/// `SpeechAnalyzer`, which is built for long recordings; earlier systems fall back to
/// `SFSpeechRecognizer` on short consecutive chunks. Only announcements that form a
/// sensible sequence (1, 2, 3… with at most one number skipped) are kept, so passing
/// mentions such as "as we saw in chapter three" are ignored.
enum ChapterDetector {
    struct Source {
        var url: URL
        var start: Double      // where this file starts on the book timeline
        var duration: Double
    }

    struct Result {
        var chapters: [Chapter]
    }

    enum DetectionError: LocalizedError {
        case unreadable
        case speechUnavailable
        case notAuthorized

        var errorDescription: String? {
            switch self {
            case .unreadable: return "The audio couldn't be read for chapter detection."
            case .speechUnavailable: return "Speech recognition isn't available on this iPhone."
            case .notAuthorized: return "Allow Speech Recognition for Audiobooks in Settings to find chapters."
            }
        }
    }

    typealias Progress = @Sendable (_ stage: String, _ fraction: Double) -> Void
    typealias SaveCheckpoint = @Sendable (Checkpoint) -> Void

    /// How far a scan got, so a stopped or failed scan can carry on from there instead of
    /// starting again: the place on the book timeline to continue from, and the announcements
    /// heard before it.
    struct Checkpoint: Codable, Sendable {
        var position: Double
        var mentions: [Mention]
        /// Why it stopped: nil while running (or if the app was closed mid-scan), otherwise a
        /// short reason ("stopped" when you tapped Stop, or the error).
        var stoppedBecause: String? = nil
        /// True once the quick pass wasn't enough and the whole book is being listened to.
        var fullListen: Bool? = nil
    }

    /// When resuming, a little audio before the checkpoint is listened to again, so the pause
    /// before an announcement right at the checkpoint can still be measured.
    static let resumeOverlap: Double = 8

    /// A spoken "Chapter N" and where it was heard on the book timeline.
    struct Mention: Sendable, Equatable, Codable {
        var time: Double
        var number: Int
        /// True when "Chapter" opened a sentence, which is how headings are read out.
        var isHeading: Bool
        /// The chapter's name when the narrator reads one: "Chapter Three. The Burrow."
        var name: String? = nil
        /// Just the number, said on its own between pauses ("Seven."), without "Chapter".
        var isBare = false
        /// "Prologue" or "Epilogue" (then `number` is 0): read out as a heading, like a chapter.
        var special: String? = nil
        /// A word said on its own that sounds like a number but was written as something else
        /// ("to" for "two", "for" for "four", "thirty" for "thirteen"). Only used to fill a
        /// gap in the chapters (`fillGaps`), never on its own.
        var isWeak = false
    }

    /// A long pause on the book timeline (from the loudness scan).
    struct Pause: Sendable {
        var start: Double
        var end: Double
        var silence: Double
    }

    /// Headings read out like chapters but without a number.
    static let specialHeadings: [String: String] = ["prologue": "Prologue", "epilogue": "Epilogue"]

    /// Two chapter starts closer than this can't both be real.
    static let minimumGap: Double = 60

    private static let listeningStage = "Listening for chapter announcements…"

    // MARK: - Entry point

    /// Works in two steps, to save time and heat:
    /// 1. **Quick pass.** Narrators pause before announcing a chapter, so the book's loudness is
    ///    measured first (fast, no speech recognition) to find its longest pauses, and only the
    ///    few seconds around each of those are listened to: roughly a tenth of the book.
    /// 2. **Whole book.** Only if the quick pass didn't find a convincing run of chapters
    ///    (1, 2, 3… with none missing and no suspiciously long chapter), everything is listened to.
    ///
    /// - Parameters:
    ///   - resume: where an earlier scan of this book got to; listening starts there.
    ///   - save: called every so often with how far this scan has got (for resuming later).
    static func detect(sources: [Source], totalDuration: Double, resume: Checkpoint? = nil,
                       save: @escaping SaveCheckpoint = { _ in },
                       progress: @escaping Progress) async throws -> Result {
        let total = max(totalDuration, 1)
        let resumeFraction = (resume?.position ?? 0) / total
        progress("Getting ready…", resumeFraction)
        var heard = resume?.mentions ?? []
        var startAt = max(0, (resume?.position ?? 0) - (resume == nil ? 0 : resumeOverlap))

        // The loudness scan (fast) finds the pauses: used to choose where to listen, and to place a
        // chapter whose announcement wasn't heard.
        let (plan, pauses) = try await quickPlan(sources: sources, totalDuration: totalDuration) { fraction in
            // The loudness scan is the first tenth of the progress bar.
            if resume == nil { progress("Looking for pauses…", fraction * 0.1) }
        }
        if resume?.fullListen != true {
            if let plan {
                heard += try await transcribe(sources: sources, totalDuration: totalDuration, windows: plan,
                                              startAt: startAt, earlier: heard, save: save) { stage, fraction in
                    progress(stage, max(resumeFraction, 0.1 + 0.9 * fraction))
                }
                try Task.checkCancellation()
                // Gaps filled from sound-alikes only (no guessing yet): if that's not enough,
                // the whole book gets a listen.
                var sequence = fillGaps(bestSequence(deduplicated(heard)), heard: heard, pauses: nil)
                if !isConvincing(sequence, totalDuration: totalDuration), sequence.count >= 3 {
                    // Some numbers missing: re-listen just around them before falling back to
                    // the whole book.
                    heard += try await relistenForMissing(sequence, sources: sources, totalDuration: totalDuration,
                                                          pauses: pauses, progress: progress)
                    sequence = fillGaps(bestSequence(deduplicated(heard)), heard: heard, pauses: nil)
                }
                if isConvincing(sequence, totalDuration: totalDuration) {
                    progress("Done", 1)
                    return Result(chapters: assemble(withSpecials(sequence, from: heard, totalDuration: totalDuration), totalDuration: totalDuration))
                }
            }
            // Not convincing: listen to the whole book, from the beginning.
            startAt = 0
        }

        heard += try await transcribe(sources: sources, totalDuration: totalDuration, windows: nil,
                                      startAt: startAt, earlier: heard,
                                      save: { var checkpoint = $0; checkpoint.fullListen = true; save(checkpoint) },
                                      progress: progress)
        try Task.checkCancellation()

        // Any numbers still missing: re-listen just around them, then fill what's left with a
        // sound-alike, or else the longest pause where it should be.
        let found = bestSequence(deduplicated(heard))
        if found.count >= 3, !isConvincing(fillGaps(found, heard: heard, pauses: nil), totalDuration: totalDuration) {
            heard += try await relistenForMissing(found, sources: sources, totalDuration: totalDuration,
                                                  pauses: pauses, progress: progress)
        }
        let sequence = fillGaps(bestSequence(deduplicated(heard)), heard: heard, pauses: pauses)
        progress("Done", 1)
        return Result(chapters: assemble(withSpecials(sequence, from: heard, totalDuration: totalDuration), totalDuration: totalDuration))
    }

    /// How to listen: normally, or (re-listening for missed chapters) with words to expect
    /// and a stronger boost for quiet voices.
    struct Listening: Sendable {
        /// Words the recogniser should expect ("Thirteen", "Chapter Thirteen").
        var hints: [String] = []
        /// How much quiet speech may be boosted (12 = +22 dB).
        var maxGain: Float = 12
    }

    /// Listens (to the whole book, or only to `windows`: time ranges within each source file)
    /// with the best speech recognition this iPhone has, and returns the announcements heard.
    private static func transcribe(sources: [Source], totalDuration: Double, windows: [[ClosedRange<Double>]]?,
                                   startAt: Double, earlier: [Mention], save: @escaping SaveCheckpoint,
                                   listening: Listening = Listening(),
                                   progress: @escaping Progress) async throws -> [Mention] {
        if #available(iOS 27, *),
           let heard = try await transcribeWithAnalyzer(sources: sources, totalDuration: totalDuration, windows: windows,
                                                        startAt: startAt, earlier: earlier, save: save,
                                                        listening: listening, progress: progress) {
            return heard
        }
        return try await transcribeWithRecognizer(sources: sources, totalDuration: totalDuration, windows: windows,
                                                  startAt: startAt, earlier: earlier, save: save,
                                                  listening: listening, progress: progress)
    }

    // MARK: - Scanning one chapter

    /// The chapter number in a title made by Find Chapters ("Chapter 12", "Chapter 12: The Burrow");
    /// 0 for "Opening" and "Prologue" (they come before Chapter 1); nil otherwise.
    static func chapterNumber(inTitle title: String) -> Int? {
        if title == "Opening" || title == "Prologue" { return 0 }
        guard title.hasPrefix("Chapter ") else { return nil }
        // "12", "12: The Burrow", "Eight: Flight of the Fat Lady", "Twenty-One"
        let rest = title.dropFirst("Chapter ".count).prefix { $0 != ":" }
        return spokenNumber(rest.split(separator: " ").map(String.init))
    }

    /// The numbers to listen for when rescanning chapter `index`: the missing ones if there's a
    /// gap after it, otherwise the next chapter's number (in case the next chapter really starts
    /// earlier, inside this one). Empty when the chapter has no number to go by.
    static func rescanNumbers(in chapters: [Chapter], at index: Int) -> [Int] {
        let missing = missingNumbers(in: chapters, at: index)
        if !missing.isEmpty { return missing }
        guard chapters.indices.contains(index), let number = chapterNumber(inTitle: chapters[index].title) else { return [] }
        return [number + 1]
    }

    /// Which chapter numbers could be hiding inside chapter `index` of `chapters`: the gap
    /// between its number and the next chapter's (Chapter 1 followed by Chapter 3 → [2]), or the
    /// number after it for the last chapter. Empty when nothing can be missing there.
    static func missingNumbers(in chapters: [Chapter], at index: Int) -> [Int] {
        guard chapters.indices.contains(index),
              let number = chapterNumber(inTitle: chapters[index].title) else { return [] }
        if index + 1 < chapters.count {
            guard let next = chapterNumber(inTitle: chapters[index + 1].title), next > number + 1 else { return [] }
            return Array((number + 1)..<next)
        }
        return [number + 1]
    }

    /// Listens to all of one chapter (`from`–`to` on the book timeline), expecting the given
    /// numbers, with the stronger boost for quiet voices. Returns where each expected number
    /// was announced (only those heard, in order, a minute or more apart and from the chapter's
    /// edges): the places to split the chapter.
    static func findMissing(_ expected: [Int], from: Double, to: Double, sources: [Source], totalDuration: Double,
                            progress: @escaping @Sendable (Double) -> Void) async throws -> [Mention] {
        guard !expected.isEmpty, to > from else { return [] }
        var windows: [[ClosedRange<Double>]] = sources.map { _ in [] }
        for (index, source) in sources.enumerated() {
            let start = max(from, source.start) - source.start
            let end = min(to, source.start + source.duration) - source.start
            if end > start { windows[index] = [start...end] }
        }
        let hints = expected.flatMap { number -> [String] in
            let word = spelledNumber(number)
            return [word, "Chapter \(word)", "\(number)"]
        }
        let heard = try await transcribe(sources: sources, totalDuration: totalDuration, windows: windows,
                                         startAt: 0, earlier: [], save: { _ in },
                                         listening: Listening(hints: hints, maxGain: 24)) { _, fraction in
            progress(min(1, max(0, (fraction * max(totalDuration, 1) - from) / (to - from))))
        }

        // For each expected number: where it was clearly heard, else a sound-alike said on its own.
        var found: [Mention] = []
        var after = from + minimumGap
        for number in expected {
            let candidates = heard.filter { $0.number == number && $0.special == nil && $0.time > after && $0.time < to - minimumGap }
            guard let pick = candidates.filter({ !$0.isWeak }).min(by: { $0.time < $1.time })
                    ?? candidates.min(by: { $0.time < $1.time }) else { continue }
            var mention = pick
            mention.isWeak = false
            found.append(mention)
            after = pick.time + minimumGap
        }
        return found
    }

    // MARK: - Re-listening for missed chapters

    /// When chapters are missing from the numbering (… 12, 14 … or a first chapter that isn't
    /// 1), listens again to just the stretches between their neighbours: around each of the
    /// longer pauses there, telling the recogniser which numbers to expect and boosting quiet
    /// voices twice as much. Returns the announcements heard (to add to the rest).
    private static func relistenForMissing(_ sequence: [Mention], sources: [Source], totalDuration: Double,
                                           pauses: [Pause], progress: @escaping Progress) async throws -> [Mention] {
        guard let first = sequence.first else { return [] }
        var expected: [Int] = []
        var stretches: [(from: Double, to: Double)] = []
        if first.number > 1, first.number <= 4 {
            expected += Array(1..<first.number)
            stretches.append((0, first.time - 5))
        }
        for (previous, next) in zip(sequence, sequence.dropFirst()) where next.number - previous.number >= 2 {
            expected += Array((previous.number + 1)..<next.number)
            stretches.append((previous.time + 30, next.time - 5))
        }
        guard !expected.isEmpty else { return [] }

        // Around the longer pauses in each stretch (at most 15 per missing chapter).
        var bookWindows: [ClosedRange<Double>] = []
        for stretch in stretches where stretch.to > stretch.from {
            let inside = pauses.filter { $0.end > stretch.from && $0.start < stretch.to && $0.silence >= 1.0 }
                .sorted { $0.silence > $1.silence }.prefix(15)
            for pause in inside {
                let from = max(stretch.from, pause.start - 2.5)
                let to = min(stretch.to, pause.end + 6)
                if to > from { bookWindows.append(from...to) }
            }
        }
        guard !bookWindows.isEmpty else { return [] }

        // The same windows, as times within each source file, in order and without overlaps.
        var windows: [[ClosedRange<Double>]] = sources.map { _ in [] }
        for (index, source) in sources.enumerated() {
            let local = bookWindows.compactMap { window -> ClosedRange<Double>? in
                let from = max(window.lowerBound, source.start) - source.start
                let to = min(window.upperBound, source.start + source.duration) - source.start
                return to > from ? from...to : nil
            }.sorted { $0.lowerBound < $1.lowerBound }
            var merged: [ClosedRange<Double>] = []
            for window in local {
                if let last = merged.last, window.lowerBound <= last.upperBound {
                    merged[merged.count - 1] = last.lowerBound...max(last.upperBound, window.upperBound)
                } else {
                    merged.append(window)
                }
            }
            windows[index] = merged
        }

        let hints = expected.flatMap { number -> [String] in
            let word = spelledNumber(number)
            return [word, "Chapter \(word)", "\(number)"]
        }
        return try await transcribe(sources: sources, totalDuration: totalDuration, windows: windows,
                                    startAt: 0, earlier: [], save: { _ in },
                                    listening: Listening(hints: hints, maxGain: 24)) { _, _ in
            progress("Checking for missed chapters…", 0.98)
        }
    }

    /// 13 → "Thirteen", 21 → "Twenty-one", 105 → "One hundred and five".
    static func spelledNumber(_ number: Int) -> String {
        let ones = ["", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven",
                    "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"]
        let tensWords = ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]
        func below100(_ n: Int) -> String {
            if n < 20 { return ones[n] }
            return tensWords[n / 10] + (n % 10 == 0 ? "" : "-" + ones[n % 10])
        }
        let n = max(1, min(999, number))
        var text = n >= 100 ? ones[n / 100] + " hundred" + (n % 100 == 0 ? "" : " and " + below100(n % 100)) : below100(n)
        text = text.prefix(1).uppercased() + text.dropFirst()
        return text
    }

    // MARK: - Quick pass: where to listen

    /// Loudness is measured in steps of this many seconds.
    static let loudnessStep = 0.1

    /// The parts of each source worth listening to (around its longest pauses), or nil when the
    /// quick pass isn't worth it: a short book, or pauses so frequent it would save little.
    private static func quickPlan(sources: [Source], totalDuration: Double,
                                  progress: @escaping @Sendable (Double) -> Void)
        async throws -> (windows: [[ClosedRange<Double>]]?, pauses: [Pause]) {
        var plan: [[ClosedRange<Double>]] = []
        var allPauses: [Pause] = []
        var toListen = 0.0
        for source in sources {
            let levels = try await loudness(of: source.url) { seconds in
                progress(min(1, (source.start + seconds) / max(totalDuration, 1)))
            }
            allPauses += pauses(loudness: levels).map {
                Pause(start: source.start + $0.start, end: source.start + $0.end, silence: $0.silence)
            }
            let windows = listeningWindows(loudness: levels, duration: source.duration)
            toListen += windows.reduce(0) { $0 + ($1.upperBound - $1.lowerBound) }
            plan.append(windows)
        }
        // Short books, or pauses so frequent the quick pass would save little: listen to everything.
        let worthIt = totalDuration >= 20 * 60 && toListen > 0 && toListen < totalDuration * 0.4
        return (worthIt ? plan : nil, allPauses)
    }

    /// How loud the file is, every `loudnessStep` seconds (RMS, 0…1). Only decodes the audio, so
    /// it's many times faster and cooler than speech recognition.
    private static func loudness(of url: URL, progress: @Sendable (Double) -> Void) async throws -> [Float] {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { throw DetectionError.unreadable }
        let reader = try AVAssetReader(asset: asset)
        let sampleRate = 8_000.0
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: pcmSettings(sampleRate: sampleRate))
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw DetectionError.unreadable }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? DetectionError.unreadable }

        let frame = Int(sampleRate * loudnessStep)
        var levels: [Float] = []
        var carry: [Float] = []
        var buffers = 0
        while let buffer = output.copyNextSampleBuffer() {
            carry += floats(in: buffer)
            var used = 0
            carry.withUnsafeBufferPointer { samples in
                guard let base = samples.baseAddress else { return }
                while used + frame <= samples.count {
                    var meanSquare: Float = 0
                    vDSP_measqv(base + used, 1, &meanSquare, vDSP_Length(frame))
                    levels.append(meanSquare.squareRoot())
                    used += frame
                }
            }
            carry.removeFirst(used)
            buffers += 1
            if buffers % 256 == 0 {
                try Task.checkCancellation()
                try await ScanPacing.waitWhileHot()
                progress(Double(levels.count) * loudnessStep)
            }
        }
        if reader.status == .failed { throw reader.error ?? DetectionError.unreadable }
        return levels
    }

    /// Picks the stretches worth listening to: the file's longest pauses, each with a little of
    /// what comes before (to measure the pause) and a few seconds after (the announcement, any
    /// title, and the start of the story). A quiet announcement in the middle of a pause counts
    /// as part of the pause, so it's inside the stretch too. Always includes the opening.
    static func listeningWindows(loudness levels: [Float], duration: Double) -> [ClosedRange<Double>] {
        let groups = pauses(loudness: levels)
        guard !groups.isEmpty || levels.count > 100 else { return [] }

        // The longest pauses: about one for every minute and a half of audio.
        let limit = max(8, Int(duration / 90))
        let chosen = groups.filter { $0.silence >= 1.5 }.sorted { $0.silence > $1.silence }.prefix(limit)

        var windows: [ClosedRange<Double>] = [0...min(45, duration)]
        for group in chosen {
            let from = max(0, group.start - 2.5)
            let to = min(duration, group.end + 8)
            if to > from { windows.append(from...to) }
        }
        // In order, with overlapping ones joined.
        var merged: [ClosedRange<Double>] = []
        for window in windows.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = merged.last, window.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound...max(last.upperBound, window.upperBound)
            } else {
                merged.append(window)
            }
        }
        return merged
    }

    /// The file's pauses (times within the file), from its loudness. Silences of 0.8 s or more;
    /// silences with only a few words between them are one pause ("[pause] Seven. [pause]"),
    /// so a quiet announcement in the middle of a pause counts as part of it.
    static func pauses(loudness levels: [Float]) -> [Pause] {
        let step = loudnessStep
        guard levels.count > 100 else { return [] }
        // Quiet = well below normal speech: 30% of the way from the noise floor to typical loudness.
        let sorted = levels.sorted()
        let floor = sorted[sorted.count / 20]
        let typical = sorted[sorted.count * 6 / 10]
        guard typical > 0 else { return [] }
        let threshold = floor + 0.3 * (typical - floor)

        // Silences of 0.8 s or more.
        var silences: [(start: Double, end: Double)] = []
        var runStart: Int?
        for i in 0...levels.count {
            let quiet = i < levels.count && levels[i] < threshold
            if quiet {
                if runStart == nil { runStart = i }
            } else if let from = runStart {
                if Double(i - from) * step >= 0.8 { silences.append((Double(from) * step, Double(i) * step)) }
                runStart = nil
            }
        }

        // Silences with only a few words between them belong together ("[pause] Chapter seven.
        // [pause] The Burrow. [pause]"), as long as the group stays short.
        var groups: [(start: Double, end: Double, silence: Double)] = []
        for silence in silences {
            let length = silence.end - silence.start
            if let last = groups.last, silence.start - last.end <= 4, silence.end - last.start <= 25 {
                groups[groups.count - 1].end = silence.end
                groups[groups.count - 1].silence += length
            } else {
                groups.append((silence.start, silence.end, length))
            }
        }

        return groups.map { Pause(start: $0.start, end: $0.end, silence: $0.silence) }
    }

    /// Whether the quick pass's chapters can be trusted without listening to the whole book:
    /// at least three, numbered without a gap, and none far longer than the rest (which would
    /// mean announcements in it were missed).
    static func isConvincing(_ sequence: [Mention], totalDuration: Double) -> Bool {
        guard sequence.count >= 3 else { return false }
        var lengths: [Double] = []
        for (previous, next) in zip(sequence, sequence.dropFirst()) {
            guard next.number - previous.number == 1 else { return false }
            lengths.append(next.time - previous.time)
        }
        let typical = lengths.sorted()[lengths.count / 2]
        let longest = max(lengths.max() ?? 0, totalDuration - (sequence.last?.time ?? 0), sequence[0].time)
        return longest <= 3.5 * typical
    }

    // MARK: - Choosing the announcements

    /// Drops repeats of the same number heard within a few seconds (chunk overlaps, stutters).
    /// How many chapters the announcements heard so far add up to (for "3 found so far").
    /// Can go down as well as up: a later announcement can show an earlier one was a mistake.
    static func chaptersSoFar(_ mentions: [Mention]) -> Int {
        bestSequence(deduplicated(mentions)).count
    }

    /// Adds a Prologue and an Epilogue to the numbered chapters (they have no numbers, so they
    /// aren't part of the 1, 2, 3… run). With chapters: the last Prologue heard before the first
    /// chapter, and the first Epilogue heard after the last chapter has had its minute. Without
    /// any numbered chapters they're still added: a Prologue heard in the first fifth of the
    /// book, and an Epilogue heard in the last fifth (after the Prologue).
    static func withSpecials(_ sequence: [Mention], from heard: [Mention], totalDuration: Double) -> [Mention] {
        let prologues = heard.filter { $0.special == "Prologue" }
        let epilogues = heard.filter { $0.special == "Epilogue" }
        var result = sequence
        if let first = sequence.first, let last = sequence.last {
            if let prologue = prologues.filter({ $0.time < first.time - 30 }).max(by: { $0.time < $1.time }) {
                result.insert(prologue, at: 0)
            }
            if let epilogue = epilogues.filter({ $0.time > last.time + minimumGap }).min(by: { $0.time < $1.time }) {
                result.append(epilogue)
            }
        } else {
            let prologue = prologues.filter { $0.time < totalDuration * 0.2 }.min(by: { $0.time < $1.time })
            if let prologue { result.append(prologue) }
            if let epilogue = epilogues.filter({ $0.time > totalDuration * 0.8 && $0.time > (prologue?.time ?? 0) + minimumGap })
                .max(by: { $0.time < $1.time }) {
                result.append(epilogue)
            }
        }
        return result
    }

    /// Fills single gaps in the numbering (… 12, 14 …): chapter 13 must start somewhere between.
    /// First choice: a sound-alike heard there on its own ("thirty" for "thirteen", "to" for
    /// "two") or the number itself heard less clearly. Otherwise, with `pauses`: the longest
    /// pause between them (narrators pause before a new chapter). Each chapter keeps at least a
    /// minute either side.
    static func fillGaps(_ sequence: [Mention], heard: [Mention], pauses: [Pause]?) -> [Mention] {
        guard sequence.count >= 2 else { return sequence }
        var result: [Mention] = [sequence[0]]
        for (previous, next) in zip(sequence, sequence.dropFirst()) {
            if next.number - previous.number == 2 {
                let missing = previous.number + 1
                let from = previous.time + minimumGap
                let to = next.time - minimumGap
                if from < to {
                    if let candidate = heard.filter({ $0.number == missing && $0.special == nil && $0.time > from && $0.time < to })
                        .min(by: { $0.time < $1.time }) {
                        var filled = candidate
                        filled.isWeak = false
                        result.append(filled)
                    } else if let pauses,
                              let pause = pauses.filter({ $0.end > from && $0.start < to && $0.silence >= 1.5 })
                                  .max(by: { $0.silence < $1.silence }) {
                        // The new chapter starts just after the last words of the one before.
                        result.append(Mention(time: pause.start + 0.3, number: missing, isHeading: false, isBare: true))
                    }
                }
            }
            result.append(next)
        }
        return result
    }

    private static func deduplicated(_ mentions: [Mention]) -> [Mention] {
        var result: [Mention] = []
        // Prologue and Epilogue are added afterwards (`withSpecials`), not part of the numbering.
        for mention in mentions.filter({ $0.special == nil && !$0.isWeak }).sorted(by: { $0.time < $1.time }) {
            if let last = result.last, last.number == mention.number, mention.time - last.time < 5 {
                // Same announcement heard twice (chunk overlap): keep the one that caught the name.
                if last.name == nil, mention.name != nil { result[result.count - 1].name = mention.name }
                continue
            }
            result.append(mention)
        }
        return result
    }

    /// Picks the best run of announcements whose numbers go up by one (or two, allowing a
    /// missed one) and that are far enough apart to be separate chapters.
    static func bestSequence(_ mentions: [Mention]) -> [Mention] {
        let sorted = mentions.sorted { $0.time < $1.time }
        guard !sorted.isEmpty else { return [] }

        // "Chapter 7" as a heading counts most; a bare "Seven." least, since numbers on their own
        // turn up in stories too (only a run of them going 1, 2, 3… is believable).
        func weight(_ mention: Mention) -> Double {
            if mention.isBare { return 0.5 }
            return mention.isHeading ? 1.0 : 0.6
        }

        var score = sorted.map(weight)
        var previous = [Int?](repeating: nil, count: sorted.count)
        for i in sorted.indices {
            for j in 0..<i {
                let step = sorted[i].number - sorted[j].number
                guard step >= 1, step <= 2, sorted[i].time - sorted[j].time >= minimumGap else { continue }
                let candidate = score[j] + weight(sorted[i]) - (step == 2 ? 0.3 : 0)
                if candidate > score[i] {
                    score[i] = candidate
                    previous[i] = j
                }
            }
        }

        guard let end = score.indices.max(by: { score[$0] < score[$1] }) else { return [] }
        var chain: [Mention] = []
        var cursor: Int? = end
        while let index = cursor {
            chain.append(sorted[index])
            cursor = previous[index]
        }
        chain.reverse()
        // A run made only of bare numbers needs at least three to be trusted.
        let needed = chain.allSatisfy(\.isBare) ? 3 : 2
        return chain.count >= needed ? chain : []
    }

    private static func assemble(_ sequence: [Mention], totalDuration: Double) -> [Chapter] {
        let starts = sequence.filter { $0.time >= 0 && $0.time < totalDuration - 5 }
        guard !starts.isEmpty else { return [] }

        // Many books have numbers only, no chapter names. If names were heard for fewer than half
        // the chapters, they're most likely bits of the story, so every chapter is just "Chapter N".
        let numbered = starts.filter { $0.special == nil }
        let named = numbered.filter { $0.name != nil }.count
        let useNames = named * 2 >= numbered.count

        var entries: [(time: Double, title: String)] = []
        if starts[0].time > 45 {
            entries.append((0, "Opening"))
        }
        for mention in starts {
            if let special = mention.special {
                entries.append((mention.time, special))
                continue
            }
            let title = useNames ? mention.name.map { "Chapter \(mention.number): \($0)" } : nil
            entries.append((mention.time, title ?? "Chapter \(mention.number)"))
        }
        entries[0].time = 0

        var chapters: [Chapter] = []
        for (i, entry) in entries.enumerated() {
            let end = i + 1 < entries.count ? entries[i + 1].time : totalDuration
            chapters.append(Chapter(title: entry.title, start: entry.time, duration: max(0, end - entry.time)))
        }
        return chapters
    }

    // MARK: - Reading the transcript

    struct TimedWord {
        var text: String
        /// Seconds from the start of the transcribed audio, when known.
        var time: Double?
        /// The first word heard in a listening window (quick pass): what came before it wasn't
        /// listened to, so the "pause" before it isn't real.
        var startsWindow = false
    }

    /// Finds every "Chapter <number>" in a word list. `offset` moves times onto the book timeline.
    /// Only words from index `first` up to (not including) `end` are looked at; the words around
    /// them are context (the end of the previous piece of transcript, and the next piece): they're
    /// used to judge pauses and read titles, but no mentions are taken from them.
    static func mentions(in words: [TimedWord], offset: Double, from first: Int = 0, to end: Int? = nil) -> [Mention] {
        let end = end ?? words.count
        var found: [Mention] = []
        var lastTime = 0.0
        for (i, word) in words.enumerated() {
            if let time = word.time, time.isFinite { lastTime = time }
            guard i >= first, i < end else { continue }
            let cleaned = word.text.lowercased().trimmingCharacters(in: .punctuationCharacters)
            if let heading = Self.specialHeadings[cleaned], isSpokenHeading(in: words, at: i) {
                found.append(Mention(time: offset + max(0, lastTime - 0.3), number: 0, isHeading: true,
                                     special: heading))
                continue
            }
            if let alternatives = Self.soundAlikes[cleaned], isolatedWord(in: words, at: i) {
                for number in alternatives {
                    found.append(Mention(time: offset + max(0, lastTime - 0.3), number: number, isHeading: false,
                                         isBare: true, isWeak: true))
                }
                // "thirty" is also a real number: carry on to check it as one.
                if Int(cleaned) == nil, !numberParts.contains(cleaned) { continue }
            }
            if cleaned != "chapter", let bare = bareNumber(in: words, at: i) {
                // Narrators who say only the number often don't read a title either, and the
                // story starts straight away, so a name is only taken when a pause follows it.
                found.append(Mention(time: offset + max(0, lastTime - 0.3), number: bare, isHeading: false,
                                     name: chapterName(in: words, afterChapterAt: i - 1, needsPauseAfter: true),
                                     isBare: true))
                continue
            }
            guard cleaned == "chapter", i + 1 < words.count,
                  let number = spokenNumber(words[(i + 1)...].prefix(5).map(\.text)) else { continue }

            let previous = i > 0 ? words[i - 1].text : ""
            let startsSentence = previous.isEmpty || previous.last.map { ".!?".contains($0) } == true
            let isHeading = word.text.first?.isUppercase == true && startsSentence
            found.append(Mention(time: offset + max(0, lastTime - 0.3), number: number, isHeading: isHeading,
                                 name: chapterName(in: words, afterChapterAt: i)))
        }
        return found
    }

    private static let numberParts: Set<String> = Set(units.keys).union(tens.keys).union(["hundred"])

    /// Pauses (in seconds between the starts of neighbouring words) that set a bare number apart.
    /// A word takes about half a second to say, so 1.3 s means a real pause of most of a second.
    private static let pauseBefore = 1.3
    private static let pauseAfter = 1.1

    /// "Prologue" / "Epilogue" read as a heading, not mentioned in passing ("as in the prologue"):
    /// it opens a sentence (or follows a pause) and is followed by a pause or a full stop.
    static func isSpokenHeading(in words: [TimedWord], at i: Int) -> Bool {
        let word = words[i]
        let previous = i > 0 ? words[i - 1] : nil
        let afterPause: Bool = {
            guard let previous else { return true }
            if previous.text.last.map({ ".!?".contains($0) }) == true { return true }
            if let start = word.time, let before = previous.time, !word.startsWindow { return start - before >= pauseBefore }
            return false
        }()
        guard afterPause, word.text.first?.isUppercase == true || word.startsWindow || previous == nil else { return false }
        if word.text.last.map({ ".!?:;".contains($0) }) == true { return true }
        guard i + 1 < words.count else { return true }
        if let next = words[i + 1].time, let start = word.time { return next - start >= pauseAfter }
        return false
    }

    /// Words a recogniser often writes instead of a quiet number said on its own: "to/too" (two),
    /// "for/fore" (four), "won" (one), "ate" (eight), and the "-teen"/"-ty" mix-ups.
    static let soundAlikes: [String: [Int]] = [
        "to": [2], "too": [2], "for": [4], "fore": [4], "won": [1], "ate": [8], "tree": [3], "free": [3],
        "thirty": [13], "forty": [14], "fifty": [15], "sixty": [16], "seventy": [17], "eighty": [18], "ninety": [19],
        "thirteen": [30], "fourteen": [40], "fifteen": [50], "sixteen": [60], "seventeen": [70],
        "eighteen": [80], "nineteen": [90],
        "30": [13], "40": [14], "50": [15], "60": [16], "70": [17], "80": [18], "90": [19],
    ]

    /// One word said on its own: a pause before it, and a pause or full stop after it.
    static func isolatedWord(in words: [TimedWord], at i: Int) -> Bool {
        guard i > 0, !words[i].startsWindow, let start = words[i].time, let before = words[i - 1].time,
              start - before >= pauseBefore else { return false }
        if words[i].text.last.map({ ".!?:;".contains($0) }) == true { return true }
        guard i + 1 < words.count else { return true }
        guard let next = words[i + 1].time else { return false }
        return next - start >= pauseAfter
    }

    /// A number said on its own, as some narrators announce chapters: a pause, "Seven." (or
    /// "Twenty-one."), then a pause or a full stop. Not when it follows "Chapter" (handled
    /// separately), and not mid-sentence ("seven years later" has no pause after "seven").
    static func bareNumber(in words: [TimedWord], at i: Int) -> Int? {
        guard i > 0, !words[i].startsWindow, let start = words[i].time, let before = words[i - 1].time,
              start - before >= pauseBefore else { return nil }
        let previous = words[i - 1].text.lowercased().trimmingCharacters(in: .punctuationCharacters)
        guard !["chapter", "part", "book", "page", "number"].contains(previous) else { return nil }

        // The number's words: "seven", "7", "twenty-one", "twenty one", "one hundred and five".
        var j = i
        var endsSentence = false
        while j < words.count, j - i < 5 {
            let raw = words[j].text
            let parts = raw.lowercased().trimmingCharacters(in: .punctuationCharacters)
                .split(separator: "-").map(String.init)
            let isNumber = !parts.isEmpty && parts.allSatisfy { $0.first?.isNumber == true || numberParts.contains($0) }
            let isJoiningAnd = parts == ["and"] && j > i && words[j - 1].text.lowercased().hasPrefix("hundred")
            guard isNumber || isJoiningAnd else { break }
            j += 1
            if raw.last.map({ ".!?:;".contains($0) }) == true { endsSentence = true; break }
            if raw.last == "," { break }
        }
        guard j > i, let number = spokenNumber(words[i..<j].map(\.text)), (1...300).contains(number) else { return nil }

        // Followed by a pause or the end of a sentence (the transcript's full stop).
        let pausedAfter: Bool
        if j < words.count, let next = words[j].time, let last = words[j - 1].time {
            pausedAfter = next - last >= pauseAfter
        } else {
            pausedAfter = j >= words.count
        }
        return pausedAfter || endsSentence ? number : nil
    }

    /// The title read after "Chapter <number>", e.g. "Chapter Three. The Burrow." → "The Burrow".
    /// Accepted only when it's short (8 words or fewer) and ends with a full stop or a pause;
    /// otherwise it's the story carrying on, not a title.
    static func chapterName(in words: [TimedWord], afterChapterAt index: Int,
                            needsPauseAfter: Bool = false) -> String? {
        // Step over the number: "3", "three", "twenty-one", "one hundred and five".
        var j = index + 1
        while j < words.count, j - index <= 5 {
            let raw = words[j].text
            let parts = raw.lowercased().trimmingCharacters(in: .punctuationCharacters)
                .split(separator: "-").map(String.init)
            let isNumber = !parts.isEmpty && parts.allSatisfy { $0.first?.isNumber == true || numberParts.contains($0) }
            let isJoiningAnd = parts == ["and"] && j > index + 1
                && words[j - 1].text.lowercased().hasPrefix("hundred") && j + 1 < words.count
            guard isNumber || isJoiningAnd else { break }
            j += 1
            if raw.last.map({ ".!?:;,".contains($0) }) == true { break }
        }
        guard j > index + 1, j < words.count else { return nil }

        var name: [String] = []
        var ended = false
        var previousTime = words[j - 1].time
        while j < words.count {
            let word = words[j]
            // A pause after some of the title means the title is over.
            if !name.isEmpty, let time = word.time, let previous = previousTime, time - previous > 1.2 {
                ended = true
                break
            }
            name.append(word.text)
            if word.time != nil { previousTime = word.time }
            j += 1
            if word.text.last.map({ ".!?".contains($0) }) == true { ended = true; break }
            if name.count > 8 { return nil }
        }
        if j >= words.count { ended = true }
        guard ended, !name.isEmpty, name.count <= 8 else { return nil }
        // Stricter: a full stop isn't enough, the narrator must also pause after the title
        // (otherwise it's probably the story's first sentence).
        if needsPauseAfter {
            guard name.count <= 6 else { return nil }
            if j < words.count {
                guard let next = words[j].time, let previous = previousTime, next - previous > 1.2 else { return nil }
            }
        }

        var text = name.joined(separator: " ").trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
        guard text.count >= 2, text.rangeOfCharacter(from: .letters) != nil else { return nil }
        // Just another number ("Three."), not a title.
        let allNumbers = name.allSatisfy { word in
            let parts = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
                .split(separator: "-").map(String.init)
            return !parts.isEmpty && parts.allSatisfy { $0.first?.isNumber == true || numberParts.contains($0) }
        }
        guard !allNumbers else { return nil }
        if text == text.lowercased() { text = TitleCleaner.titleCased(text) }
        return text
    }

    private static let units: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
        "seventeen": 17, "eighteen": 18, "nineteen": 19,
        "first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5, "sixth": 6, "seventh": 7, "eighth": 8,
        "ninth": 9, "tenth": 10, "eleventh": 11, "twelfth": 12, "thirteenth": 13, "fourteenth": 14,
        "fifteenth": 15, "sixteenth": 16, "seventeenth": 17, "eighteenth": 18, "nineteenth": 19,
    ]
    private static let tens: [String: Int] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
        "twentieth": 20, "thirtieth": 30, "fortieth": 40, "fiftieth": 50, "sixtieth": 60, "seventieth": 70,
        "eightieth": 80, "ninetieth": 90,
    ]

    /// Reads a chapter number from the words that follow "Chapter":
    /// "7", "7.", "seven", "Seven:", "twenty-one", "twenty one", "one hundred and five".
    static func spokenNumber(_ words: [String]) -> Int? {
        // Split hyphenated words, and remember where a sentence ended so "Chapter twenty. One day…" stays 20.
        var tokens: [(text: String, endsSentence: Bool)] = []
        for word in words {
            let endsSentence = word.last.map { ".!?;:".contains($0) } ?? false
            let pieces = word.lowercased().split(separator: "-").map { $0.trimmingCharacters(in: .punctuationCharacters) }
            for (i, piece) in pieces.enumerated() where !piece.isEmpty {
                tokens.append((piece, endsSentence && i == pieces.count - 1))
            }
        }
        guard let first = tokens.first else { return nil }

        if first.text.first?.isNumber == true {
            guard let value = Int(first.text.prefix { $0.isNumber }), (1...999).contains(value) else { return nil }
            return value
        }

        var index = 0
        var value = 0
        var matched = false

        if (first.text == "one" || first.text == "a"), tokens.count > 1, tokens[1].text == "hundred" {
            value = 100
            index = 2
            matched = true
            if index < tokens.count, tokens[index].text == "and", !tokens[index - 1].endsSentence { index += 1 }
        }
        if index < tokens.count, matched, tokens[index - 1].endsSentence {
            return value
        }
        if index < tokens.count, let ten = tens[tokens[index].text] {
            value += ten
            matched = true
            let tenEndsSentence = tokens[index].endsSentence
            index += 1
            if index < tokens.count, !tenEndsSentence, let unit = units[tokens[index].text], unit < 10 {
                value += unit
            }
        } else if index < tokens.count, let unit = units[tokens[index].text] {
            value += unit
            matched = true
        }
        return matched && value > 0 ? value : nil
    }

    // MARK: - iOS 26: SpeechAnalyzer

    @available(iOS 27, *)
    private static func transcribeWithAnalyzer(sources: [Source], totalDuration: Double,
                                               windows: [[ClosedRange<Double>]]?,
                                               startAt: Double, earlier: [Mention],
                                               save: @escaping SaveCheckpoint,
                                               listening: Listening,
                                               progress: @escaping Progress) async throws -> [Mention]? {
        var supported = await SpeechTranscriber.supportedLocale(equivalentTo: .current)
        if supported == nil {
            supported = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US"))
        }
        guard let locale = supported else { return nil }

        func makeTranscriber() -> SpeechTranscriber {
            SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [.audioTimeRange])
        }

        if let request = try await AssetInventory.assetInstallationRequest(supporting: [makeTranscriber()]) {
            progress("Downloading the speech model…", 0)
            try await request.downloadAndInstall()
        }

        var heard: [Mention] = []
        for (index, source) in sources.enumerated() {
            try Task.checkCancellation()
            // Resuming: files already done are skipped, and the one in progress starts part way.
            guard source.start + source.duration > startAt else { continue }
            let skip = max(0, startAt - source.start)
            // What to listen to in this file: everything, or only the quick pass's windows.
            let ranges: [ClosedRange<Double>]
            if let windows {
                ranges = windows[index].compactMap {
                    $0.upperBound > skip ? max($0.lowerBound, skip)...$0.upperBound : nil
                }
                if ranges.isEmpty { continue }
            } else {
                ranges = [skip...Double.infinity]
            }
            let transcriber = makeTranscriber()
            // The audio is read here (not with AssetInputSequenceProvider) so it can be evened out
            // first: some narrators read the chapter announcements much more quietly than the
            // story, and the recognizer misses them unless they're brought up to speech level.
            // It's also fed at a capped speed (see `ScanPacing`), so the iPhone doesn't get hot.
            let pacer = ScanPacer()
            let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
                ?? AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
            let audio = try await LevelledAudioReader(url: source.url, format: format, pacer: pacer, ranges: ranges,
                                                      maxGain: listening.maxGain)
            let inputs = AsyncThrowingStream<AnalyzerInput, Error>(unfolding: { try await audio.next() })
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            if !listening.hints.isEmpty {
                // Words to expect (the missing chapter numbers): makes a quiet "Thirteen" much
                // more likely to come out as "thirteen" than as "thirty" or nothing.
                let context = AnalysisContext()
                context.contextualStrings[.general] = listening.hints
                try? await analyzer.setContext(context)
            }
            let offset = source.start
            let before = earlier + heard

            let found = try await withThrowingTaskGroup(of: [Mention].self) { group in
                group.addTask {
                    var local: [Mention] = []
                    // The transcript arrives in pieces split at pauses, so a number said on its
                    // own ("Seven.") is usually a piece by itself, with any title in the next one.
                    // So each piece is judged one step late, with the end of the piece before it
                    // and the whole piece after it as context: the pauses on both sides can be
                    // measured, and a title that follows can be read.
                    var context: [TimedWord] = []
                    var pending: [TimedWord] = []
                    var lastRange = -1
                    for try await result in transcriber.results {
                        // The recognizer's times count the audio it was given; turn them into
                        // times in the file (they differ when only parts of it are listened to).
                        let next = timedWords(in: result.text).map { word -> TimedWord in
                            guard let time = word.time else { return word }
                            let place = audio.place(at: time)
                            defer { lastRange = place.range }
                            return TimedWord(text: word.text, time: place.time,
                                             startsWindow: windows != nil && place.range != lastRange)
                        }
                        let words = context + pending + next
                        local += mentions(in: words, offset: offset,
                                          from: context.count, to: context.count + pending.count)
                        context = Array((context + pending).suffix(8))
                        pending = next
                        // Everything before the piece still waiting to be judged is done.
                        if let resumeAt = (pending.first?.time ?? context.last?.time) {
                            save(Checkpoint(position: offset + resumeAt, mentions: before + local))
                        }
                        let end = result.range.end.seconds
                        if end.isFinite {
                            progress(listeningStage, min(0.99, (offset + audio.place(at: end).time) / max(totalDuration, 1)))
                        }
                    }
                    // The last piece (nothing comes after it).
                    let words = context + pending
                    local += mentions(in: words, offset: offset, from: context.count, to: words.count)
                    return local
                }
                group.addTask {
                    do {
                        let last = try await analyzer.analyzeSequence(inputs)
                        if Task.isCancelled {
                            await analyzer.cancelAndFinishNow()
                            throw CancellationError()
                        }
                        if let last {
                            try await analyzer.finalizeAndFinish(through: last)
                        } else {
                            await analyzer.cancelAndFinishNow()
                        }
                    } catch {
                        await analyzer.cancelAndFinishNow()
                        throw error
                    }
                    return []
                }
                var all: [Mention] = []
                for try await part in group { all += part }
                return all
            }
            heard += found
            save(Checkpoint(position: source.start + source.duration, mentions: earlier + heard))
        }
        return heard
    }

    @available(iOS 26, *)
    private static func timedWords(in text: AttributedString) -> [TimedWord] {
        var words: [TimedWord] = []
        for run in text.runs {
            let time = run.audioTimeRange?.start.seconds
            let piece = String(text[run.range].characters)
            for token in piece.split(whereSeparator: \.isWhitespace) {
                words.append(TimedWord(text: String(token), time: time))
            }
        }
        return words
    }

    // MARK: - iOS 18–25: SFSpeechRecognizer in chunks

    private static let chunkSeconds = 50.0
    private static let chunkOverlap = 3.0

    private static func transcribeWithRecognizer(sources: [Source], totalDuration: Double,
                                                 windows: [[ClosedRange<Double>]]?,
                                                 startAt: Double, earlier: [Mention],
                                                 save: @escaping SaveCheckpoint,
                                                 listening: Listening,
                                                 progress: @escaping Progress) async throws -> [Mention] {
        guard await speechAuthorized() else { throw DetectionError.notAuthorized }
        guard let recognizer = makeRecognizer() else { throw DetectionError.speechUnavailable }

        var heard: [Mention] = []
        var recognizedAny = false
        var tried = 0
        let pacer = ScanPacer()
        for (index, source) in sources.enumerated() {
            // Resuming: files already done are skipped, and the one in progress starts part way.
            guard source.start + source.duration > startAt else { continue }
            let skip = max(0, startAt - source.start)
            // What to listen to in this file: everything, or only the quick pass's windows.
            let ranges: [ClosedRange<Double>]
            if let windows {
                ranges = windows[index].compactMap {
                    let to = min($0.upperBound, source.duration)
                    return to > max($0.lowerBound, skip) ? max($0.lowerBound, skip)...to : nil
                }
            } else {
                ranges = skip < source.duration ? [skip...source.duration] : []
            }
            let asset = AVURLAsset(url: source.url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
            for range in ranges {
                // In chunks short enough for the recognizer, overlapping a little.
                var start = range.lowerBound
                while start < range.upperBound {
                    try Task.checkCancellation()
                    progress(listeningStage, min(0.99, (source.start + start) / max(totalDuration, 1)))
                    let length = min(chunkSeconds + chunkOverlap, range.upperBound - start)
                    var samples = try await readSamples(asset: asset, from: start, duration: length, sampleRate: 16_000)
                    // Bring quiet parts (often the chapter announcements) up to speech level.
                    var leveller = SpeechLeveller(sampleRate: 16_000, maxGain: listening.maxGain)
                    leveller.level(&samples)
                    tried += 1
                    if samples.count > 1_600, let words = await transcribe(samples, recognizer: recognizer, hints: listening.hints) {
                        recognizedAny = true
                        heard += mentions(in: words, offset: source.start + start)
                    }
                    start += chunkSeconds
                    save(Checkpoint(position: source.start + min(start, range.upperBound), mentions: earlier + heard))
                    // Rests between chunks, longer when the iPhone is warm, and waits while it's hot.
                    pacer.advance(by: length)
                    try await pacer.waitIfAhead()
                }
            }
        }
        // Not a single chunk came back: the recognizer is broken (e.g. its model failed to load),
        // which is different from hearing the book and finding no chapter announcements.
        guard recognizedAny || startAt > 0 || tried == 0 else { throw DetectionError.speechUnavailable }
        return heard
    }

    private static func speechAuthorized() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
            }
        default: return false
        }
    }

    private static func makeRecognizer() -> SFSpeechRecognizer? {
        let recognizer = SFSpeechRecognizer() ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let recognizer, recognizer.isAvailable else { return nil }
        return recognizer
    }

    private static func transcribe(_ samples: [Float], recognizer: SFSpeechRecognizer,
                                   hints: [String] = []) async -> [TimedWord]? {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            if let base = source.baseAddress { channel.update(from: base, count: samples.count) }
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = false
        request.taskHint = .dictation
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        if !hints.isEmpty { request.contextualStrings = hints }
        request.append(buffer)
        request.endAudio()

        return await withCheckedContinuation { continuation in
            let box = ResumeOnce(continuation)
            let task = recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal {
                    box.resume(result.bestTranscription.segments.map {
                        TimedWord(text: $0.substring, time: $0.timestamp)
                    })
                } else if error != nil {
                    box.resume(nil)
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 90) {
                task.cancel()
                box.resume(nil)
            }
        }
    }

    private final class ResumeOnce: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        private let continuation: CheckedContinuation<[TimedWord]?, Never>

        init(_ continuation: CheckedContinuation<[TimedWord]?, Never>) { self.continuation = continuation }

        func resume(_ value: [TimedWord]?) {
            lock.lock()
            defer { lock.unlock() }
            guard !done else { return }
            done = true
            continuation.resume(returning: value)
        }
    }

    // MARK: - Audio reading

    private static func pcmSettings(sampleRate: Double) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
    }

    private static func floats(in buffer: CMSampleBuffer) -> [Float] {
        guard let block = CMSampleBufferGetDataBuffer(buffer) else { return [] }
        let length = CMBlockBufferGetDataLength(block)
        let count = length / 4
        guard count > 0 else { return [] }
        var samples = [Float](repeating: 0, count: count)
        samples.withUnsafeMutableBytes { raw in
            if let base = raw.baseAddress {
                _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: count * 4, destination: base)
            }
        }
        return samples
    }

    private static func readSamples(asset: AVURLAsset, from start: Double, duration: Double, sampleRate: Double) async throws -> [Float] {
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { throw DetectionError.unreadable }
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 1000),
                                       duration: CMTime(seconds: duration, preferredTimescale: 1000))
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: pcmSettings(sampleRate: sampleRate))
        guard reader.canAdd(output) else { throw DetectionError.unreadable }
        reader.add(output)
        guard reader.startReading() else { throw DetectionError.unreadable }
        var samples: [Float] = []
        while let buffer = output.copyNextSampleBuffer() {
            samples += floats(in: buffer)
        }
        if reader.status == .failed { throw reader.error ?? DetectionError.unreadable }
        return samples
    }
}

// MARK: - Keeping the iPhone cool

/// Finding chapters listens to the whole book. Flat out, that keeps the Neural Engine and CPU
/// busy for many minutes and the iPhone gets very hot. So the audio is fed in at a capped speed
/// that drops as the iPhone warms up, and the work pauses completely while it's hot.
enum ScanPacing {
    /// How many times faster than real time to listen (nil: pause, the iPhone is hot).
    /// At 20× a 10-hour book takes about half an hour.
    static func speedLimit() -> Double? {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return 20
        case .fair: return 8
        case .serious, .critical: return nil
        @unknown default: return 8
        }
    }

    /// Waits for the iPhone to cool down if it's hot.
    static func waitWhileHot() async throws {
        while speedLimit() == nil {
            try await Task.sleep(for: .seconds(15))
        }
    }
}

/// Paces speech recognition (see `ScanPacing`): it's told how much audio has been listened to,
/// and `waitIfAhead()` waits whenever that's more than the speed limit allows, and while the
/// iPhone is hot. Used from two tasks at once (the audio feed and the transcript), so it locks.
final class ScanPacer: @unchecked Sendable {
    private let lock = NSLock()
    private var windowStart = ContinuousClock.now
    private var windowAudio = 0.0
    private var windowLimit: Double?
    private var lastPosition = 0.0

    /// `seconds` more audio has been listened to.
    func advance(by seconds: Double) {
        lock.withLock { windowAudio += max(0, seconds) }
    }

    /// The transcript has reached `position` seconds into the file.
    func moved(to position: Double) {
        lock.withLock {
            windowAudio += max(0, position - lastPosition)
            lastPosition = max(lastPosition, position)
        }
    }

    /// Waits while the iPhone is hot, then as long as needed to stay under the speed limit.
    func waitIfAhead() async throws {
        try Task.checkCancellation()
        while ScanPacing.speedLimit() == nil {
            try await Task.sleep(for: .seconds(15))
            lock.withLock { windowLimit = nil }   // start timing afresh once it's cooler
        }
        let limit = ScanPacing.speedLimit() ?? 8
        let wait: Duration = lock.withLock {
            if windowLimit != limit {
                windowLimit = limit
                windowStart = .now
                windowAudio = 0
            }
            let earliest = Duration.seconds(windowAudio / limit)
            let elapsed = windowStart.duration(to: .now)
            return earliest > elapsed ? earliest - elapsed : .zero
        }
        if wait > .zero { try await Task.sleep(for: wait) }
    }
}

// MARK: - Evening out the volume

/// Brings quiet speech up to a normal level before recognition, so a chapter announcement read
/// in a soft or thin voice is heard as well as the story. Works in 50 ms steps: each step's
/// loudness is measured and boosted towards ordinary speech level, by at most 12× (+22 dB).
/// Near-silence isn't boosted (that would just raise the hiss), loud parts are never turned down,
/// and the boost changes smoothly so it doesn't pump or click.
struct SpeechLeveller {
    let sampleRate: Double
    private var gain: Float = 1

    /// About −22 dBFS: a typical level for clear speech.
    private static let targetLevel: Float = 0.08
    /// Below about −50 dBFS it's a pause or room noise, not speech.
    private static let silenceLevel: Float = 0.003
    private let maxGain: Float

    init(sampleRate: Double, maxGain: Float = 12) {
        self.sampleRate = sampleRate
        self.maxGain = maxGain
    }

    mutating func level(_ samples: inout [Float]) {
        let step = max(1, Int(sampleRate * 0.05))
        var start = 0
        while start < samples.count {
            let end = min(samples.count, start + step)
            var sum: Float = 0
            for i in start..<end { sum += samples[i] * samples[i] }
            let rms = (sum / Float(end - start)).squareRoot()

            let wanted: Float
            if rms < Self.silenceLevel {
                wanted = gain                                   // a pause: keep the boost as it is
            } else {
                wanted = min(maxGain, max(1, Self.targetLevel / rms))
            }
            // Down at once (no sudden loud bursts), up gently (about a third of a second).
            let next = wanted < gain ? wanted : gain + (wanted - gain) * 0.15

            // Glide from the old boost to the new one across the step, and keep within ±1.
            let count = Float(end - start)
            for (n, i) in (start..<end).enumerated() {
                let g = gain + (next - gain) * Float(n + 1) / count
                samples[i] = min(1, max(-1, samples[i] * g))
            }
            gain = next
            start = end
        }
    }
}

/// Reads an audio file for `SpeechAnalyzer`: one channel at the analyzer's sample rate, evened
/// out by `SpeechLeveller`, and only as fast as `ScanPacer` allows. It reads the given time
/// ranges of the file one after another (the whole file is one range), with half a second of
/// silence between them, and remembers where each piece came from so the recognizer's times
/// can be turned back into times in the file. Each call to `next()` reads the next piece, so
/// the file is never all in memory.
@available(iOS 26, *)
final class LevelledAudioReader: @unchecked Sendable {
    private let asset: AVURLAsset
    private let track: AVAssetTrack
    private let format: AVAudioFormat
    private let pacer: ScanPacer
    private var leveller: SpeechLeveller
    private let ranges: [ClosedRange<Double>]
    private var rangeIndex = 0
    private var reader: AVAssetReader?
    private var output: AVAssetReaderTrackOutput?
    private var owesGap = false
    /// Samples handed to the recognizer so far.
    private var fedSamples = 0

    /// Where each range's audio sits in what the recognizer was given (guarded by `lock`).
    private struct Segment {
        var fedStart: Double
        var fileStart: Double
        var length: Double
        var range: Int
    }
    private let lock = NSLock()
    private var segments: [Segment] = []

    /// - Parameter ranges: the parts of the file to read, in order (seconds; the last may end at
    ///   `.infinity` for "to the end").
    init(url: URL, format: AVAudioFormat, pacer: ScanPacer, ranges: [ClosedRange<Double>],
         maxGain: Float = 12) async throws {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw ChapterDetector.DetectionError.unreadable
        }
        self.asset = asset
        self.track = track
        self.format = format
        self.pacer = pacer
        self.ranges = ranges
        leveller = SpeechLeveller(sampleRate: format.sampleRate, maxGain: maxGain)
    }

    deinit { reader?.cancelReading() }

    /// Turns a time the recognizer reports (seconds of audio it was given) into a time in the
    /// file, and says which range it's in.
    func place(at fedTime: Double) -> (time: Double, range: Int) {
        lock.withLock {
            guard let segment = segments.last(where: { $0.fedStart <= fedTime }) ?? segments.first else {
                return (ranges.first?.lowerBound ?? 0, 0)
            }
            return (segment.fileStart + min(max(0, fedTime - segment.fedStart), segment.length), segment.range)
        }
    }

    private func open(_ range: ClosedRange<Double>) throws {
        let reader = try AVAssetReader(asset: asset)
        let duration = range.upperBound.isFinite
            ? CMTime(seconds: range.upperBound - range.lowerBound, preferredTimescale: 1000)
            : CMTime.positiveInfinity
        reader.timeRange = CMTimeRange(start: CMTime(seconds: range.lowerBound, preferredTimescale: 1000),
                                       duration: duration)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw ChapterDetector.DetectionError.unreadable }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? ChapterDetector.DetectionError.unreadable }
        self.reader = reader
        self.output = output
        let fedStart = Double(fedSamples) / format.sampleRate
        lock.withLock {
            segments.append(Segment(fedStart: fedStart, fileStart: range.lowerBound, length: 0, range: rangeIndex))
        }
    }

    /// The next piece of audio, or nil when every range has been read.
    func next() async throws -> AnalyzerInput? {
        try await pacer.waitIfAhead()
        while true {
            if output == nil {
                guard rangeIndex < ranges.count else { return nil }
                if owesGap {
                    // A short silence between ranges, so the recognizer doesn't run their words together.
                    owesGap = false
                    let silence = [Float](repeating: 0, count: Int(format.sampleRate * 0.5))
                    guard let buffer = makeBuffer(silence) else { throw ChapterDetector.DetectionError.unreadable }
                    fedSamples += silence.count
                    return AnalyzerInput(buffer: buffer)
                }
                try open(ranges[rangeIndex])
            }
            if let sampleBuffer = output?.copyNextSampleBuffer() {
                var samples = Self.floats(in: sampleBuffer)
                guard !samples.isEmpty else { continue }
                leveller.level(&samples)
                guard let buffer = makeBuffer(samples) else { throw ChapterDetector.DetectionError.unreadable }
                let seconds = Double(samples.count) / format.sampleRate
                fedSamples += samples.count
                lock.withLock { segments[segments.count - 1].length += seconds }
                pacer.advance(by: seconds)
                return AnalyzerInput(buffer: buffer)
            }
            if reader?.status == .failed { throw reader?.error ?? ChapterDetector.DetectionError.unreadable }
            // This range is done: on to the next.
            reader = nil
            output = nil
            rangeIndex += 1
            owesGap = rangeIndex < ranges.count
        }
    }

    /// The samples in the analyzer's own format (32-bit float or 16-bit whole numbers).
    private func makeBuffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        let channels = Int(format.channelCount)
        if let floats = buffer.floatChannelData {
            for channel in 0..<channels {
                samples.withUnsafeBufferPointer { source in
                    if let base = source.baseAddress { floats[channel].update(from: base, count: samples.count) }
                }
            }
        } else if let ints = buffer.int16ChannelData {
            for channel in 0..<channels {
                for i in samples.indices { ints[channel][i] = Int16(samples[i] * 32_767) }
            }
        } else {
            return nil
        }
        return buffer
    }

    private static func floats(in buffer: CMSampleBuffer) -> [Float] {
        guard let block = CMSampleBufferGetDataBuffer(buffer) else { return [] }
        let count = CMBlockBufferGetDataLength(block) / 4
        guard count > 0 else { return [] }
        var samples = [Float](repeating: 0, count: count)
        samples.withUnsafeMutableBytes { raw in
            if let base = raw.baseAddress {
                _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: count * 4, destination: base)
            }
        }
        return samples
    }
}
