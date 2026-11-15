import Foundation
import UniformTypeIdentifiers

/// Keeps the library in step with a folder the user picked in Files (e.g. "Audiobooks").
///
/// The folder is chosen once; its bookmark is saved so the app can read it again later.
/// Each check (on launch, when the app comes to the front, or pull-to-refresh) imports
/// anything new:
/// - every audio file directly inside the folder is one book;
/// - every subfolder that holds audio files is one book (its files in name order).
///
/// Something counts as already there when a book in the library has the same files
/// (names and sizes), or when that file/folder was handled by an earlier check. The second
/// rule means a book deleted in the app isn't re-added, and adding a file to a folder that
/// was already imported doesn't create a second book.
@MainActor
final class FolderSync: ObservableObject {
    static let shared = FolderSync()

    @Published private(set) var folderName: String?
    @Published private(set) var isSyncing = false
    @Published private(set) var lastChecked: Date?

    private let bookmarkKey = "watchedFolderBookmark"
    private let nameKey = "watchedFolderName"
    private var known: Known

    private struct Known: Codable {
        var keys: Set<String> = []        // paths inside the folder, e.g. "Dune" or "Dune.m4b"
        var signatures: Set<String> = []  // file names + sizes
    }

    /// A book found in the folder.
    private struct Candidate: Sendable {
        var key: String
        var files: [URL]
        var signature: String
        /// Set for a subfolder book: its name is the fallback title.
        var folderName: String?
    }

    private struct Scan: Sendable {
        var candidates: [Candidate] = []
        var downloading = 0
    }

    private var knownURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Library/folder-sync.json")
    }

    private init() {
        folderName = UserDefaults.standard.string(forKey: nameKey)
        known = Known()
        if let data = try? Data(contentsOf: knownURL),
           let saved = try? JSONDecoder().decode(Known.self, from: data) {
            known = saved
        }
    }

    var isWatching: Bool { folderName != nil }

    // MARK: - Choosing the folder

    func choose(_ url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
            UserDefaults.standard.set(url.lastPathComponent, forKey: nameKey)
            folderName = url.lastPathComponent
        } catch {
            LibraryStore.shared.post("Couldn't remember that folder. \(error.localizedDescription)")
            return
        }
        await sync(announceNothingNew: true)
    }

    func stopWatching() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        UserDefaults.standard.removeObject(forKey: nameKey)
        folderName = nil
        lastChecked = nil
    }

    // MARK: - Checking for new books

    /// Imports new books from the folder. Quiet unless something was added or went wrong,
    /// or `announceNothingNew` asks for a reply either way (e.g. a manual check).
    func sync(announceNothingNew: Bool = false) async {
        guard !isSyncing, let folder = resolveFolder() else { return }
        isSyncing = true
        defer { isSyncing = false }

        let library = LibraryStore.shared
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }

        let scan = await Task.detached { Self.scan(folder) }.value
        let inLibrary = library.fileSignatures()
        let fresh = scan.candidates.filter {
            !known.keys.contains($0.key) && !known.signatures.contains($0.signature) && !inLibrary.contains($0.signature)
        }

        // Books already in the library are remembered too, so moving them around later doesn't matter.
        for candidate in scan.candidates where inLibrary.contains(candidate.signature) {
            known.keys.insert(candidate.key)
            known.signatures.insert(candidate.signature)
        }

        var added: [Book] = []
        for candidate in fresh {
            let files = candidate.files
            let staged = await Task.detached { LibraryStore.stage(files) }.value
            guard !staged.isEmpty else { continue }
            var books = await library.importStaged(staged, asSingleBook: true, announce: false)
            // A folder of files without a title tag would otherwise be named after its first file.
            if let folderTitle = candidate.folderName, let first = files.first {
                let fileTitle = first.deletingPathExtension().lastPathComponent
                for i in books.indices where books[i].title == fileTitle {
                    books[i].title = folderTitle
                    library.update(books[i])
                }
            }
            added += books
            known.keys.insert(candidate.key)
            known.signatures.insert(candidate.signature)
        }
        saveKnown()
        lastChecked = Date()

        let name = folderName ?? "your folder"
        var message: String?
        if added.count == 1, let book = added.first {
            message = "Added “\(TitleCleaner.clean(book.title))” from “\(name)”."
        } else if added.count > 1 {
            message = "Added \(added.count) new books from “\(name)”."
        } else if announceNothingNew {
            message = "No new books in “\(name)”."
        }
        if scan.downloading > 0 {
            let waiting = "\(scan.downloading) file\(scan.downloading == 1 ? " is" : "s are") still downloading from iCloud; they'll be added next time."
            message = message.map { "\($0) \(waiting)" } ?? waiting
        }
        if added.contains(where: { $0.chapterSource == .none && $0.duration >= 2 * ChapterDetector.minimumGap }) {
            message = (message ?? "") + " Looking for chapters in the books that have none."
        }
        if let message { library.post(message) }
    }

    private func resolveFolder() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else {
            LibraryStore.shared.post("Can't open “\(folderName ?? "your folder")” any more. Choose it again in Settings.")
            stopWatching()
            return nil
        }
        if stale {
            let scoped = url.startAccessingSecurityScopedResource()
            if let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                UserDefaults.standard.set(fresh, forKey: bookmarkKey)
            }
            if scoped { url.stopAccessingSecurityScopedResource() }
        }
        return url
    }

    private func saveKnown() {
        if let data = try? JSONEncoder().encode(known) {
            try? data.write(to: knownURL, options: .atomic)
        }
    }

    // MARK: - Reading the folder (off the main thread)

    nonisolated private static func scan(_ root: URL) -> Scan {
        var result = Scan()
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey]
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?

        coordinator.coordinate(readingItemAt: root, options: [], error: &coordinationError) { root in
            /// Audio files directly inside `folder`, plus its subfolders.
            func contents(of folder: URL) -> (audio: [URL], folders: [URL]) {
                guard let items = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys) else { return ([], []) }
                var audio: [URL] = []
                var folders: [URL] = []
                for item in items {
                    let name = item.lastPathComponent
                    if name.hasPrefix(".") {
                        // iCloud keeps files that aren't on the phone yet as ".Name.ext.icloud".
                        if name.hasSuffix(".icloud") {
                            let real = item.deletingLastPathComponent()
                                .appendingPathComponent(String(name.dropFirst().dropLast(".icloud".count)))
                            if isAudio(real) {
                                try? fm.startDownloadingUbiquitousItem(at: real)
                                result.downloading += 1
                            }
                        }
                        continue
                    }
                    if (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                        folders.append(item)
                    } else if isAudio(item) {
                        audio.append(item)
                    }
                }
                return (audio.sorted(by: byName), folders.sorted(by: byName))
            }

            func relative(_ url: URL) -> String {
                let base = root.standardizedFileURL.path
                let path = url.standardizedFileURL.path
                return path.hasPrefix(base) ? String(path.dropFirst(base.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/")) : path
            }

            let top = contents(of: root)
            for file in top.audio {
                result.candidates.append(Candidate(key: relative(file), files: [file], signature: signature([file])))
            }
            // Each subfolder (at any depth) with audio files of its own is one book.
            var pending = top.folders
            while !pending.isEmpty {
                let folder = pending.removeFirst()
                let inside = contents(of: folder)
                if !inside.audio.isEmpty {
                    result.candidates.append(Candidate(key: relative(folder), files: inside.audio, signature: signature(inside.audio),
                                                       folderName: folder.lastPathComponent))
                }
                pending += inside.folders
            }
        }
        return result
    }

    nonisolated private static func byName(_ a: URL, _ b: URL) -> Bool {
        a.lastPathComponent.localizedStandardCompare(b.lastPathComponent) == .orderedAscending
    }

    nonisolated static func isAudio(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ["m4b", "m4a", "mp3", "mp4", "aac", "wav", "aiff", "aif", "caf", "flac"].contains(ext) { return true }
        return UTType(filenameExtension: ext)?.conforms(to: .audio) == true
    }

    /// File names and sizes, in order. The same audio copied anywhere gives the same signature.
    nonisolated static func signature(_ files: [URL]) -> String {
        files.map { url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
            return "\(url.lastPathComponent.lowercased()):\(size)"
        }
        .sorted()
        .joined(separator: "|")
    }
}
