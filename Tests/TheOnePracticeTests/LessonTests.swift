import XCTest
@testable import TheOnePractice

/// Builds Standard MIDI Files in memory, so the parser is tested against real
/// bytes rather than a mock.
enum MIDIBuilder {
    static func varLength(_ value: Int) -> [UInt8] {
        var bytes = [UInt8(value & 0x7F)]
        var remaining = value >> 7
        while remaining > 0 {
            bytes.insert(UInt8((remaining & 0x7F) | 0x80), at: 0)
            remaining >>= 7
        }
        return bytes
    }

    static func track(_ events: [[UInt8]]) -> [UInt8] {
        var body: [UInt8] = Array(events.joined())
        body += [0x00, 0xFF, 0x2F, 0x00]          // end of track
        let length = UInt32(body.count)
        var chunk: [UInt8] = Array("MTrk".utf8)
        chunk.append(UInt8((length >> 24) & 0xFF))
        chunk.append(UInt8((length >> 16) & 0xFF))
        chunk.append(UInt8((length >> 8) & 0xFF))
        chunk.append(UInt8(length & 0xFF))
        chunk += body
        return chunk
    }

    static func trackName(_ name: String) -> [UInt8] {
        let bytes: [UInt8] = Array(name.utf8)
        var event: [UInt8] = [0x00, 0xFF, 0x03]
        event += varLength(bytes.count)
        event += bytes
        return event
    }

    static func tempo(bpm: Int) -> [UInt8] {
        let us = 60_000_000 / bpm
        return [0x00, 0xFF, 0x51, 0x03,
                UInt8((us >> 16) & 0xFF), UInt8((us >> 8) & 0xFF), UInt8(us & 0xFF)]
    }

    static func noteOn(_ note: UInt8, _ velocity: UInt8, delta: Int = 0, channel: UInt8 = 0) -> [UInt8] {
        var event: [UInt8] = varLength(delta)
        event += [0x90 | channel, note, velocity]
        return event
    }

    static func noteOff(_ note: UInt8, delta: Int, channel: UInt8 = 0) -> [UInt8] {
        var event: [UInt8] = varLength(delta)
        event += [0x80 | channel, note, 0]
        return event
    }

    static func file(ticksPerBeat: Int = 480, tracks: [[UInt8]]) -> Data {
        let format: UInt16 = tracks.count > 1 ? 1 : 0
        let count = UInt16(tracks.count)
        let tpb = UInt16(ticksPerBeat)
        var bytes: [UInt8] = Array("MThd".utf8)
        bytes += [0, 0, 0, 6]
        bytes.append(UInt8(format >> 8)); bytes.append(UInt8(format & 0xFF))
        bytes.append(UInt8(count >> 8)); bytes.append(UInt8(count & 0xFF))
        bytes.append(UInt8(tpb >> 8)); bytes.append(UInt8(tpb & 0xFF))
        bytes += Array(tracks.joined())
        return Data(bytes)
    }

    /// A two-hand file with named tracks — the authoritative hand signal.
    static func twoHandFile() -> Data {
        let right = track([
            trackName("Right Hand"),
            tempo(bpm: 120),
            noteOn(60, 90), noteOff(60, delta: 480),
            noteOn(62, 90), noteOff(62, delta: 480),
        ])
        let left = track([
            trackName("Left Hand"),
            noteOn(48, 70), noteOff(48, delta: 960),
        ])
        return file(tracks: [right, left])
    }

    /// A one-note-at-a-time run up the keyboard, for tests that need somewhere to
    /// seek to.
    static func scaleFile(from first: UInt8 = 60, count: Int = 8) -> Data {
        var events: [[UInt8]] = [trackName("Right Hand"), tempo(bpm: 120)]
        for step in 0..<count {
            let note = first + UInt8(step)
            events.append(noteOn(note, 90))
            events.append(noteOff(note, delta: 240))
        }
        return file(tracks: [track(events)])
    }
}

final class MIDIFileTests: XCTestCase {

    func testParsesNotesWithAbsoluteSeconds() throws {
        let file = try MIDIFile(data: MIDIBuilder.twoHandFile())
        XCTAssertEqual(file.notes.count, 3)
        XCTAssertEqual(file.ticksPerBeat, 480)

        let c4 = try XCTUnwrap(file.notes.first { $0.note == 60 })
        XCTAssertEqual(c4.start, 0, accuracy: 0.001)
        // One beat at 120 bpm is half a second.
        XCTAssertEqual(c4.duration, 0.5, accuracy: 0.01)
    }

    func testKeepsTrackNames() throws {
        let file = try MIDIFile(data: MIDIBuilder.twoHandFile())
        XCTAssertTrue(file.trackNames.contains("Right Hand"))
        XCTAssertTrue(file.trackNames.contains("Left Hand"))
        let bass = try XCTUnwrap(file.notes.first { $0.note == 48 })
        XCTAssertEqual(bass.trackName, "Left Hand")
    }

    func testHonoursTempoChanges() throws {
        // 60 bpm makes a beat one second, so the same tick count lasts twice as long.
        let data = MIDIBuilder.file(tracks: [MIDIBuilder.track([
            MIDIBuilder.tempo(bpm: 60),
            MIDIBuilder.noteOn(60, 90), MIDIBuilder.noteOff(60, delta: 480),
        ])])
        let file = try MIDIFile(data: data)
        XCTAssertEqual(file.notes[0].duration, 1.0, accuracy: 0.01)
    }

    func testHandlesRunningStatus() throws {
        // Status omitted on repeats — ubiquitous in real files.
        var events: [UInt8] = MIDIBuilder.trackName("RS")
        events += MIDIBuilder.noteOn(60, 90)
        events += MIDIBuilder.varLength(480); events += [62, 90]  // running status note-on
        events += MIDIBuilder.varLength(0);   events += [60, 0]   // running status release
        events += MIDIBuilder.varLength(0);   events += [62, 0]
        let data = MIDIBuilder.file(tracks: [MIDIBuilder.track([events])])

        let file = try MIDIFile(data: data)
        XCTAssertEqual(Set(file.notes.map(\.note)), [60, 62])
    }

    func testNoteOnWithVelocityZeroIsARelease() throws {
        var events: [UInt8] = MIDIBuilder.noteOn(60, 90)
        events += MIDIBuilder.noteOn(60, 0, delta: 480)   // release, per MIDI 1.0
        let data = MIDIBuilder.file(tracks: [MIDIBuilder.track([events])])

        let file = try MIDIFile(data: data)
        XCTAssertEqual(file.notes.count, 1)
        XCTAssertEqual(file.notes[0].duration, 0.5, accuracy: 0.01)
    }

    func testUnreleasedNotesStillAppear() throws {
        // A malformed file should still teach something rather than losing the note.
        let data = MIDIBuilder.file(tracks: [MIDIBuilder.track([MIDIBuilder.noteOn(60, 90)])])
        let file = try MIDIFile(data: data)
        XCTAssertEqual(file.notes.count, 1)
        XCTAssertGreaterThan(file.notes[0].duration, 0)
    }

    func testRejectsNonMIDIData() {
        XCTAssertThrowsError(try MIDIFile(data: Data("not a midi file".utf8))) { error in
            XCTAssertEqual(error as? MIDIFile.ParseError, .notAMIDIFile)
        }
    }

    func testNotesAreSortedByTime() throws {
        let file = try MIDIFile(data: MIDIBuilder.twoHandFile())
        XCTAssertEqual(file.notes.map(\.start), file.notes.map(\.start).sorted())
    }
}

final class LessonCompileTests: XCTestCase {

    private func twoHandLesson(hand: Lesson.HandFilter = .both) throws -> Lesson {
        let file = try MIDIFile(data: MIDIBuilder.twoHandFile())
        return Lesson.compile(from: file, name: "t", hand: hand)
    }

    func testSimultaneousNotesBecomeOneChordStep() throws {
        let lesson = try twoHandLesson()
        XCTAssertEqual(lesson.steps.first?.keys, [48, 60])
        XCTAssertTrue(lesson.steps[0].isChord)
    }

    func testTrackNamesDriveHandAssignment() throws {
        let lesson = try twoHandLesson()
        XCTAssertEqual(lesson.handSignal, .trackName)
        XCTAssertTrue(lesson.handSignal.isReliable)
        XCTAssertEqual(lesson.steps[0].hands[48], .left)
        XCTAssertEqual(lesson.steps[0].hands[60], .right)
    }

    func testHandFilteringKeepsOneHand() throws {
        XCTAssertEqual(try twoHandLesson(hand: .right).keysUsed, [60, 62])
        XCTAssertEqual(try twoHandLesson(hand: .left).keysUsed, [48])
    }

    func testNotesOutsideTheKeyboardAreDroppedAndReported() {
        let data = MIDIBuilder.file(tracks: [MIDIBuilder.track([
            MIDIBuilder.noteOn(12, 90), MIDIBuilder.noteOff(12, delta: 480),
        ])])
        let file = try! MIDIFile(data: data)
        let lesson = Lesson.compile(from: file, name: "t")
        XCTAssertTrue(lesson.keysUsed.isEmpty)
        XCTAssertEqual(lesson.droppedNotes, [12])
    }

    func testTransposeBringsOutOfRangeNotesIn() {
        let data = MIDIBuilder.file(tracks: [MIDIBuilder.track([
            MIDIBuilder.noteOn(12, 90), MIDIBuilder.noteOff(12, delta: 480),
        ])])
        let file = try! MIDIFile(data: data)
        let lesson = Lesson.compile(from: file, name: "t", transposeIntoRange: true)
        XCTAssertTrue(lesson.droppedNotes.isEmpty)
        XCTAssertTrue(lesson.keysUsed.allSatisfy(TheOneProtocol.keyRange.contains))
    }

    func testPitchFallbackIsFlaggedAsUnreliable() {
        // One unnamed track, one channel: nothing trustworthy to go on.
        let data = MIDIBuilder.file(tracks: [MIDIBuilder.track([
            MIDIBuilder.noteOn(48, 90), MIDIBuilder.noteOff(48, delta: 240),
            MIDIBuilder.noteOn(72, 90), MIDIBuilder.noteOff(72, delta: 240),
        ])])
        let lesson = Lesson.compile(from: try! MIDIFile(data: data), name: "t")
        XCTAssertEqual(lesson.handSignal, .pitch)
        XCTAssertFalse(lesson.handSignal.isReliable)
    }
}

final class LessonSessionTests: XCTestCase {

    private func lesson(_ groups: [[Int]]) -> Lesson {
        Lesson(
            name: "t",
            steps: groups.enumerated().map { index, keys in
                LessonStep(id: index, keys: keys.sorted(), hands: [:], time: 0)
            },
            handSignal: .trackName
        )
    }

    func testCorrectKeyAdvances() {
        var session = LessonSession(lesson: lesson([[60], [62]]))
        let result = session.keyDown(60)
        XCTAssertTrue(result.correct)
        XCTAssertTrue(result.stepComplete)
        XCTAssertEqual(session.current?.keys, [62])
    }

    func testWrongKeyIsCountedButNeverBlocks() {
        var session = LessonSession(lesson: lesson([[60]]))
        let result = session.keyDown(65)
        XCTAssertFalse(result.correct)
        XCTAssertEqual(session.mistakes, 1)
        XCTAssertEqual(session.wrongKeys[65], 1)
        // Still on the same step, and still accepting the right key.
        XCTAssertTrue(session.keyDown(60).stepComplete)
    }

    func testAHeldKeyDoesNotCompleteTheNextStep() {
        // The load-bearing rule. Without it, a step needing a key you are still
        // holding completes itself the instant it appears.
        var session = LessonSession(lesson: lesson([[60], [60]]))
        _ = session.keyDown(60)
        XCTAssertEqual(session.stepsCompleted, 1)
        XCTAssertEqual(session.current?.keys, [60], "step 1 must not have auto-completed")
    }

    func testARunOfRepeatedNotesCannotRaceToTheEnd() {
        var session = LessonSession(lesson: lesson([[60], [60], [60], [60]]))
        _ = session.keyDown(60)
        XCTAssertEqual(session.stepsCompleted, 1, "one press completes exactly one step")
        XCTAssertFalse(session.isFinished)
    }

    func testRepeatedNoteAdvancesAfterReleaseAndRePress() {
        var session = LessonSession(lesson: lesson([[60], [60]]))
        _ = session.keyDown(60)
        session.keyUp(60)
        XCTAssertTrue(session.keyDown(60).finished)
    }

    func testChordNeedsAllItsKeysInAnyOrder() {
        var session = LessonSession(lesson: lesson([[60, 64, 67]]))
        XCTAssertFalse(session.keyDown(67).stepComplete)
        XCTAssertFalse(session.keyDown(60).stepComplete)
        XCTAssertTrue(session.keyDown(64).stepComplete)
    }

    func testRemainingReportsOutstandingKeys() {
        var session = LessonSession(lesson: lesson([[60, 64, 67]]))
        _ = session.keyDown(64)
        XCTAssertEqual(session.remaining, [60, 67])
    }

    func testLenientModeAllowsReleasingBetweenChordNotes() {
        var session = LessonSession(lesson: lesson([[60, 64]]))
        _ = session.keyDown(60)
        session.keyUp(60)
        XCTAssertTrue(session.keyDown(64).stepComplete)
    }

    func testStrictModeRequiresThemHeldTogether() {
        var session = LessonSession(lesson: lesson([[60, 64]]), requireSimultaneous: true)
        _ = session.keyDown(60)
        session.keyUp(60)
        XCTAssertFalse(session.keyDown(64).stepComplete)
        XCTAssertTrue(session.keyDown(60).stepComplete)
    }

    func testProgressAndAccuracy() {
        var session = LessonSession(lesson: lesson([[60], [62]]))
        XCTAssertEqual(session.progress, 0)
        XCTAssertEqual(session.accuracy, 1)
        _ = session.keyDown(99)
        _ = session.keyDown(60)
        XCTAssertEqual(session.progress, 0.5, accuracy: 0.001)
        XCTAssertEqual(session.accuracy, 0.5, accuracy: 0.001)
    }

    func testRestartClearsEverything() {
        var session = LessonSession(lesson: lesson([[60], [62]]))
        _ = session.keyDown(99)
        _ = session.keyDown(60)
        session.restart()
        XCTAssertEqual(session.stepsCompleted, 0)
        XCTAssertEqual(session.mistakes, 0)
        XCTAssertEqual(session.current?.keys, [60])
    }

    func testPressesAfterTheEndAreHarmless() {
        var session = LessonSession(lesson: lesson([[60]]))
        _ = session.keyDown(60)
        XCTAssertTrue(session.isFinished)
        XCTAssertFalse(session.keyDown(72).correct)
    }

    func testEmptyLessonIsImmediatelyFinished() {
        XCTAssertTrue(LessonSession(lesson: lesson([])).isFinished)
    }
}

/// Seeking makes "position" and "achievement" two different things, and conflating
/// them would make scrubbing to the end look like a flawless performance.
final class SeekingTests: XCTestCase {

    private func lesson(_ count: Int) -> Lesson {
        Lesson(
            name: "t",
            steps: (0..<count).map { i in
                LessonStep(id: i, keys: [60 + i], hands: [:], time: Double(i) * 0.5)
            },
            handSignal: .trackName
        )
    }

    func testProgressTracksPositionNotStepsCompleted() {
        var session = LessonSession(lesson: lesson(4))
        session.seek(to: 2)
        XCTAssertEqual(session.progress, 0.5, accuracy: 0.001)
        XCTAssertEqual(session.stepsCompleted, 0, "seeking earns no steps")
    }

    func testSeekingDoesNotInflateAccuracy() {
        var session = LessonSession(lesson: lesson(10))
        _ = session.keyDown(99)          // one mistake
        session.seek(to: 9)              // scrub to the end
        XCTAssertEqual(session.stepsCompleted, 0)
        XCTAssertEqual(session.mistakes, 1)
        XCTAssertEqual(session.accuracy, 0, accuracy: 0.001)
    }

    func testSeekingMovesWhatMustBePlayedNext() {
        var session = LessonSession(lesson: lesson(4))
        session.seek(to: 2)
        XCTAssertEqual(session.current?.keys, [62])
        XCTAssertTrue(session.keyDown(62).stepComplete)
    }

    func testSeekingClearsCreditFromTheOldStep() {
        // Otherwise a key already pressed would complete the step you jumped to.
        var session = LessonSession(lesson: lesson(4))
        _ = session.keyDown(60)          // completes step 0, credits 60
        session.seek(to: 0)
        XCTAssertEqual(session.current?.keys, [60])
        XCTAssertEqual(session.remaining, [60], "the jumped-to step must be unearned")
    }

    func testSeekingIsClampedToTheLesson() {
        var session = LessonSession(lesson: lesson(3))
        session.seek(to: -5)
        XCTAssertEqual(session.index, 0)
        session.seek(to: 99)
        XCTAssertEqual(session.index, 3)
        XCTAssertTrue(session.isFinished)
    }

    func testPositionLabelIsOneBasedAndClamped() {
        var session = LessonSession(lesson: lesson(4))
        XCTAssertEqual(session.positionLabel, "1/4")
        session.seek(to: 3)
        XCTAssertEqual(session.positionLabel, "4/4")
        _ = session.keyDown(63)
        XCTAssertEqual(session.positionLabel, "4/4", "must not read 5/4 once finished")
    }

    func testTimeReadoutsFollowTheSourceSong() {
        var session = LessonSession(lesson: lesson(5))
        XCTAssertEqual(session.currentTime, 0, accuracy: 0.001)
        XCTAssertEqual(session.totalTime, 2.0, accuracy: 0.001)
        session.seek(to: 2)
        XCTAssertEqual(session.currentTime, 1.0, accuracy: 0.001)
    }

    func testFinishedSessionReportsFullProgress() {
        var session = LessonSession(lesson: lesson(2))
        _ = session.keyDown(60)
        _ = session.keyDown(61)
        XCTAssertEqual(session.progress, 1.0, accuracy: 0.001)
    }

    func testEmptyLessonHasNoDivisionByZero() {
        let session = LessonSession(lesson: lesson(0))
        XCTAssertEqual(session.progress, 1)
        XCTAssertEqual(session.totalTime, 0)
    }
}

/// Playback is a different view of the song from practice, and the bug these
/// cover is the one that made repeated notes sound as a single held note.
final class PlaybackTimelineTests: XCTestCase {

    /// Two E4s in a row, butt-joined — the shape that broke.
    private func repeatedNoteFile() -> Data {
        MIDIBuilder.file(tracks: [MIDIBuilder.track([
            MIDIBuilder.noteOn(64, 90), MIDIBuilder.noteOff(64, delta: 480),
            MIDIBuilder.noteOn(64, 90), MIDIBuilder.noteOff(64, delta: 480),
        ])])
    }

    private func lesson(_ data: Data) throws -> Lesson {
        Lesson.compile(from: try MIDIFile(data: data), name: "t")
    }

    func testARepeatedNoteProducesTwoSeparateSoundings() throws {
        let events = try lesson(repeatedNoteFile()).playback
        let ons = events.filter { $0.isOn && $0.note == 64 }
        let offs = events.filter { !$0.isOn && $0.note == 64 }
        XCTAssertEqual(ons.count, 2, "each occurrence must articulate")
        XCTAssertEqual(offs.count, 2)
    }

    func testThereIsAnAudibleGapBetweenRepeats() throws {
        // A note-off and note-on at the same instant is not reliably heard as two
        // notes; the synth may never release the envelope.
        let events = try lesson(repeatedNoteFile()).playback
        let firstOff = try XCTUnwrap(events.first { !$0.isOn && $0.note == 64 })
        let secondOn = try XCTUnwrap(events.filter { $0.isOn && $0.note == 64 }.dropFirst().first)
        XCTAssertGreaterThanOrEqual(
            secondOn.time - firstOff.time, Lesson.minRetriggerGap - 0.0001
        )
    }

    func testOffsPrecedeOnsAtTheSameInstant() throws {
        // Otherwise a release cancels the note that just started.
        let events = try lesson(repeatedNoteFile()).playback
        for (a, b) in zip(events, events.dropFirst()) where a.time == b.time {
            XCTAssertFalse(a.isOn && !b.isOn, "an on must not precede an off at the same time")
        }
    }

    func testEventsAreOrderedByTime() throws {
        let events = try lesson(MIDIBuilder.twoHandFile()).playback
        XCTAssertEqual(events.map(\.time), events.map(\.time).sorted())
    }

    func testASustainedNoteIsNotCutShortByALaterOnset() throws {
        // The other half of the diffing bug: a bass note held under a moving
        // melody was switched off as soon as the melody moved.
        let lesson = try lesson(MIDIBuilder.twoHandFile())
        let bassOff = try XCTUnwrap(lesson.playback.first { !$0.isOn && $0.note == 48 })
        let melodyOn = try XCTUnwrap(
            lesson.playback.filter { $0.isOn && $0.note == 62 }.first
        )
        XCTAssertGreaterThan(
            bassOff.time, melodyOn.time,
            "the held bass must outlast the melody note that starts under it"
        )
    }

    func testEveryNoteOnHasAMatchingOff() throws {
        // A missing off leaves the instrument sounding after playback ends.
        let events = try lesson(MIDIBuilder.twoHandFile()).playback
        var open: [Int: Int] = [:]
        for event in events {
            open[event.note, default: 0] += event.isOn ? 1 : -1
            XCTAssertGreaterThanOrEqual(open[event.note]!, 0, "off before on for \(event.note)")
        }
        XCTAssertTrue(open.values.allSatisfy { $0 == 0 }, "every note must be released")
    }

    func testVelocityIsCarriedThrough() throws {
        let events = try lesson(MIDIBuilder.twoHandFile()).playback
        let bass = try XCTUnwrap(events.first { $0.isOn && $0.note == 48 })
        XCTAssertEqual(bass.velocity, 70)
    }

    func testPlaybackRespectsTheHandFilter() throws {
        let file = try MIDIFile(data: MIDIBuilder.twoHandFile())
        let right = Lesson.compile(from: file, name: "t", hand: .right)
        XCTAssertFalse(right.playback.contains { $0.note == 48 })
        XCTAssertTrue(right.playback.contains { $0.note == 60 })
    }

    func testATrimmedNoteStillArticulates() throws {
        // Overlapping repeats of one pitch must not be trimmed out of existence.
        var events: [UInt8] = MIDIBuilder.noteOn(64, 90)
        events += MIDIBuilder.noteOn(64, 90, delta: 5)      // retrigger almost immediately
        events += MIDIBuilder.noteOff(64, delta: 480)
        let data = MIDIBuilder.file(tracks: [MIDIBuilder.track([events])])
        let lesson = Lesson.compile(from: try MIDIFile(data: data), name: "t")
        for event in lesson.playback where event.isOn {
            let off = lesson.playback.first {
                !$0.isOn && $0.note == event.note && $0.time > event.time
            }
            XCTAssertNotNil(off)
            XCTAssertGreaterThan(off!.time, event.time, "a note must have positive length")
        }
    }
}

/// Against the real sample file, which is what exposed the bug in use.
final class OdeToJoyPlaybackTests: XCTestCase {

    private var sampleURL: URL? {
        // Tests run from the package directory; the samples live at the repo root.
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // TheOnePracticeTests/
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Samples/ode-to-joy.mid")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func testTheOpeningRepeatedEsArticulateSeparately() throws {
        guard let sampleURL else { throw XCTSkip("Samples/ode-to-joy.mid not present") }
        let lesson = Lesson.compile(from: try MIDIFile(url: sampleURL), name: "ode", hand: .right)

        // The melody opens E E F G — the two Es must be two soundings.
        let eOns = lesson.playback.filter { $0.isOn && $0.note == 64 }
        XCTAssertGreaterThanOrEqual(eOns.count, 4, "E4 recurs throughout the melody")

        let firstTwo = Array(eOns.prefix(2))
        XCTAssertEqual(firstTwo.count, 2)
        let offBetween = lesson.playback.first {
            !$0.isOn && $0.note == 64 && $0.time > firstTwo[0].time && $0.time <= firstTwo[1].time
        }
        XCTAssertNotNil(offBetween, "there must be a release between the two Es")
        XCTAssertGreaterThanOrEqual(
            firstTwo[1].time - offBetween!.time, Lesson.minRetriggerGap - 0.0001
        )
    }

    func testEveryRepeatedPairInTheMelodyArticulates() throws {
        guard let sampleURL else { throw XCTSkip("Samples/ode-to-joy.mid not present") }
        let lesson = Lesson.compile(from: try MIDIFile(url: sampleURL), name: "ode", hand: .right)

        // Walk the timeline and check no pitch is ever asked to start while already on.
        var sounding: Set<Int> = []
        for event in lesson.playback {
            if event.isOn {
                XCTAssertFalse(
                    sounding.contains(event.note),
                    "note \(event.note) started at \(event.time) while already sounding"
                )
                sounding.insert(event.note)
            } else {
                sounding.remove(event.note)
            }
        }
        XCTAssertTrue(sounding.isEmpty)
    }
}

/// Every bundled sample must actually be playable, on both paths. A song that
/// compiles but produces no lamp writes looks like a hardware fault.
final class SampleSongTests: XCTestCase {

    private var samplesDirectory: URL? {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // TheOnePracticeTests/
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Samples")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func sampleURLs() throws -> [URL] {
        guard let samplesDirectory else { throw XCTSkip("Samples/ not present") }
        let files = try FileManager.default.contentsOfDirectory(
            at: samplesDirectory, includingPropertiesForKeys: nil
        )
        let midi = files.filter { ["mid", "midi"].contains($0.pathExtension.lowercased()) }
        guard !midi.isEmpty else { throw XCTSkip("no MIDI samples") }
        return midi.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func testEverySampleProducesStepsAndPlayback() throws {
        for url in try sampleURLs() {
            let name = url.lastPathComponent
            let file = try MIDIFile(url: url)
            XCTAssertFalse(file.notes.isEmpty, "\(name): parsed no notes")

            let lesson = Lesson.compile(from: file, name: name)
            XCTAssertFalse(lesson.steps.isEmpty, "\(name): no practice steps")
            XCTAssertFalse(lesson.playback.isEmpty, "\(name): no playback events")
        }
    }

    func testEverySampleNoteIsAddressableOnTheHardware() throws {
        for url in try sampleURLs() {
            let name = url.lastPathComponent
            let lesson = Lesson.compile(from: try MIDIFile(url: url), name: name)
            for event in lesson.playback {
                XCTAssertNotNil(
                    TheOneProtocol.lampIndex(forNote: event.note),
                    "\(name): note \(event.note) (\(NoteName.of(event.note))) has no lamp index"
                )
            }
            XCTAssertTrue(
                lesson.droppedNotes.isEmpty,
                "\(name): dropped \(lesson.droppedNotes) as out of range"
            )
        }
    }

    func testEverySampleWorksWithEachHandFilter() throws {
        for url in try sampleURLs() {
            let file = try MIDIFile(url: url)
            let name = url.lastPathComponent
            for hand in Lesson.HandFilter.allCases {
                let lesson = Lesson.compile(from: file, name: name, hand: hand)
                XCTAssertFalse(
                    lesson.playback.isEmpty,
                    "\(name) with \(hand.rawValue): no playback events"
                )
            }
        }
    }

    func testEverySamplePlaybackStartsAtOrNearZero() throws {
        // runListenMode filters events at or after the starting step's time. If the
        // first playback event sat before the first step, nothing would play.
        for url in try sampleURLs() {
            let name = url.lastPathComponent
            let lesson = Lesson.compile(from: try MIDIFile(url: url), name: name)
            let firstStep = try XCTUnwrap(lesson.steps.first).time
            let firstEvent = try XCTUnwrap(lesson.playback.first).time
            XCTAssertGreaterThanOrEqual(
                firstEvent, firstStep - 0.0001,
                "\(name): playback begins before the first step, so it would be filtered out"
            )
        }
    }
}

/// What stays lit during a chord. The strict case had the whole chord going dark
/// as it was played, leaving no way to see which notes were still wanted.
final class ChordLightingTests: XCTestCase {

    private func chordLesson() -> Lesson {
        Lesson(
            name: "t",
            steps: [
                LessonStep(id: 0, keys: [60, 64, 67], hands: [:], time: 0),
                LessonStep(id: 1, keys: [62], hands: [:], time: 1),
            ],
            handSignal: .trackName
        )
    }

    func testLenientChordsExtinguishWhatHasBeenPlayed() {
        // The keys still lit are exactly the ones outstanding.
        var session = LessonSession(lesson: chordLesson())
        XCTAssertEqual(session.keysToLight, [60, 64, 67])
        _ = session.keyDown(60)
        XCTAssertEqual(session.keysToLight, [64, 67])
        _ = session.keyDown(64)
        XCTAssertEqual(session.keysToLight, [67])
    }

    func testStrictChordsKeepTheWholeChordLit() {
        // The bug: pressing a note darkened it, so a partly-played chord gave no
        // indication of what it had been.
        var session = LessonSession(lesson: chordLesson(), requireSimultaneous: true)
        XCTAssertEqual(session.keysToLight, [60, 64, 67])
        _ = session.keyDown(60)
        XCTAssertEqual(session.keysToLight, [60, 64, 67], "the full chord must stay visible")
        _ = session.keyDown(64)
        XCTAssertEqual(session.keysToLight, [60, 64, 67])
    }

    func testStrictChordLightingSurvivesARelease() {
        // Releasing revokes credit under strict chords, so the target is unchanged
        // and must still be fully shown.
        var session = LessonSession(lesson: chordLesson(), requireSimultaneous: true)
        _ = session.keyDown(60)
        session.keyUp(60)
        XCTAssertEqual(session.keysToLight, [60, 64, 67])
        XCTAssertFalse(session.keyDown(64).stepComplete, "60 is no longer held")
    }

    func testCompletingAChordMovesTheLightToTheNextStep() {
        for strict in [false, true] {
            var session = LessonSession(lesson: chordLesson(), requireSimultaneous: strict)
            _ = session.keyDown(60)
            _ = session.keyDown(64)
            let result = session.keyDown(67)
            XCTAssertTrue(result.stepComplete, "strict=\(strict)")
            XCTAssertEqual(session.keysToLight, [62], "strict=\(strict)")
        }
    }

    func testSingleNoteStepsAreUnaffectedByTheChordRule() {
        for strict in [false, true] {
            var session = LessonSession(
                lesson: Lesson(
                    name: "t",
                    steps: [LessonStep(id: 0, keys: [60], hands: [:], time: 0)],
                    handSignal: .trackName
                ),
                requireSimultaneous: strict
            )
            XCTAssertEqual(session.keysToLight, [60])
            _ = session.keyDown(60)
            XCTAssertEqual(session.keysToLight, [], "finished lessons light nothing")
        }
    }

    func testAFinishedLessonLightsNothing() {
        var session = LessonSession(lesson: chordLesson())
        _ = session.keyDown(60); _ = session.keyDown(64); _ = session.keyDown(67)
        _ = session.keyDown(62)
        XCTAssertTrue(session.isFinished)
        XCTAssertEqual(session.keysToLight, [])
    }

    func testSeekingRelightsTheWholeTargetStep() {
        var session = LessonSession(lesson: chordLesson())
        _ = session.keyDown(60)
        session.seek(to: 0)
        XCTAssertEqual(session.keysToLight, [60, 64, 67], "a jumped-to step is unearned")
    }
}
