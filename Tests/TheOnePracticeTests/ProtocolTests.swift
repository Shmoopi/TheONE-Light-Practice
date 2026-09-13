import XCTest
@testable import TheOnePractice

/// The protocol bytes are measured. A regression here breaks real
/// hardware silently, so every value is pinned.
final class ProtocolTests: XCTestCase {

    func testLampWriteIsPolyAftertouchOnChannel2() {
        XCTAssertEqual(TheOneProtocol.lampStatus, 0xA2)
        XCTAssertEqual(TheOneProtocol.lamp(note: 60, state: .primary), [0xA2, 39, 0x01])
    }

    func testLampIndexIsMidiNoteMinus21() {
        // Lamp 0 is A0 — standard 0-based 88-key position. Getting this wrong
        // fails quietly: every key lights and the song is merely transposed.
        XCTAssertEqual(TheOneProtocol.lampIndexOffset, 21)
        XCTAssertEqual(TheOneProtocol.lampIndex(forNote: 21), 0)
        XCTAssertEqual(TheOneProtocol.lampIndex(forNote: 60), 39)
        XCTAssertEqual(TheOneProtocol.note(forLampIndex: 0), 21)
        XCTAssertEqual(TheOneProtocol.note(forLampIndex: 39), 60)
    }

    func testUnaddressableNotesReturnNilRatherThanClamping() {
        // A clamped index lights the wrong key, which is worse than lighting none.
        XCTAssertNil(TheOneProtocol.lampIndex(forNote: 10))
        XCTAssertNil(TheOneProtocol.lamp(note: 10, state: .primary))
    }

    func testLampStatesAreTheMeasuredSet() {
        // Values 1, 2 and 3 all light a key; 4+ do nothing. On the Light all three
        // look identical — single-colour LEDs, no brightness.
        XCTAssertEqual(TheOneProtocol.LampState.off.rawValue, 0x00)
        XCTAssertEqual(TheOneProtocol.LampState.primary.rawValue, 0x01)
        XCTAssertEqual(TheOneProtocol.LampState.secondary.rawValue, 0x02)
        XCTAssertEqual(TheOneProtocol.LampState.tertiary.rawValue, 0x03)
        XCTAssertEqual(TheOneProtocol.LampState.allCases.count, 4)
    }

    func testHandshakeIsExactlyTheCapturedSequence() {
        // Byte-for-byte from a cold-start capture. The first four frames are the
        // ones that matter: they appear only when the app is captured from launch,
        // and two replay attempts failed before they were found.
        let expected: [[UInt8]] = [
            [0xF0, 0x00, 0x20, 0x2B, 0x69, 0x00, 0x00, 0x55, 0x79, 0xF7],
            [0xF0, 0x00, 0x20, 0x2B, 0x69, 0x41, 0x01, 0x00, 0xF7],
            [0xF0, 0x00, 0x20, 0x2B, 0x69, 0x01, 0x00, 0x00, 0xF7],
            [0xF0, 0x00, 0x20, 0x2B, 0x69, 0x09, 0x01, 0x6E, 0xF7],
            [0xF0, 0x00, 0x20, 0x2B, 0x69, 0x06, 0x00, 0x02, 0x00, 0xF7],
            [0xF0, 0x00, 0x20, 0x2B, 0x69, 0x06, 0x00, 0x00, 0x01, 0xF7],
            [0xF0, 0x00, 0x20, 0x2B, 0x69, 0x06, 0x00, 0x01, 0x00, 0xF7],
            [0xF0, 0x00, 0x20, 0x2B, 0x69, 0x06, 0x01, 0x02, 0x79, 0x00, 0x00, 0xF7],
            [0xF0, 0x00, 0x20, 0x2B, 0x69, 0x06, 0x01, 0x00, 0x79, 0x00, 0x00, 0xF7],
            [0xF0, 0x00, 0x20, 0x2B, 0x69, 0x06, 0x01, 0x01, 0x79, 0x00, 0x00, 0xF7],
        ]
        XCTAssertEqual(TheOneProtocol.handshake, expected)
    }

    func testEveryVendorFrameIsWellFormedSysEx() {
        for frame in TheOneProtocol.handshake + [TheOneProtocol.clearLamps] {
            XCTAssertEqual(frame.first, 0xF0)
            XCTAssertEqual(frame.last, 0xF7)
            XCTAssertEqual(Array(frame[1...3]), TheOneProtocol.manufacturerID)
            XCTAssertEqual(frame[4], TheOneProtocol.modelByte)
            // SysEx payload bytes must be 7-bit.
            XCTAssertTrue(frame.dropFirst().dropLast().allSatisfy { $0 < 0x80 })
        }
    }

    func testHandshakeIsPaced() {
        // Firmware that drops a burst fails the handshake silently.
        XCTAssertGreaterThan(TheOneProtocol.handshakeGap, .zero)
    }

    func testAllLampsOffSweepsEveryIndexNotAMidiRange() {
        // Blanks the whole device regardless of the offset.
        let frames = TheOneProtocol.allLampsOff
        XCTAssertEqual(frames.first, TheOneProtocol.clearLamps)
        let lampFrames = frames.filter { $0.first == TheOneProtocol.lampStatus }
        XCTAssertEqual(lampFrames.count, 128)
        XCTAssertEqual(Set(lampFrames.map { $0[1] }), Set(0...127))
        XCTAssertTrue(lampFrames.allSatisfy { $0[2] == 0 })
    }

    func testKeyRangeMatchesA61KeyBed() {
        XCTAssertEqual(TheOneProtocol.keyRange, 36...96)
        XCTAssertEqual(TheOneProtocol.keyRange.count, 61)
        // Every physical key must be addressable.
        for note in TheOneProtocol.keyRange {
            XCTAssertNotNil(TheOneProtocol.lampIndex(forNote: note))
        }
    }
}

final class NoteNameTests: XCTestCase {
    func testScientificPitchNames() {
        XCTAssertEqual(NoteName.of(60), "C4")
        XCTAssertEqual(NoteName.of(21), "A0")
        XCTAssertEqual(NoteName.of(72), "C5")
    }

    func testBlackKeyDetection() {
        XCTAssertFalse(NoteName.isBlackKey(60))  // C
        XCTAssertTrue(NoteName.isBlackKey(61))   // C#
        XCTAssertFalse(NoteName.isBlackKey(64))  // E
        XCTAssertTrue(NoteName.isBlackKey(66))   // F#
    }

    func testA61KeyBedHas36WhiteKeys() {
        let white = TheOneProtocol.keyRange.filter { !NoteName.isBlackKey($0) }
        XCTAssertEqual(white.count, 36)
        XCTAssertEqual(white.count + TheOneProtocol.keyRange.filter(NoteName.isBlackKey).count, 61)
    }
}
