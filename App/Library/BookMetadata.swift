import Foundation
import UIKit
import NaturalLanguage

// MARK: - Title cleanup

/// Strips the noise that audiobook file names and tags often carry:
/// "01 - Project Hail Mary (Unabridged) [64kbps].m4b" → "Project Hail Mary".
enum TitleCleaner {
    /// Words that mark a parenthesised part as noise, e.g. "(Unabridged)", "(Opus 5.1ch)".
    /// Square- and curly-bracketed parts are always dropped: real titles almost never use them.
    private static let noiseWords: Set<String> = [
        "unabridged", "abridged", "audiobook", "audible", "retail", "narrated", "mp3", "m4b", "m4a",
        "aac", "opus", "flac", "kbps", "khz", "ripped", "encode", "encoded", "stereo", "mono",
        "dramatized", "dramatised",
    ]
    private static let noisePhrases = ["read by", "audio book", "full cast"]

    /// Whole-word check, so "(Monologues)" or "(The Trip)" aren't mistaken for noise.
    private static func isNoise(_ text: String) -> Bool {
        let lower = text.lowercased()
        if noisePhrases.contains(where: lower.contains) { return true }
        if lower.range(of: #"^\s*(19|20)\d\d\s*$"#, options: .regularExpression) != nil { return true } // a year
        let tokens = lower.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        return tokens.contains { token in
            noiseWords.contains(token)
                || token.range(of: #"^\d+(kbps|khz|ch)$"#, options: .regularExpression) != nil // 64kbps, 1ch
        }
    }

    static func clean(_ raw: String, author: String? = nil) -> String {
        // A file extension left in the title.
        var s = raw.replacingOccurrences(of: #"\.(m4b|m4a|mp3|aac|mp4|wav|flac)$"#, with: "", options: [.regularExpression, .caseInsensitive])

        // Words joined by underscores, or (when there are no spaces at all) by dots or hyphens:
        // "Harry_Potter_and_the", "Harry.Potter.and.the", "harry-potter-and-the".
        // Number-only titles like "11.22.63" are left alone.
        s = s.replacingOccurrences(of: "_", with: " ")
        if !s.contains(" "), s.rangeOfCharacter(from: .letters) != nil {
            for separator in [".", "-"] where s.components(separatedBy: separator).count >= 3 {
                s = s.replacingOccurrences(of: separator, with: " ")
            }
        }

        // Square/curly-bracketed parts: "[Opus 5.1ch Encode]", "{Retail}".
        s = s.replacingOccurrences(of: #"\s*(\[[^\]]*\]|\{[^\}]*\})"#, with: "", options: .regularExpression)
        // Parenthesised parts that are noise, or just a year: "(Unabridged)", "(2019)".
        s = s.replacingOccurrences(of: #"\s*\(([^\)]*)\)"#, with: "",
                                   where: isNoise)

        // "… read by Ray Porter", "… narrated by …" at the end.
        s = s.replacingOccurrences(of: #"\s*[-,:]?\s*(read|narrated)\s+by\s+.*$"#, with: "", options: [.regularExpression, .caseInsensitive])
        // Loose noise words: "Dune Unabridged Audiobook 64kbps".
        s = s.replacingOccurrences(of: #"\b(unabridged|abridged|audiobook|audio book|audible|m4b|mp3|\d+\s?kbps)\b"#, with: "",
                                   options: [.regularExpression, .caseInsensitive])
        // Leading track numbers with punctuation: "01 - ", "1. ", "03_" (but not "1984" or "7 Habits").
        s = s.replacingOccurrences(of: #"^\s*\d{1,3}\s*[-.)]\s+"#, with: "", options: .regularExpression)

        // "Author - Title" or "Title - Author" when the author is known.
        if let author, !author.isEmpty, author.lowercased() != "unknown author" {
            let parts = s.components(separatedBy: " - ").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 {
                if parts[0].caseInsensitiveCompare(author) == .orderedSame { s = parts[1] }
                else if parts[1].caseInsensitiveCompare(author) == .orderedSame { s = parts[0] }
            }
        }

        s = s.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: " -–—_.,:;|").union(.whitespacesAndNewlines))
        if s.isEmpty { return raw }
        // "harry potter and the chamber of secrets" → "Harry Potter and the Chamber of Secrets".
        return s == s.lowercased() ? titleCased(s) : s
    }

    private static let minorWords: Set<String> = ["a", "an", "and", "as", "at", "but", "by", "for", "in", "of", "on", "or", "the", "to", "with"]

    static func titleCased(_ s: String) -> String {
        s.split(separator: " ").enumerated().map { index, word in
            let w = String(word)
            return index > 0 && minorWords.contains(w) ? w : w.prefix(1).uppercased() + w.dropFirst()
        }.joined(separator: " ")
    }

    /// The title without any bracketed part, for searching: extra words in brackets
    /// would otherwise stop the store finding the book.
    static func searchCore(_ cleaned: String) -> String {
        let core = cleaned
            .replacingOccurrences(of: #"\s*[\(\[\{][^\)\]\}]*[\)\]\}]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " -–—_.,:;|").union(.whitespaces))
        return core.isEmpty ? cleaned : core
    }

    /// Splits "The Way of Kings: The Stormlight Archive, Book 1" into title and series.
    static func splitSeries(_ title: String) -> (title: String, series: String?) {
        let patterns = [
            #"^(.+?)\s*\(([^()]+?),?\s+(?:Book|Volume|Vol\.?|#)\s*(\d+)\)$"#,  // Title (Series, Book 1)
            #"^(.+?):\s*([^:]+?),?\s+(?:Book|Volume|Vol\.?|#)\s*(\d+)$"#,      // Title: Series, Book 1
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
                  let t = Range(match.range(at: 1), in: title),
                  let s = Range(match.range(at: 2), in: title),
                  let n = Range(match.range(at: 3), in: title) else { continue }
            return (String(title[t]).trimmingCharacters(in: .whitespaces), "\(title[s]), Book \(title[n])")
        }
        return (title, nil)
    }
}

private extension String {
    /// Regex replace with a per-match condition on capture group 1.
    func replacingOccurrences(of pattern: String, with replacement: String, options: NSRegularExpression.Options = [],
                              where keep: (String) -> Bool) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return self }
        let source = self as NSString
        let result = NSMutableString(string: source)
        // Back to front, so earlier ranges stay valid while later ones are replaced.
        for match in regex.matches(in: self, range: NSRange(location: 0, length: source.length)).reversed()
        where keep(source.substring(with: match.range(at: 1))) {
            result.replaceCharacters(in: match.range, with: replacement)
        }
        return result as String
    }
}

// MARK: - Online lookup

/// A country's Apple Books store. Each has its own editions, so covers differ (UK vs US especially).
enum CoverRegion: String, CaseIterable, Identifiable, Sendable {
    case gb, us, ca, au, ie, nz, `in`
    var id: String { rawValue }
    var label: String {
        switch self {
        case .gb: return "UK"
        case .us: return "US"
        case .ca: return "Canada"
        case .au: return "Australia"
        case .ie: return "Ireland"
        case .nz: return "New Zealand"
        case .in: return "India"
        }
    }
    var storeName: String { "Apple Books \(label)" }

    /// The Audible store for this country (Ireland uses the UK store, New Zealand the Australian).
    var audibleDomain: String {
        switch self {
        case .gb, .ie: return "co.uk"
        case .us: return "com"
        case .ca: return "ca"
        case .au, .nz: return "com.au"
        case .in: return "in"
        }
    }
    var audibleName: String {
        switch self {
        case .gb, .ie: return "Audible UK"
        case .us: return "Audible US"
        case .ca: return "Audible Canada"
        case .au, .nz: return "Audible Australia"
        case .in: return "Audible India"
        }
    }

    /// Used until the user picks another default in Settings.
    static let standard: CoverRegion = .gb
}

/// Where a lookup searches: one of the Apple Books stores, or Open Library.
enum MetadataSource: Hashable, Identifiable, Sendable {
    case apple(CoverRegion)
    case audible(CoverRegion)
    case openLibrary

    var id: String { label }
    var label: String {
        switch self {
        case .apple(let region): return region.storeName
        case .audible(let region): return region.audibleName
        case .openLibrary: return "Open Library"
        }
    }
    static let all: [MetadataSource] = CoverRegion.allCases.map { .apple($0) } + [.openLibrary]
}

struct MetadataMatch: Identifiable, Sendable {
    var id = UUID()
    var title: String
    var author: String?
    var series: String?
    var genre: String?
    var year: String?
    var publisher: String?
    var summary: String?
    var coverURL: URL?
    var source: MetadataSource
    var edition: Edition = .audiobook

    /// Audiobook art often adds "Narrated by …"; covers are only taken from ebook and print
    /// editions, which carry the publisher's own artwork.
    enum Edition: Sendable { case audiobook, ebook, print }
}

enum MetadataLookup {
    static func search(_ query: String, source: MetadataSource) async -> [MetadataMatch]? {
        switch source {
        case .apple(let region): return await searchApple(query, region: region)
        case .audible(let region): return await searchAudible(query, region: region)
        case .openLibrary: return await searchOpenLibrary(query)
        }
    }

    /// Apple's store search. Each country store has its own editions, so US and UK covers differ.
    /// Returns nil when the request failed (e.g. offline), [] when nothing matched.
    static func searchApple(_ query: String, region: CoverRegion) async -> [MetadataMatch]? {
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: query),
            URLQueryItem(name: "media", value: "audiobook"),
            URLQueryItem(name: "entity", value: "audiobook"),
            URLQueryItem(name: "country", value: region.rawValue),
            URLQueryItem(name: "limit", value: "15"),
        ]
        guard let url = components.url, let json = await fetchJSON(url),
              let results = json["results"] as? [[String: Any]] else { return nil }

        return results.compactMap { item in
            guard let rawTitle = item["collectionName"] as? String else { return nil }
            let split = TitleCleaner.splitSeries(TitleCleaner.clean(rawTitle))
            var cover: URL?
            if let art = item["artworkUrl100"] as? String {
                // The same image is served at any size; ask for a large one.
                cover = URL(string: art.replacingOccurrences(of: "100x100bb", with: Self.appleArtworkSize))
            }
            var publisher: String?
            if let copyright = item["copyright"] as? String {
                publisher = copyright
                    .replacingOccurrences(of: #"^(℗|©|\(c\)|\(p\))?\s*(\d{4})?\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
                    .trimmingCharacters(in: .whitespaces)
                if publisher?.isEmpty == true { publisher = nil }
            }
            return MetadataMatch(
                title: split.title,
                author: item["artistName"] as? String,
                series: split.series,
                genre: item["primaryGenreName"] as? String,
                year: (item["releaseDate"] as? String).map { String($0.prefix(4)) },
                publisher: publisher,
                summary: (item["description"] as? String).map(plainText).flatMap(withoutNarration).flatMap(englishOnly),
                coverURL: cover,
                source: .apple(region))
        }
    }

    /// Audible's store search (no account needed). Audible covers are the audiobook's own square
    /// artwork. Returns nil when the request failed, [] when nothing matched.
    static func searchAudible(_ query: String, region: CoverRegion) async -> [MetadataMatch]? {
        var components = URLComponents(string: "https://api.audible.\(region.audibleDomain)/1.0/catalog/products")!
        components.queryItems = [
            URLQueryItem(name: "keywords", value: query),
            URLQueryItem(name: "num_results", value: "15"),
            URLQueryItem(name: "products_sort_by", value: "Relevance"),
            URLQueryItem(name: "response_groups", value: "contributors,media,product_attrs,product_desc,series"),
            URLQueryItem(name: "image_sizes", value: "500,1024,2400"),
        ]
        guard let url = components.url, let json = await fetchJSON(url),
              let products = json["products"] as? [[String: Any]] else { return nil }

        return products.compactMap { item in
            guard let rawTitle = item["title"] as? String else { return nil }
            // The biggest image offered, then without its size code: Amazon serves the original.
            var cover: URL?
            if let images = item["product_images"] as? [String: String],
               let biggest = images.max(by: { (Int($0.key) ?? 0) < (Int($1.key) ?? 0) })?.value {
                cover = URL(string: biggest.replacingOccurrences(of: #"\._[A-Z]{2}\d+_(?=\.)"#, with: "",
                                                                 options: .regularExpression))
            }
            let authors = (item["authors"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
            let series = (item["series"] as? [[String: Any]])?.first.flatMap { entry -> String? in
                guard let name = entry["title"] as? String else { return nil }
                if let number = entry["sequence"] as? String, !number.isEmpty { return "\(name), Book \(number)" }
                return name
            }
            let summary = (item["merchandising_summary"] as? String ?? item["publisher_summary"] as? String)
                .map(plainText).flatMap(withoutNarration).flatMap(englishOnly)
            return MetadataMatch(
                title: TitleCleaner.clean(rawTitle),
                author: authors.isEmpty ? nil : authors.joined(separator: ", "),
                series: series,
                genre: nil,
                year: (item["release_date"] as? String).map { String($0.prefix(4)) },
                publisher: item["publisher_name"] as? String,
                summary: summary,
                coverURL: cover,
                source: .audible(region),
                edition: .audiobook)
        }
    }

    /// Audiobook covers (Audible's, then Apple Books' audiobook art) of this exact book, from the
    /// preferred store first. Square, and made for audiobooks. Nil only if every request failed.
    static func audiobookCoverOptions(title: String, author: String?, preferred: CoverRegion) async -> [MetadataMatch]? {
        let query = [TitleCleaner.searchCore(title), author].compactMap { $0 }.joined(separator: " ")
        // One request per Audible store (several countries share one).
        var audibleStores: [CoverRegion] = []
        for region in [preferred] + CoverRegion.allCases where !audibleStores.contains(where: { $0.audibleDomain == region.audibleDomain }) {
            audibleStores.append(region)
        }
        let appleStores = [preferred] + CoverRegion.allCases.filter { $0 != preferred }.prefix(2)
        let sources: [MetadataSource] = audibleStores.map { .audible($0) } + appleStores.map { .apple($0) }

        var results = [[MetadataMatch]?](repeating: nil, count: sources.count)
        await withTaskGroup(of: (Int, [MetadataMatch]?).self) { group in
            for (i, source) in sources.enumerated() {
                group.addTask { (i, await search(query, source: source)) }
            }
            for await (i, result) in group { results[i] = result }
        }
        if results.allSatisfy({ $0 == nil }) { return nil }

        var seen = Set<String>()
        var options: [MetadataMatch] = []
        for match in results.compactMap({ $0 }).joined()
        where match.coverURL != nil && isSameBook(match, title: title, author: author) {
            if seen.insert(imageKey(match.coverURL!)).inserted { options.append(match) }
        }
        return options
    }

    /// Apple Books' ebook listing: the publisher's own cover (e.g. Bloomsbury in the UK store,
    /// Scholastic in the US store), without audiobook branding.
    static func searchAppleEbooks(_ query: String, region: CoverRegion) async -> [MetadataMatch]? {
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: query),
            URLQueryItem(name: "media", value: "ebook"),
            URLQueryItem(name: "entity", value: "ebook"),
            URLQueryItem(name: "country", value: region.rawValue),
            URLQueryItem(name: "limit", value: "15"),
        ]
        guard let url = components.url, let json = await fetchJSON(url),
              let results = json["results"] as? [[String: Any]] else { return nil }

        return results.compactMap { item in
            guard let rawTitle = item["trackName"] as? String,
                  let art = item["artworkUrl100"] as? String else { return nil }
            let split = TitleCleaner.splitSeries(TitleCleaner.clean(rawTitle))
            let genre = (item["genres"] as? [String])?.first { $0 != "Books" }
            return MetadataMatch(
                title: split.title,
                author: item["artistName"] as? String,
                series: split.series,
                genre: genre,
                year: (item["releaseDate"] as? String).map { String($0.prefix(4)) },
                summary: (item["description"] as? String).map(plainText).flatMap(englishOnly),
                coverURL: URL(string: art.replacingOccurrences(of: "100x100bb", with: Self.appleArtworkSize)),
                source: .apple(region),
                edition: .ebook)
        }
    }

    /// The publisher's edition of this exact book: the ebook in the given store first, then a
    /// couple of other English stores, then an Open Library print edition. Its cover is the
    /// publisher's artwork and its description is about the book, not the narration.
    static func publisherEdition(title: String, author: String?, region: CoverRegion) async -> MetadataMatch? {
        let query = [TitleCleaner.searchCore(title), author].compactMap { $0 }.joined(separator: " ")
        for store in [region] + CoverRegion.allCases.filter({ $0 != region }).prefix(2) {
            if let found = await searchAppleEbooks(query, region: store)?
                .first(where: { $0.coverURL != nil && isSameBook($0, title: title, author: author) }) {
                return found
            }
        }
        return await openLibraryEditionCovers(title: title, author: author)?.first
    }

    static func publisherCover(title: String, author: String?, region: CoverRegion) async -> URL? {
        await publisherEdition(title: title, author: author, region: region)?.coverURL
    }

    /// The physical book's description (the publisher's blurb, as on Goodreads), from the book's
    /// Open Library work. Falls back to `fallback` (ebook or audiobook text) with sentences about
    /// the narration or the ebook format removed.
    static func bookDescription(title: String, author: String?, fallback: String?) async -> String? {
        if let printed = await openLibraryWorkDescription(title: title, author: author) { return printed }
        return fallback.flatMap(withoutNarration).flatMap(englishOnly)
    }

    /// The text if it's in English, else nil (some listings carry a Spanish, French… description).
    static func englishOnly(_ text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        // Short texts can be ambiguous: English only needs to be the most likely language.
        return recognizer.dominantLanguage == .english ? text : nil
    }

    private static func openLibraryWorkDescription(title: String, author: String?) async -> String? {
        var components = URLComponents(string: "https://openlibrary.org/search.json")!
        var items = [URLQueryItem(name: "title", value: TitleCleaner.searchCore(title)),
                     URLQueryItem(name: "limit", value: "5"),
                     URLQueryItem(name: "fields", value: "key,title,author_name")]
        if let author, author.lowercased() != "unknown author" { items.append(URLQueryItem(name: "author", value: author)) }
        components.queryItems = items
        guard let url = components.url, let json = await fetchJSON(url),
              let docs = json["docs"] as? [[String: Any]] else { return nil }

        for doc in docs.prefix(3) {
            guard let key = doc["key"] as? String, let workTitle = doc["title"] as? String else { continue }
            let probe = MetadataMatch(title: workTitle, author: (doc["author_name"] as? [String])?.first, source: .openLibrary)
            guard isSameBook(probe, title: title, author: author),
                  let workURL = URL(string: "https://openlibrary.org\(key).json"),
                  let work = await fetchJSON(workURL) else { continue }
            let raw = (work["description"] as? String) ?? ((work["description"] as? [String: Any])?["value"] as? String)
            if let raw, let text = cleanOpenLibraryText(raw).flatMap(englishOnly), text.count >= 60 { return text }
        }
        return nil
    }

    /// Open Library descriptions are Markdown and sometimes end with a "----" block of links or sources.
    private static func cleanOpenLibraryText(_ raw: String) -> String? {
        var text = raw.replacingOccurrences(of: "\r\n", with: "\n")
        if let rule = text.range(of: #"\n\s*-{3,}"#, options: .regularExpression) { text = String(text[..<rule.lowerBound]) }
        text = text.replacingOccurrences(of: #"\(\[[^\]]*\]\[\d+\]\)"#, with: "", options: .regularExpression) // ([source][1])
        text = text.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]*\)"#, with: "$1", options: .regularExpression) // [text](url)
        text = text.replacingOccurrences(of: #"\[([^\]]+)\]\[\d+\]"#, with: "$1", options: .regularExpression)  // [text][1]
        text = text.replacingOccurrences(of: #"[*_]{1,2}([^*_]+)[*_]{1,2}"#, with: "$1", options: .regularExpression)
        // Footnote links ("  [1]: https://…") and the "Source" line that introduces them.
        text = text.replacingOccurrences(of: #"(?m)^\s*\[\d+\]:\s*\S+.*$"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?im)^\s*\(?(source|sources)\)?:?\s*$"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Store descriptions mix in the format: narration ("Stephen Fry brings these stories to
    /// life…", "Audiobook of the Year") or the ebook ("the Harry Potter eBooks never fail…").
    /// Drops those sentences; nil if nothing about the book is left.
    static func withoutNarration(_ text: String) -> String? {
        let markers = ["narrat", "read by", "performance", "performed", "listen", "audiobook", "audio book",
                       "audible", "audie award", "recording", "your ears", "voice", "unabridged",
                       "ebook", "e-book", "kindle", "digital edition", "enhanced edition"]
        let paragraphs = text.components(separatedBy: "\n").compactMap { paragraph -> String? in
            var sentences: [String] = []
            paragraph.enumerateSubstrings(in: paragraph.startIndex..., options: .bySentences) { sentence, _, _, _ in
                guard let sentence else { return }
                let lower = sentence.lowercased()
                if !markers.contains(where: lower.contains) { sentences.append(sentence) }
            }
            let kept = sentences.joined().trimmingCharacters(in: .whitespacesAndNewlines)
            return kept.isEmpty ? nil : kept
        }
        let result = paragraphs.joined(separator: "\n\n")
        return result.count < 40 ? nil : result
    }

    /// Open Library: broader catalogue (print editions), used when Apple has no match.
    static func searchOpenLibrary(_ query: String) async -> [MetadataMatch]? {
        var components = URLComponents(string: "https://openlibrary.org/search.json")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "15"),
            URLQueryItem(name: "fields", value: "title,author_name,first_publish_year,cover_i,publisher,subject"),
        ]
        guard let url = components.url, let json = await fetchJSON(url),
              let docs = json["docs"] as? [[String: Any]] else { return nil }

        return docs.compactMap { doc in
            guard let title = doc["title"] as? String else { return nil }
            let cover = (doc["cover_i"] as? Int).flatMap { URL(string: "https://covers.openlibrary.org/b/id/\($0)-L.jpg") }
            return MetadataMatch(
                title: title,
                author: (doc["author_name"] as? [String])?.first,
                genre: (doc["subject"] as? [String])?.first,
                year: (doc["first_publish_year"] as? Int).map(String.init),
                publisher: (doc["publisher"] as? [String])?.first,
                coverURL: cover,
                source: .openLibrary,
                edition: .print)
        }
    }

    /// The match that fits the title (and author, when known) well enough to trust, or nil.
    static func bestMatch(in matches: [MetadataMatch], title: String, author: String?) -> MetadataMatch? {
        let query = words(title)
        let authorWords = words(author ?? "")
        guard !query.isEmpty else { return nil }

        var best: (match: MetadataMatch, score: Double)?
        for match in matches {
            let candidate = words(match.title)
            guard !candidate.isEmpty else { continue }
            let shared = Double(candidate.intersection(query).count)
            // How much of the candidate's title is in ours, and how much of ours is explained
            // by the candidate's title plus author (file names often hold "Author - Title").
            let titleCovered = shared / Double(candidate.count)
            let queryExplained = Double(query.intersection(candidate.union(words(match.author ?? ""))).count) / Double(query.count)
            var score = 0.6 * titleCovered + 0.4 * queryExplained
            if !authorWords.isEmpty {
                let matchAuthor = words(match.author ?? "")
                score += matchAuthor.intersection(authorWords).isEmpty ? -0.3 : 0.15
            }
            if score > (best?.score ?? 0) { best = (match, score) }
        }
        guard let best, best.score >= 0.75 else { return nil }
        return best.match
    }

    // MARK: Same-book matching

    /// The title reduced to what must match exactly: cleaned, without brackets or a ": subtitle",
    /// lowercased, without punctuation. "Harry Potter and the Chamber of Secrets [Opus Encode]"
    /// and "Harry Potter and the Chamber of Secrets: Book 2" give the same key.
    static func titleKey(_ title: String) -> String {
        var core = TitleCleaner.searchCore(TitleCleaner.splitSeries(TitleCleaner.clean(title)).title)
        if let colon = core.firstIndex(of: ":") { core = String(core[..<colon]) }
        let folded = core.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "\u{2019}", with: "")
            .replacingOccurrences(of: "&", with: " and ")
        return folded.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Same title, and the same author when the author is known: rules out summaries,
    /// parodies, podcasts and other books that only share words.
    static func isSameBook(_ match: MetadataMatch, title: String, author: String?) -> Bool {
        guard titleKey(match.title) == titleKey(title) else { return false }
        guard let author, !author.isEmpty, author.lowercased() != "unknown author" else { return true }
        let wanted = words(author).filter { $0.count > 1 }
        let found = words(match.author ?? "").filter { $0.count > 1 }
        return !wanted.isDisjoint(with: found)
    }

    // MARK: Covers from every English edition

    /// Every publisher cover of this exact book: the ebook editions in all the English-language
    /// Apple stores, plus English print editions (Bloomsbury, Scholastic, …) from Open Library.
    /// Audiobook art (often "Narrated by …") is not offered.
    /// Duplicates are removed. Nil only if every request failed (offline).
    static func coverOptions(title: String, author: String?, preferred: CoverRegion) async -> [MetadataMatch]? {
        let query = [TitleCleaner.searchCore(title), author].compactMap { $0 }.joined(separator: " ")
        let stores = [preferred] + CoverRegion.allCases.filter { $0 != preferred }

        async let print = openLibraryEditionCovers(title: title, author: author)
        var storeResults: [[MetadataMatch]?] = []
        await withTaskGroup(of: (Int, [MetadataMatch]?).self) { group in
            for (i, store) in stores.enumerated() {
                group.addTask { (i, await searchAppleEbooks(query, region: store)) }
            }
            var collected = [[MetadataMatch]?](repeating: nil, count: stores.count)
            for await (i, result) in group { collected[i] = result }
            storeResults = collected
        }
        let printResults = await print

        if storeResults.allSatisfy({ $0 == nil }) && printResults == nil { return nil }

        var seen = Set<String>()
        var options: [MetadataMatch] = []
        for match in storeResults.compactMap({ $0 }).joined() + (printResults ?? [])
        where match.coverURL != nil && isSameBook(match, title: title, author: author) {
            if seen.insert(imageKey(match.coverURL!)).inserted { options.append(match) }
        }
        return options
    }

    /// Book details (from the ebook listings, so descriptions are about the book) from every
    /// English Apple store and Open Library, one row per distinct book.
    static func detailOptions(_ query: String, preferred: CoverRegion) async -> [MetadataMatch]? {
        let stores = [preferred] + CoverRegion.allCases.filter { $0 != preferred }
        var storeResults = [[MetadataMatch]?](repeating: nil, count: stores.count)
        await withTaskGroup(of: (Int, [MetadataMatch]?).self) { group in
            for (i, store) in stores.enumerated() {
                group.addTask { (i, await searchAppleEbooks(query, region: store)) }
            }
            for await (i, result) in group { storeResults[i] = result }
        }
        let printResults = await searchOpenLibrary(query)
        if storeResults.allSatisfy({ $0 == nil }) && printResults == nil { return nil }

        var seen = Set<String>()
        var options: [MetadataMatch] = []
        for match in storeResults.compactMap({ $0 }).joined() + (printResults ?? []) {
            let key = titleKey(match.title) + "|" + words(match.author ?? "").sorted().joined(separator: " ")
            if seen.insert(key).inserted { options.append(match) }
        }
        return options
    }

    /// The same image is served from different URLs (sizes, stores); compare without the size part.
    private static func imageKey(_ url: URL) -> String {
        url.deletingLastPathComponent().path + "/" + url.lastPathComponent
            .replacingOccurrences(of: #"\d+x\d+bb"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"-[SML]\.jpg$"#, with: "", options: .regularExpression)
    }

    private static let libraryBinders = ["follett", "turtleback", "perfection learning", "paw prints", "demco",
                                         "san val", "bound to stay bound", "midwest tape", "library binding", "topeka"]

    /// English print editions of the book on Open Library, each with its own cover and publisher.
    static func openLibraryEditionCovers(title: String, author: String?) async -> [MetadataMatch]? {
        var components = URLComponents(string: "https://openlibrary.org/search.json")!
        var items = [URLQueryItem(name: "title", value: TitleCleaner.searchCore(title)),
                     URLQueryItem(name: "limit", value: "5"),
                     URLQueryItem(name: "fields", value: "key,title,author_name")]
        if let author, author.lowercased() != "unknown author" { items.append(URLQueryItem(name: "author", value: author)) }
        components.queryItems = items
        guard let url = components.url, let json = await fetchJSON(url),
              let docs = json["docs"] as? [[String: Any]] else { return nil }

        // The works that are this book (an exact title, by this author).
        let works: [(key: String, author: String?)] = docs.compactMap { doc in
            guard let key = doc["key"] as? String, let workTitle = doc["title"] as? String else { return nil }
            let workAuthor = (doc["author_name"] as? [String])?.first
            let probe = MetadataMatch(title: workTitle, author: workAuthor, source: .openLibrary)
            return isSameBook(probe, title: title, author: author) ? (key, workAuthor) : nil
        }

        var covers: [MetadataMatch] = []
        var seenCovers = Set<Int>()
        // Libraries upload their own photos of the same edition; one per publisher and year is enough.
        var seenEditions = Set<String>()
        for work in works.prefix(2) {
            guard let editionsURL = URL(string: "https://openlibrary.org\(work.key)/editions.json?limit=300"),
                  let json = await fetchJSON(editionsURL),
                  let entries = json["entries"] as? [[String: Any]] else { continue }
            for edition in entries {
                guard let editionTitle = edition["title"] as? String,
                      titleKey(editionTitle) == titleKey(title),
                      let coverID = (edition["covers"] as? [Int])?.first(where: { $0 > 0 }),
                      seenCovers.insert(coverID).inserted else { continue }
                // Only editions marked as English: an unlabelled one can be a translation.
                guard let languages = edition["languages"] as? [[String: String]],
                      languages.contains(where: { $0["key"] == "/languages/eng" }) else { continue }
                // Library rebinds: poor scans, often with barcodes and stickers on the cover.
                let publisher = (edition["publishers"] as? [String])?.first
                if let publisher, libraryBinders.contains(where: { publisher.lowercased().contains($0) }) { continue }
                let editionKey = "\(publisher?.lowercased() ?? "?")|\((edition["publish_date"] as? String) ?? "?")"
                guard seenEditions.insert(editionKey).inserted else { continue }
                var year: String?
                if let date = edition["publish_date"] as? String,
                   let range = date.range(of: #"(1[5-9]|20)\d\d"#, options: .regularExpression) {
                    year = String(date[range])
                }
                covers.append(MetadataMatch(
                    title: editionTitle,
                    author: work.author,
                    year: year,
                    publisher: publisher,
                    coverURL: URL(string: "https://covers.openlibrary.org/b/id/\(coverID)-L.jpg"),
                    source: .openLibrary,
                    edition: .print))
                if covers.count >= 40 { return covers }
            }
        }
        return covers
    }

    /// Apple serves its artwork at any size up to the original; asking for 3000 px returns the
    /// original (it doesn't upscale), which is usually 1,400–2,400 px tall.
    static let appleArtworkSize = "3000x3000bb"

    static func downloadImage(_ url: URL) async -> UIImage? {
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let image = UIImage(data: data), image.size.width > 10 else { return nil }
        return image
    }

    // MARK: Helpers

    private static func fetchJSON(_ url: URL) async -> [String: Any]? {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Prismo-iOS", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static let stopWords: Set<String> = ["the", "a", "an", "of", "and", "&", "in", "on", "to", "by"]

    static func words(_ text: String) -> Set<String> {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\u{2019}", with: "")
        let tokens = folded.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        // "Philosopher's", "philosophers" and "philosopher" count as the same word.
        return Set(tokens.filter { !stopWords.contains($0) }.map { word in
            word.count > 3 && word.hasSuffix("s") && !word.hasSuffix("ss") ? String(word.dropLast()) : word
        })
    }

    /// Store descriptions are HTML; keep the text.
    static func plainText(_ html: String) -> String {
        var s = html.replacingOccurrences(of: #"<br\s*/?>|</p>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        for (entity, char) in ["&amp;": "&", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&lt;": "<", "&gt;": ">", "&nbsp;": " "] {
            s = s.replacingOccurrences(of: entity, with: char)
        }
        s = s.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
