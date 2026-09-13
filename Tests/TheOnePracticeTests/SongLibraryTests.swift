import XCTest
@testable import TheOnePractice

/// Songs are copied into the app's own folder when you add them, so your library
/// keeps working if you move or delete the original file.
final class SongLibraryTests: XCTestCase {

    private var temporary: URL!
    private var library: SongLibrary!

    override func setUpWithError() throws {
        temporary = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SongLibraryTests-\(UUID().uuidString)")
        library = SongLibrary(folder: temporary.appendingPathComponent("Songs"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporary)
    }

    /// A file with recognisable contents, outside the library.
    private func makeSong(named name: String, contents: String = "song") throws -> URL {
        let folder = temporary.appendingPathComponent("Originals")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url
    }

    func testAddingASongCopiesItIntoTheLibrary() throws {
        let original = try makeSong(named: "tune.mid")
        let saved = try library.add(original)

        XCTAssertTrue(saved.path.hasPrefix(library.folder.path), "should live in the library")
        XCTAssertNotEqual(saved, original)
        XCTAssertTrue(FileManager.default.fileExists(atPath: saved.path))
    }

    func testTheCopySurvivesDeletingTheOriginal() throws {
        // The whole point: your library should not break when you tidy up Downloads.
        let original = try makeSong(named: "tune.mid", contents: "keep me")
        let saved = try library.add(original)
        try FileManager.default.removeItem(at: original)

        XCTAssertTrue(FileManager.default.fileExists(atPath: saved.path))
        XCTAssertEqual(try String(contentsOf: saved, encoding: .utf8), "keep me")
    }

    func testAddingTheSameFileTwiceDoesNotDuplicateIt() throws {
        let original = try makeSong(named: "tune.mid")
        let first = try library.add(original)
        let second = try library.add(original)

        XCTAssertEqual(first, second)
        XCTAssertEqual(library.songs().count, 1)
    }

    func testTwoDifferentSongsWithTheSameNameBothSurvive() throws {
        let a = try makeSong(named: "tune.mid", contents: "first")
        try library.add(a)

        let folder = temporary.appendingPathComponent("Elsewhere")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let b = folder.appendingPathComponent("tune.mid")
        try Data("second".utf8).write(to: b)
        let savedB = try library.add(b)

        XCTAssertEqual(library.songs().count, 2, "neither should be overwritten")
        XCTAssertEqual(try String(contentsOf: savedB, encoding: .utf8), "second")
    }

    func testListingReturnsOnlyMidiFiles() throws {
        try library.createFolderIfNeeded()
        try Data("x".utf8).write(to: library.folder.appendingPathComponent("notes.txt"))
        try library.add(try makeSong(named: "tune.mid"))
        try library.add(try makeSong(named: "other.midi", contents: "other"))

        let names = library.songs().map(\.lastPathComponent).sorted()
        XCTAssertEqual(names, ["other.midi", "tune.mid"])
    }

    func testRemovingDeletesTheLibraryCopy() throws {
        let saved = try library.add(try makeSong(named: "tune.mid"))
        library.remove(saved)
        XCTAssertFalse(FileManager.default.fileExists(atPath: saved.path))
        XCTAssertTrue(library.songs().isEmpty)
    }

    func testRemovingWillNotTouchFilesOutsideTheLibrary() throws {
        // Removing a song from the list must never delete the user's own file.
        let original = try makeSong(named: "precious.mid")
        library.remove(original)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: original.path),
            "a file outside the library must be left alone"
        )
    }

    func testTheFolderIsCreatedOnDemand() throws {
        XCTAssertFalse(FileManager.default.fileExists(atPath: library.folder.path))
        try library.add(try makeSong(named: "tune.mid"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: library.folder.path))
    }

    func testListingAnAbsentFolderIsEmptyRatherThanAnError() {
        XCTAssertTrue(library.songs().isEmpty)
    }

    func testDefaultFolderIsInApplicationSupport() {
        let path = SongLibrary().folder.path
        XCTAssertTrue(path.contains("Application Support"))
        XCTAssertTrue(path.hasSuffix("TheONE Light Practice/Songs"))
    }
}
