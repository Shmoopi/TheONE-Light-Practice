import Foundation

/// How to talk to THE ONE Light keyboard.
///
/// These are the exact messages that turn the keyboard's lights on and off. They
/// were worked out by watching what the official app sends, then checking each one
/// against a real keyboard. `docs/PROTOCOL.md` has the details if you're curious.
///
/// Three things matter:
/// - Lights are switched with a MIDI message the keyboard would never send itself,
///   so turning a light on never makes a sound.
/// - The keyboard numbers its lights differently from musical notes. Getting this
///   wrong still lights keys, just the wrong ones, so it's easy to miss.
/// - The keyboard ignores light messages until it's been greeted. Skip the
///   greeting and nothing happens at all.
public enum TheOneProtocol {

    // MARK: - Lamp writes

    /// The keyboard listens for light messages here.
    public static let lampChannel: UInt8 = 2

    /// The first byte of every "set a light" message.
    public static let lampStatus: UInt8 = 0xA0 | lampChannel

    /// The keyboard counts its lights from the lowest key of a full-size piano,
    /// which is 21 steps below the usual numbering for musical notes.
    public static let lampIndexOffset: Int = 21

    /// A light is either off or on.
    ///
    /// The keyboard accepts three different "on" values, but on THE ONE Light they
    /// all look exactly the same — the lights are a single colour and can't be
    /// dimmed. Other models in the range may show them differently.
    public enum LampState: UInt8, CaseIterable, Sendable {
        case off = 0x00
        case primary = 0x01
        case secondary = 0x02
        case tertiary = 0x03
    }

    /// Which light matches a musical note, or nothing if the note is off the end
    /// of the keyboard. Better to light nothing than to light the wrong key.
    public static func lampIndex(forNote note: Int) -> UInt8? {
        let index = note - lampIndexOffset
        guard (0...127).contains(index) else { return nil }
        return UInt8(index)
    }

    /// Which musical note a light belongs to.
    public static func note(forLampIndex index: UInt8) -> Int {
        Int(index) + lampIndexOffset
    }

    /// The message that turns one key's light on or off.
    public static func lamp(note: Int, state: LampState) -> [UInt8]? {
        guard let index = lampIndex(forNote: note) else { return nil }
        return [lampStatus, index, state.rawValue]
    }

    // MARK: - Vendor SysEx envelope

    /// Identifies these as messages for this make of keyboard.
    public static let manufacturerID: [UInt8] = [0x00, 0x20, 0x2B]

    /// Identifies this model of keyboard.
    public static let modelByte: UInt8 = 0x69

    private static func frame(_ command: UInt8, _ args: UInt8...) -> [UInt8] {
        [0xF0] + manufacturerID + [modelByte, command] + args + [0xF7]
    }

    /// The greeting. Send this once when you connect — the keyboard ignores every
    /// light message until it arrives.
    ///
    /// We don't know what each line means individually. They're copied exactly from
    /// what the official app sends, and together they work.
    public static let handshake: [[UInt8]] = [
        frame(0x00, 0x00, 0x55, 0x79),   // open / hello
        frame(0x41, 0x01, 0x00),
        frame(0x01, 0x00, 0x00),
        frame(0x09, 0x01, 0x6E),
        frame(0x06, 0x00, 0x02, 0x00),   // per-slot configuration
        frame(0x06, 0x00, 0x00, 0x01),
        frame(0x06, 0x00, 0x01, 0x00),
        frame(0x06, 0x01, 0x02, 0x79, 0x00, 0x00),
        frame(0x06, 0x01, 0x00, 0x79, 0x00, 0x00),
        frame(0x06, 0x01, 0x01, 0x79, 0x00, 0x00),
    ]

    /// A short pause between each line of the greeting. Sending them all at once
    /// is too fast for the keyboard to keep up.
    public static let handshakeGap: Duration = .milliseconds(15)

    /// Turn the lights off in one go.
    public static var clearLamps: [UInt8] { frame(0x16, lampChannel, 0x00) }

    /// Turn off every light, one by one, to be certain none are left on.
    public static var allLampsOff: [[UInt8]] {
        [clearLamps] + (0...127).map { [lampStatus, UInt8($0), LampState.off.rawValue] }
    }

    // MARK: - Keyboard facts

    /// THE ONE Light has 61 keys, running from C2 up to C7.
    public static let keyRange: ClosedRange<Int> = 36...96

    /// Where the keyboard tells us which keys you've pressed.
    public static let keyPressChannel: UInt8 = 0
}
