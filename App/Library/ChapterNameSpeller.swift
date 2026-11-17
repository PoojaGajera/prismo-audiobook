import Foundation

/// Makes the names in found chapter titles consistent. Speech recognition can spell the same name
/// differently each time it's read ("Chapter 3: Bri", "Chapter 5: Bree", "Chapter 7: Brie"), which
/// matters most in books whose chapters are named after the character telling them.
///
/// Words in the names that sound alike (same consonants, at most two letters apart) are treated
/// as one name and given one spelling:
/// 1. the spelling used in the book's own details (title, summary, author), if it's there;
/// 2. otherwise the spelling heard most often;
/// 3. otherwise, with three or more spellings, the one closest to all the others.
/// Two spellings heard equally often, with nothing else to go on, are left alone.
enum ChapterNameSpeller {
    static func unify(_ chapters: [Chapter], book: Book) -> [Chapter] {
        let known = [book.title, book.summary ?? "", book.series ?? "", book.author].joined(separator: ". ")
        return unify(chapters, knownText: known)
    }

    static func unify(_ chapters: [Chapter], knownText: String) -> [Chapter] {
        // "Chapter 12: Brie" → prefix "Chapter 12: ", name "Brie". Other titles are left alone.
        let parts: [(prefix: String, name: String)?] = chapters.map { chapter in
            guard ChapterDetector.chapterNumber(inTitle: chapter.title) != nil,
                  let colon = chapter.title.range(of: ": ") else { return nil }
            return (String(chapter.title[..<colon.upperBound]), String(chapter.title[colon.upperBound...]))
        }

        // How often each spelling was heard.
        var counts: [String: Int] = [:]
        for part in parts.compactMap({ $0 }) {
            for word in words(in: part.name) { counts[word, default: 0] += 1 }
        }
        guard !counts.isEmpty else { return chapters }

        let known = knownNames(in: knownText)
        var spelling: [String: String] = [:]   // heard (lowercased) → correct spelling

        // Group spellings that sound alike, most heard first.
        var groups: [[String]] = []
        for word in counts.keys.sorted(by: { (counts[$0]!, $0) > (counts[$1]!, $1) }) {
            if let i = groups.firstIndex(where: { group in group.contains { soundAlike($0, word) } }) {
                groups[i].append(word)
            } else {
                groups.append([word])
            }
        }

        for group in groups {
            let display = group.map { displayForm($0, in: parts) }
            var chosen: String?
            // 1. The book's own spelling.
            if let match = known.first(where: { k in group.contains { $0 == k.lowercased() || soundAlike($0, k.lowercased()) } }) {
                chosen = match
            } else if group.count > 1 {
                let heard = group.map { counts[$0]! }
                if heard[0] > heard[1] {
                    chosen = display[0]                                  // 2. heard most often
                } else if group.count >= 3 {
                    let best = group.indices.min { a, b in             // 3. closest to the rest
                        group.map { distance(group[a], $0) }.reduce(0, +) < group.map { distance(group[b], $0) }.reduce(0, +)
                    }!
                    chosen = display[best]
                }
            }
            guard let chosen else { continue }
            for word in group where word != chosen.lowercased() || displayForm(word, in: parts) != chosen {
                spelling[word] = chosen
            }
        }
        guard !spelling.isEmpty else { return chapters }

        return zip(chapters, parts).map { chapter, part in
            guard let part else { return chapter }
            let name = respelled(part.name, with: spelling)
            guard name != part.name else { return chapter }
            var copy = chapter
            copy.title = part.prefix + name
            return copy
        }
    }

    // MARK: - Words

    private static let ignored: Set<String> = [
        "the", "a", "an", "and", "of", "in", "on", "at", "to", "for", "with", "by", "from", "is", "it",
        "part", "book", "chapter", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
    ]

    /// The words of a name worth comparing, lowercased.
    private static func words(in name: String) -> [String] {
        name.split(whereSeparator: { !$0.isLetter && $0 != "'" })
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "'")).lowercased() }
            .filter { $0.count >= 2 && !ignored.contains($0) }
    }

    /// How a word was written in the titles ("Brie", not "brie").
    private static func displayForm(_ word: String, in parts: [(prefix: String, name: String)?]) -> String {
        for part in parts.compactMap({ $0 }) {
            for token in part.name.split(whereSeparator: { !$0.isLetter && $0 != "'" }) where token.lowercased() == word {
                return String(token)
            }
        }
        return word.capitalized
    }

    /// Names in the book's details: capitalised words that aren't just starting a sentence.
    private static func knownNames(in text: String) -> [String] {
        var names: [String] = []
        var startOfSentence = true
        for token in text.split(whereSeparator: \.isWhitespace) {
            let word = token.trimmingCharacters(in: .punctuationCharacters)
            if let first = word.first, first.isUppercase, word.count >= 2, word.allSatisfy({ $0.isLetter || $0 == "'" }),
               !startOfSentence, !ignored.contains(word.lowercased()), !names.contains(word) {
                names.append(word)
            }
            startOfSentence = token.last.map { ".!?".contains($0) } ?? false
        }
        return names
    }

    private static func respelled(_ name: String, with spelling: [String: String]) -> String {
        var result = ""
        var token = ""
        func flush() {
            if !token.isEmpty {
                result += spelling[token.lowercased()] ?? token
                token = ""
            }
        }
        for character in name {
            if character.isLetter || character == "'" { token.append(character) } else { flush(); result.append(character) }
        }
        flush()
        return result
    }

    // MARK: - Sounding alike

    /// Same consonant sounds and at most two letters different (one, for very short names).
    static func soundAlike(_ a: String, _ b: String) -> Bool {
        guard a != b else { return true }
        let key = consonantKey(a)
        guard key == consonantKey(b), abs(a.count - b.count) <= 2 else { return false }
        return distance(a, b) <= (key.count < 2 ? 1 : 2)
    }

    /// First letter, then the consonants (vowels, h, w and y dropped; doubles collapsed; c/k/q,
    /// s/z and ph/f treated alike). "Brie", "Bree", "Bri" and "Bre" all give "br".
    static func consonantKey(_ word: String) -> String {
        var w = word.lowercased()
        for (from, to) in [("ph", "f"), ("ck", "k"), ("q", "k"), ("c", "k"), ("z", "s"), ("x", "ks")] {
            w = w.replacingOccurrences(of: from, with: to)
        }
        guard let first = w.first else { return "" }
        var key = String(first)
        for character in w.dropFirst() where !"aeiouyhw".contains(character) {
            if key.last != character { key.append(character) }
        }
        return key
    }

    /// Letters to change, add or remove to turn one word into the other.
    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }
        var row = Array(0...b.count)
        for i in 1...a.count {
            var previous = row[0]
            row[0] = i
            for j in 1...b.count {
                let current = row[j]
                row[j] = min(row[j] + 1, row[j - 1] + 1, previous + (a[i - 1] == b[j - 1] ? 0 : 1))
                previous = current
            }
        }
        return row[b.count]
    }
}
