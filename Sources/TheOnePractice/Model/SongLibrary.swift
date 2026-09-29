import Foundation

/// Keeps your songs in the app's own folder.
///
/// When you add a MIDI file, a copy is saved inside the app's storage. That way
/// your library keeps working even if you move, rename, or delete the original
/// file — and everything you added is still there next time you open the app.
///
/// On a Mac the folder is out of the way, in
/// `~/Library/Application Support/TheONE Light Practice/Songs`.
///
/// On iPhone and iPad it is the app's own folder in the Files app, because that's
/// how music gets onto the device in the first place: drop a `.mid` file in there
/// and it's in the library next time the app comes to the front.
public struct SongLibrary {

    public enum LibraryError: LocalizedError {
        case couldNotCreateFolder(String)
        case couldNotCopy(String, String)

        public var errorDescription: String? {
            switch self {
            case .couldNotCreateFolder(let why):
                "Could not create the songs folder: \(why)"
            case .couldNotCopy(let name, let why):
                "Could not save \(name): \(why)"
            }
        }
    }

    public let folder: URL

    public init(folder: URL? = nil) {
        // Always use the fully resolved path. Songs are identified by their
        // location, and the same folder can be spelled two ways (/var and
        // /private/var, for instance) — which would let one song appear twice.
        if let folder {
            self.folder = folder.resolvingSymlinksInPath()
        } else {
            self.folder = Self.defaultFolder().resolvingSymlinksInPath()
        }
    }

    private static func defaultFolder() -> URL {
        let fallback = URL(fileURLWithPath: NSTemporaryDirectory())
        #if os(iOS)
        // Documents itself, with no folder inside it: this is what you see when
        // you open the app in Files, so anything dropped in is a song.
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first ?? fallback
        #else
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? fallback
        return support
            .appendingPathComponent("TheONE Light Practice")
            .appendingPathComponent("Songs")
        #endif
    }

    public func createFolderIfNeeded() throws {
        guard !FileManager.default.fileExists(atPath: folder.path) else { return }
        do {
            try FileManager.default.createDirectory(
                at: folder, withIntermediateDirectories: true
            )
        } catch {
            throw LibraryError.couldNotCreateFolder(error.localizedDescription)
        }
    }

    /// Save a copy of a song and return where it was saved.
    ///
    /// If you add the same file twice, the existing copy is reused rather than
    /// making a duplicate. If a *different* song happens to share a name, a number
    /// is added so neither is lost.
    @discardableResult
    public func add(_ source: URL) throws -> URL {
        try createFolderIfNeeded()

        // Some files need permission to be opened before they can be read.
        let needsPermission = source.startAccessingSecurityScopedResource()
        defer { if needsPermission { source.stopAccessingSecurityScopedResource() } }

        let destination = availableName(for: source)
        if destination == nil {
            // An identical copy is already saved, so reuse it.
            return existingIdenticalCopy(of: source) ?? source
        }

        do {
            try FileManager.default.copyItem(at: source, to: destination!)
            return destination!.resolvingSymlinksInPath()
        } catch {
            throw LibraryError.couldNotCopy(
                source.lastPathComponent, error.localizedDescription
            )
        }
    }

    /// Every song saved in the library, newest last.
    public func songs() -> [URL] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return contents
            .map { $0.resolvingSymlinksInPath() }
            .filter { ["mid", "midi"].contains($0.pathExtension.lowercased()) }
            .sorted { a, b in
                a.lastPathComponent.localizedStandardCompare(b.lastPathComponent) == .orderedAscending
            }
    }

    public func remove(_ url: URL) {
        // Only ever delete our own copy, never the file you imported.
        let resolved = url.resolvingSymlinksInPath()
        guard resolved.path.hasPrefix(folder.path) else { return }
        try? FileManager.default.removeItem(at: resolved)
    }

    // MARK: - Naming

    /// A free filename for this song, or nil if an identical copy already exists.
    private func availableName(for source: URL) -> URL? {
        let name = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension.isEmpty ? "mid" : source.pathExtension

        var candidate = folder.appendingPathComponent("\(name).\(ext)")
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            if sameContents(candidate, source) { return nil }
            candidate = folder.appendingPathComponent("\(name) \(counter).\(ext)")
            counter += 1
            if counter > 500 { break }   // give up rather than spin
        }
        return candidate
    }

    private func existingIdenticalCopy(of source: URL) -> URL? {
        songs().first { sameContents($0, source) }
    }

    private func sameContents(_ a: URL, _ b: URL) -> Bool {
        guard let dataA = try? Data(contentsOf: a), let dataB = try? Data(contentsOf: b)
        else { return false }
        return dataA == dataB
    }
}
