import Foundation

/// Reads ID3v2.3 / ID3v2.4 CHAP frames from an MP3 file.
/// Used as a fallback when AVFoundation doesn't report chapters for an MP3.
enum ID3ChapterParser {
    struct Entry {
        var title: String?
        var start: Double
        var end: Double
    }

    static func parse(url: URL) -> [Entry] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }

        guard let headerData = try? handle.read(upToCount: 10), headerData.count == 10 else { return [] }
        let header = [UInt8](headerData)
        guard header[0] == 0x49, header[1] == 0x44, header[2] == 0x33 else { return [] } // "ID3"
        let major = Int(header[3])
        guard major == 3 || major == 4 else { return [] }
        let flags = header[5]
        let tagSize = synchsafe(header, 6)
        guard tagSize > 0, tagSize <= 64 * 1024 * 1024,
              let tagData = try? handle.read(upToCount: tagSize) else { return [] }

        var tag = [UInt8](tagData)
        if flags & 0x80 != 0 && major == 3 {
            tag = removeUnsynchronisation(tag)
        }

        var offset = 0
        if flags & 0x40 != 0, tag.count >= 4 { // extended header
            offset = major == 4 ? synchsafe(tag, 0) : be32(tag, 0) + 4
        }

        var entries: [Entry] = []
        forEachFrame(in: tag, from: offset, to: tag.count, major: major) { id, start, size in
            guard id == "CHAP" else { return }
            if let entry = parseChapter(tag, start: start, size: size, major: major) {
                entries.append(entry)
            }
        }
        return entries.sorted { $0.start < $1.start }
    }

    // MARK: - Frames

    private static func forEachFrame(in data: [UInt8], from: Int, to end: Int, major: Int,
                                     visit: (String, Int, Int) -> Void) {
        var p = from
        while p + 10 <= end {
            if data[p] == 0 { break } // padding
            guard let id = String(bytes: data[p..<(p + 4)], encoding: .ascii) else { break }
            let size = major == 4 ? synchsafe(data, p + 4) : be32(data, p + 4)
            let bodyStart = p + 10
            guard size >= 0, bodyStart + size <= end else { break }
            visit(id, bodyStart, size)
            p = bodyStart + size
        }
    }

    private static func parseChapter(_ data: [UInt8], start: Int, size: Int, major: Int) -> Entry? {
        let end = start + size
        var p = start
        while p < end && data[p] != 0 { p += 1 } // element ID (null-terminated)
        p += 1
        guard p + 16 <= end else { return nil }
        let startMs = be32(data, p)
        let endMs = be32(data, p + 4)
        p += 16 // start time, end time, start offset, end offset

        var title: String?
        forEachFrame(in: data, from: p, to: end, major: major) { id, s, sz in
            if title == nil, id == "TIT2" {
                title = decodeText(Array(data[s..<(s + sz)]))
            }
        }
        return Entry(title: title, start: Double(startMs) / 1000, end: Double(endMs) / 1000)
    }

    // MARK: - Helpers

    private static func decodeText(_ bytes: [UInt8]) -> String? {
        guard let encoding = bytes.first else { return nil }
        let payload = Array(bytes.dropFirst())
        let decoded: String?
        switch encoding {
        case 0: decoded = String(bytes: payload, encoding: .isoLatin1)
        case 1: decoded = String(bytes: payload, encoding: .utf16)
        case 2: decoded = String(bytes: payload, encoding: .utf16BigEndian)
        default: decoded = String(bytes: payload, encoding: .utf8)
        }
        let cleaned = decoded?
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let cleaned, !cleaned.isEmpty else { return nil }
        return cleaned
    }

    private static func be32(_ d: [UInt8], _ i: Int) -> Int {
        guard i + 4 <= d.count else { return 0 }
        return Int(d[i]) << 24 | Int(d[i + 1]) << 16 | Int(d[i + 2]) << 8 | Int(d[i + 3])
    }

    private static func synchsafe(_ d: [UInt8], _ i: Int) -> Int {
        guard i + 4 <= d.count else { return 0 }
        return Int(d[i] & 0x7F) << 21 | Int(d[i + 1] & 0x7F) << 14 | Int(d[i + 2] & 0x7F) << 7 | Int(d[i + 3] & 0x7F)
    }

    private static func removeUnsynchronisation(_ d: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(d.count)
        var i = 0
        while i < d.count {
            out.append(d[i])
            if d[i] == 0xFF, i + 1 < d.count, d[i + 1] == 0x00 { i += 2 } else { i += 1 }
        }
        return out
    }
}
