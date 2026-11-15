import Foundation
import AVFoundation
@preconcurrency import Speech

/// Finds chapters in audiobooks that have none by listening for the narrator
/// announcing them: "Chapter one", "Chapter 2", "Chapter twenty-three"…
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

    /// A spoken "Chapter N" and where it was heard on the book timeline.
    struct Mention: Sendable, Equatable {
        var time: Double
        var number: Int
        /// True when "Chapter" opened a sentence, which is how headings are read out.
        var isHeading: Bool
        /// The chapter's name when the narrator reads one: "Chapter Three. The Burrow."
        var name: String? = nil
    }

    /// Two chapter starts closer than this can't both be real.
    static let minimumGap: Double = 60

    private static let listeningStage = "Listening for chapter announcements…"

    // MARK: - Entry point

    static func detect(sources: [Source], totalDuration: Double, progress: @escaping Progress) async throws -> Result {
        progress("Getting ready…", 0)
        var heard: [Mention]?
        if #available(iOS 27, *) {
            heard = try await transcribeWithAnalyzer(sources: sources, totalDuration: totalDuration, progress: progress)
        }
        if heard == nil {
            heard = try await transcribeWithRecognizer(sources: sources, totalDuration: totalDuration, progress: progress)
        }
        try Task.checkCancellation()

        let sequence = bestSequence(deduplicated(heard ?? []))
        progress("Done", 1)
        return Result(chapters: assemble(sequence, totalDuration: totalDuration))
    }

    // MARK: - Choosing the announcements

    /// Drops repeats of the same number heard within a few seconds (chunk overlaps, stutters).
    private static func deduplicated(_ mentions: [Mention]) -> [Mention] {
        var result: [Mention] = []
        for mention in mentions.sorted(by: { $0.time < $1.time }) {
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

        func weight(_ mention: Mention) -> Double { mention.isHeading ? 1.0 : 0.6 }

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
        return chain.count >= 2 ? chain : []
    }

    private static func assemble(_ sequence: [Mention], totalDuration: Double) -> [Chapter] {
        let starts = sequence.filter { $0.time >= 0 && $0.time < totalDuration - 5 }
        guard !starts.isEmpty else { return [] }

        var entries: [(time: Double, title: String)] = []
        if starts[0].time > 45 {
            entries.append((0, "Opening"))
        }
        for mention in starts {
            let title = mention.name.map { "Chapter \(mention.number): \($0)" } ?? "Chapter \(mention.number)"
            entries.append((mention.time, title))
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
    }

    /// Finds every "Chapter <number>" in a word list. `offset` moves times onto the book timeline.
    static func mentions(in words: [TimedWord], offset: Double) -> [Mention] {
        var found: [Mention] = []
        var lastTime = 0.0
        for (i, word) in words.enumerated() {
            if let time = word.time, time.isFinite { lastTime = time }
            let cleaned = word.text.lowercased().trimmingCharacters(in: .punctuationCharacters)
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

    /// The title read after "Chapter <number>", e.g. "Chapter Three. The Burrow." → "The Burrow".
    /// Accepted only when it's short (8 words or fewer) and ends with a full stop or a pause;
    /// otherwise it's the story carrying on, not a title.
    static func chapterName(in words: [TimedWord], afterChapterAt index: Int) -> String? {
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

        var text = name.joined(separator: " ").trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
        guard text.count >= 2, text.rangeOfCharacter(from: .letters) != nil else { return nil }
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
        for source in sources {
            try Task.checkCancellation()
            let transcriber = makeTranscriber()
            let asset = AVURLAsset(url: source.url)
            let provider = try await AssetInputSequenceProvider.provider(from: asset, compatibleWith: [transcriber])
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            let offset = source.start

            let found = try await withThrowingTaskGroup(of: [Mention].self) { group in
                group.addTask {
                    var local: [Mention] = []
                    for try await result in transcriber.results {
                        local += mentions(in: result.text, offset: offset)
                        let end = result.range.end.seconds
                        if end.isFinite {
                            progress(listeningStage, min(0.99, (offset + end) / max(totalDuration, 1)))
                        }
                    }
                    return local
                }
                group.addTask {
                    do {
                        let last = try await analyzer.analyzeSequence(provider.analyzerInputs)
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
        }
        return heard
    }

    @available(iOS 26, *)
    private static func mentions(in text: AttributedString, offset: Double) -> [Mention] {
        var words: [TimedWord] = []
        for run in text.runs {
            let time = run.audioTimeRange?.start.seconds
            let piece = String(text[run.range].characters)
            for token in piece.split(whereSeparator: \.isWhitespace) {
                words.append(TimedWord(text: String(token), time: time))
            }
        }
        return mentions(in: words, offset: offset)
    }

    // MARK: - iOS 18–25: SFSpeechRecognizer in chunks

    private static let chunkSeconds = 50.0
    private static let chunkOverlap = 3.0

    private static func transcribeWithRecognizer(sources: [Source], totalDuration: Double,
                                                 progress: @escaping Progress) async throws -> [Mention] {
        guard await speechAuthorized() else { throw DetectionError.notAuthorized }
        guard let recognizer = makeRecognizer() else { throw DetectionError.speechUnavailable }

        var heard: [Mention] = []
        var recognizedAny = false
        for source in sources {
            let asset = AVURLAsset(url: source.url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
            var start = 0.0
            while start < source.duration {
                try Task.checkCancellation()
                progress(listeningStage, min(0.99, (source.start + start) / max(totalDuration, 1)))
                let samples = try await readSamples(asset: asset, from: start, duration: chunkSeconds + chunkOverlap, sampleRate: 16_000)
                if samples.count > 1_600, let words = await transcribe(samples, recognizer: recognizer) {
                    recognizedAny = true
                    heard += mentions(in: words, offset: source.start + start)
                }
                start += chunkSeconds
            }
        }
        // Not a single chunk came back: the recognizer is broken (e.g. its model failed to load),
        // which is different from hearing the book and finding no chapter announcements.
        guard recognizedAny else { throw DetectionError.speechUnavailable }
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

    private static func transcribe(_ samples: [Float], recognizer: SFSpeechRecognizer) async -> [TimedWord]? {
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
