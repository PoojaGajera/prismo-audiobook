import Foundation
import AVFoundation
import UIKit

/// Reads duration, tags, artwork and chapter markers from audio files.
enum BookAnalyzer {
    struct FileAnalysis {
        var duration: Double = 0
        var title: String?
        var artist: String?
        var album: String?
        var artwork: Data?
        /// Chapters relative to the start of this file.
        var chapters: [Chapter] = []
    }

    struct AssembledBook {
        var title: String
        var author: String
        var files: [BookFile]
        var chapters: [Chapter]
        var source: ChapterSource
        var duration: Double
        var artwork: Data?
    }

    static func analyze(url: URL) async -> FileAnalysis {
        var result = FileAnalysis()
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])

        if let duration = try? await asset.load(.duration), duration.seconds.isFinite {
            result.duration = duration.seconds
        }

        if let metadata = try? await asset.load(.commonMetadata) {
            result.title = await string(metadata, .commonIdentifierTitle)
            result.artist = await string(metadata, .commonIdentifierArtist)
            result.album = await string(metadata, .commonIdentifierAlbumName)
            if let item = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierArtwork).first {
                result.artwork = try? await item.load(.dataValue)
            }
        }

        // 1) Chapters AVFoundation understands (M4B/M4A/MP4 chapter tracks, some MP3s).
        var chapters = await avFoundationChapters(asset)

        // 2) Fallback: ID3 CHAP frames in MP3 files.
        if chapters.isEmpty, url.pathExtension.lowercased() == "mp3" {
            chapters = ID3ChapterParser.parse(url: url).enumerated().map { index, entry in
                Chapter(title: entry.title ?? "Chapter \(index + 1)",
                        start: entry.start,
                        duration: max(0, entry.end - entry.start))
            }
        }

        result.chapters = normalize(chapters, fileDuration: result.duration)
        return result
    }

    /// Joins one or more analysed files into a single book timeline.
    static func assemble(_ items: [(name: String, info: FileAnalysis)]) -> AssembledBook {
        let stems = items.map { ($0.name as NSString).deletingPathExtension }
        let tagTitles = items.map { $0.info.title ?? "" }
        // For multi-file books, only trust per-file title tags if they're all present and distinct.
        let tagTitlesUsable = !tagTitles.contains("") && Set(tagTitles).count == tagTitles.count

        var files: [BookFile] = []
        var chapters: [Chapter] = []
        var cursor = 0.0
        var foundEmbedded = false

        for (index, item) in items.enumerated() {
            files.append(BookFile(fileName: item.name, start: cursor, duration: item.info.duration))

            if item.info.chapters.count > 1 {
                foundEmbedded = true
                chapters += item.info.chapters.map {
                    Chapter(title: $0.title, start: $0.start + cursor, duration: $0.duration)
                }
            } else {
                let title: String
                if items.count == 1 {
                    title = item.info.chapters.first?.title ?? item.info.title ?? stems[index]
                } else {
                    title = tagTitlesUsable ? tagTitles[index] : stems[index]
                }
                chapters.append(Chapter(title: title, start: cursor, duration: item.info.duration))
            }
            cursor += item.info.duration
        }

        let first = items[0].info
        let bookTitle: String
        if items.count == 1 {
            bookTitle = first.title ?? first.album ?? stems[0]
        } else {
            bookTitle = first.album ?? commonPrefix(stems) ?? stems[0]
        }

        let source: ChapterSource = foundEmbedded ? .embedded : (items.count > 1 ? .perFile : .none)

        return AssembledBook(
            title: bookTitle,
            author: items.lazy.compactMap { $0.info.artist }.first ?? "Unknown Author",
            files: files,
            chapters: chapters,
            source: source,
            duration: cursor,
            artwork: items.lazy.compactMap { $0.info.artwork }.first)
    }

    // MARK: - Private

    private static func avFoundationChapters(_ asset: AVURLAsset) async -> [Chapter] {
        var groups = (try? await asset.loadChapterMetadataGroups(bestMatchingPreferredLanguages: Locale.preferredLanguages)) ?? []
        if groups.isEmpty,
           let locales = try? await asset.load(.availableChapterLocales),
           let locale = locales.first {
            groups = (try? await asset.loadChapterMetadataGroups(withTitleLocale: locale, containingItemsWithCommonKeys: [])) ?? []
        }

        var chapters: [Chapter] = []
        for (index, group) in groups.enumerated() {
            let start = group.timeRange.start.seconds
            let duration = group.timeRange.duration.seconds
            var title = "Chapter \(index + 1)"
            if let item = AVMetadataItem.metadataItems(from: group.items, filteredByIdentifier: .commonIdentifierTitle).first,
               let value = try? await item.load(.stringValue) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { title = trimmed }
            }
            chapters.append(Chapter(title: title,
                                    start: start.isFinite ? start : 0,
                                    duration: duration.isFinite ? duration : 0))
        }
        return chapters
    }

    /// Sorts chapters, removes duplicates, and makes them cover the file end-to-end.
    private static func normalize(_ chapters: [Chapter], fileDuration: Double) -> [Chapter] {
        let sorted = chapters
            .filter { $0.start.isFinite && $0.start >= 0 && (fileDuration <= 0 || $0.start < fileDuration) }
            .sorted { $0.start < $1.start }

        var result: [Chapter] = []
        for chapter in sorted {
            if let last = result.last, abs(last.start - chapter.start) < 0.5 { continue }
            result.append(chapter)
        }
        guard !result.isEmpty else { return [] }

        result[0].start = 0
        for i in result.indices {
            let end = i + 1 < result.count ? result[i + 1].start : fileDuration
            result[i].duration = max(0, end - result[i].start)
        }
        return result
    }

    private static func string(_ items: [AVMetadataItem], _ identifier: AVMetadataIdentifier) async -> String? {
        guard let item = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier).first,
              let value = try? await item.load(.stringValue) else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func commonPrefix(_ names: [String]) -> String? {
        guard var prefix = names.first else { return nil }
        for name in names.dropFirst() {
            while !name.hasPrefix(prefix) && !prefix.isEmpty { prefix.removeLast() }
        }
        let cleaned = prefix.trimmingCharacters(in: CharacterSet(charactersIn: " -_.0123456789"))
        return cleaned.count >= 3 ? cleaned : nil
    }
}

enum ImageUtils {
    /// Covers are stored up to this size (Apple's originals are usually 1,400–2,400 px tall),
    /// so they stay sharp on the full-width player cover (~1,100 px wide on a 3× phone).
    static let coverPixels: CGFloat = 3000

    static func jpegData(_ image: UIImage, maxDimension: CGFloat, quality: CGFloat = 0.85) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(1, maxDimension / max(size.width, size.height))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return rendered.jpegData(compressionQuality: quality)
    }
}
