import XCTest
@testable import TheOnePractice

/// Records what happened, in order, from inside jobs that run concurrently.
@MainActor
private final class Trace {
    private(set) var lines: [String] = []
    func add(_ line: String) { lines.append(line) }
}

@MainActor
final class PlaybackRunnerTests: XCTestCase {

    /// The bug behind seeking during playback: the run being replaced turns its
    /// own notes and lamps off as it unwinds, so if the replacement has already
    /// started, the tidying silences the song that just started instead.
    func testReplacementDoesNotStartUntilTheOldJobHasUnwound() async {
        let runner = PlaybackRunner()
        let trace = Trace()

        runner.replace {
            trace.add("first started")
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(2))
            }
            // Standing in for "turn off whatever this run left lit and sounding".
            trace.add("first tidied up")
        }
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(20))

        runner.replace { trace.add("second started") }
        await runner.settle()

        XCTAssertEqual(trace.lines, ["first started", "first tidied up", "second started"])
    }

    /// Dragging the timeline seeks over and over. Only the last one should play,
    /// and it should still come last.
    func testOnlyTheLastOfManyReplacementsRuns() async {
        let runner = PlaybackRunner()
        let trace = Trace()

        runner.replace {
            trace.add("a started")
            while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(2)) }
            trace.add("a tidied up")
        }
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(20))

        for name in ["b", "c", "d"] {
            runner.replace { trace.add("\(name) started") }
        }
        await runner.settle()

        XCTAssertEqual(trace.lines, ["a started", "a tidied up", "d started"])
    }

    func testCancelLetsTheJobUnwindAndKeepsTheOrderForWhateverComesNext() async {
        let runner = PlaybackRunner()
        let trace = Trace()

        runner.replace {
            trace.add("started")
            while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(2)) }
            trace.add("tidied up")
        }
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(20))

        runner.cancel()
        runner.replace { trace.add("next started") }
        await runner.settle()

        XCTAssertEqual(trace.lines, ["started", "tidied up", "next started"])
    }

    func testAJobThatFinishesOnItsOwnDoesNotHoldUpTheNextOne() async {
        let runner = PlaybackRunner()
        let trace = Trace()

        runner.replace { trace.add("first") }
        await runner.settle()
        runner.replace { trace.add("second") }
        await runner.settle()

        XCTAssertEqual(trace.lines, ["first", "second"])
    }
}

@MainActor
final class SeekAndResumeTests: XCTestCase {

    private func makeModel() throws -> (PracticeModel, URL) {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("seek-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let song = folder.appendingPathComponent("scale.mid")
        try MIDIBuilder.scaleFile().write(to: song)

        let model = PracticeModel(library: SongLibrary(folder: folder))
        return (model, folder)
    }

    /// Dragging the timeline and pressing Start used to replay from the beginning,
    /// while the screen said it would carry on from where you left it.
    func testStartCarriesOnFromWhereTheTimelineWasLeft() throws {
        let (model, folder) = try makeModel()
        defer { try? FileManager.default.removeItem(at: folder) }

        XCTAssertNotNil(model.lesson, "the one song in the library should be selected")
        model.seek(toStep: 4)
        XCTAssertEqual(model.session?.index, 4)

        let resumed = model.resumedSession(for: try XCTUnwrap(model.lesson))
        XCTAssertEqual(resumed.index, 4)
        XCTAssertEqual(resumed.stepsCompleted, 0, "skipping ahead is not the same as playing it")
    }

    /// A song you played to the end starts again from the top, rather than
    /// starting finished.
    func testStartingAFinishedSongBeginsAgain() throws {
        let (model, folder) = try makeModel()
        defer { try? FileManager.default.removeItem(at: folder) }

        let lesson = try XCTUnwrap(model.lesson)
        model.seek(toStep: lesson.steps.count - 1)
        var finished = try XCTUnwrap(model.session)
        finished.seek(to: lesson.steps.count)
        XCTAssertTrue(finished.isFinished)

        model.seek(toStep: lesson.steps.count - 1)
        XCTAssertEqual(model.resumedSession(for: lesson).index, lesson.steps.count - 1)
    }

    func testSeekingPastTheEndLandsOnTheLastStep() throws {
        let (model, folder) = try makeModel()
        defer { try? FileManager.default.removeItem(at: folder) }

        let lesson = try XCTUnwrap(model.lesson)
        model.seek(toFraction: 1)
        XCTAssertEqual(model.session?.index, lesson.steps.count - 1)
        model.seek(toFraction: -3)
        XCTAssertEqual(model.session?.index, 0)
    }

    /// Stop has the last word on what the screen says, because the run it cancels
    /// deliberately stays quiet.
    func testStopSaysSoOnlyWhenSomethingWasRunning() throws {
        let (model, folder) = try makeModel()
        defer { try? FileManager.default.removeItem(at: folder) }

        let described = model.statusMessage
        model.stop()
        XCTAssertEqual(model.statusMessage, described,
                       "stopping what was never started should not report a stop")
    }

    func testRescanPicksUpSongsAddedOutsideTheApp() throws {
        let (model, folder) = try makeModel()
        defer { try? FileManager.default.removeItem(at: folder) }

        XCTAssertEqual(model.songs.count, 1)
        try MIDIBuilder.scaleFile().write(to: folder.appendingPathComponent("another.mid"))
        model.rescanLibrary()
        XCTAssertEqual(model.songs.map(\.title).sorted(), ["another", "scale"])

        try FileManager.default.removeItem(at: folder.appendingPathComponent("another.mid"))
        model.rescanLibrary()
        XCTAssertEqual(model.songs.map(\.title), ["scale"])
    }
}
