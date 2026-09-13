import CoreMIDI
import Foundation
import Observation

/// The connection to your keyboard.
///
/// Finds it, greets it, turns its lights on and off, and listens for the keys you
/// play.
@MainActor
@Observable
public final class PianoConnection {

    /// A key press or release reported by the instrument.
    public struct KeyEvent: Sendable, Equatable {
        public let note: Int
        public let isDown: Bool
        public let velocity: Int
    }

    public enum Status: Equatable, Sendable {
        case disconnected
        case connected(String)
        case failed(String)

        public var isConnected: Bool {
            if case .connected = self { return true }
            return false
        }

        public var description: String {
            switch self {
            case .disconnected: "Not connected"
            case .connected(let name): name
            case .failed(let reason): "Error: \(reason)"
            }
        }
    }

    public private(set) var status: Status = .disconnected
    /// Everything else we found plugged in, in case the keyboard isn't there.
    public private(set) var availableDestinations: [String] = []
    /// The keys you're holding down right now.
    public private(set) var heldNotes: Set<Int> = []
    /// The keys currently lit up.
    public private(set) var litNotes: Set<Int> = []

    /// Called each time you press or release a key.
    public var onKeyEvent: ((KeyEvent) -> Void)?

    private var client = MIDIClientRef()
    private var outputPort = MIDIPortRef()
    private var inputPort = MIDIPortRef()
    private var destination = MIDIEndpointRef()
    private var source = MIDIEndpointRef()
    private var handshakeSent = false

    /// Part of the keyboard's name, used to find it among your MIDI devices.
    public var portPattern: String = "THE ONE"

    public init() {}

    // MARK: - Connection

    public func refreshDestinations() {
        var names: [String] = []
        for i in 0..<MIDIGetNumberOfDestinations() {
            let endpoint = MIDIGetDestination(i)
            names.append(Self.displayName(of: endpoint))
        }
        availableDestinations = names
    }

    public func connect() {
        disconnect()
        refreshDestinations()

        var result = MIDIClientCreateWithBlock("TheOnePractice" as CFString, &client) { _ in }
        guard result == noErr else {
            status = .failed("could not create a MIDI client (\(result))")
            return
        }

        guard let dest = findEndpoint(count: MIDIGetNumberOfDestinations(), get: MIDIGetDestination)
        else {
            let seen = availableDestinations.isEmpty
                ? "no MIDI destinations at all — is the keyboard plugged in and on?"
                : "saw: \(availableDestinations.joined(separator: ", "))"
            status = .failed("no MIDI output matching “\(portPattern)”. \(seen)")
            return
        }
        destination = dest

        result = MIDIOutputPortCreate(client, "Out" as CFString, &outputPort)
        guard result == noErr else {
            status = .failed("could not open an output port (\(result))")
            return
        }

        // Listening is optional — the lights work either way — but practice needs
        // to know what you play.
        if let src = findEndpoint(count: MIDIGetNumberOfSources(), get: MIDIGetSource) {
            source = src
            result = MIDIInputPortCreateWithBlock(client, "In" as CFString, &inputPort) {
                [weak self] packetList, _ in
                // This arrives on a background thread, so hand it over safely.
                let events = Self.parse(packetList)
                guard !events.isEmpty else { return }
                Task { @MainActor [weak self] in
                    self?.receive(events)
                }
            }
            if result == noErr {
                MIDIPortConnectSource(inputPort, source, nil)
            }
        }

        status = .connected(Self.displayName(of: destination))
        handshakeSent = false
    }

    public func disconnect() {
        if inputPort != 0, source != 0 { MIDIPortDisconnectSource(inputPort, source) }
        if inputPort != 0 { MIDIPortDispose(inputPort) }
        if outputPort != 0 { MIDIPortDispose(outputPort) }
        if client != 0 { MIDIClientDispose(client) }
        inputPort = 0
        outputPort = 0
        client = 0
        destination = 0
        source = 0
        handshakeSent = false
        heldNotes = []
        litNotes = []
        status = .disconnected
    }

    private func findEndpoint(
        count: Int, get: (Int) -> MIDIEndpointRef
    ) -> MIDIEndpointRef? {
        let needle = portPattern.lowercased()
        for i in 0..<count {
            let endpoint = get(i)
            if Self.displayName(of: endpoint).lowercased().contains(needle) {
                return endpoint
            }
        }
        return nil
    }

    private static func displayName(of endpoint: MIDIEndpointRef) -> String {
        var cf: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &cf) == noErr,
              let name = cf?.takeRetainedValue()
        else { return "(unnamed)" }
        return name as String
    }

    // MARK: - Sending

    /// Greet the keyboard. Nothing lights up until this has been sent.
    public func prepareIfNeeded() async {
        guard status.isConnected, !handshakeSent else { return }
        handshakeSent = true
        for frame in TheOneProtocol.handshake {
            send(frame)
            try? await Task.sleep(for: TheOneProtocol.handshakeGap)
        }
        try? await Task.sleep(for: .milliseconds(300))
    }

    public func light(notes: Set<Int>, state: TheOneProtocol.LampState = .primary) {
        setLamps(on: notes, off: litNotes.subtracting(notes), state: state)
    }

    public func lightOnly(_ notes: Set<Int>, state: TheOneProtocol.LampState = .primary) {
        light(notes: notes, state: state)
    }

    /// Turn some lights on and others off.
    public func setLamps(
        on turnOn: Set<Int>,
        off turnOff: Set<Int>,
        state: TheOneProtocol.LampState = .primary
    ) {
        for note in turnOff.sorted() {
            if let bytes = TheOneProtocol.lamp(note: note, state: .off) { send(bytes) }
        }
        for note in turnOn.sorted() {
            if let bytes = TheOneProtocol.lamp(note: note, state: state) { send(bytes) }
        }
        litNotes.formUnion(turnOn)
        litNotes.subtract(turnOff)
    }

    public func allLampsOff() {
        for frame in TheOneProtocol.allLampsOff { send(frame) }
        litNotes = []
    }

    /// Play a note out loud. Lighting a key is silent on its own.
    public func soundNote(_ note: Int, velocity: Int = 90, on: Bool = true) {
        let status: UInt8 = (on ? 0x90 : 0x80) | TheOneProtocol.keyPressChannel
        send([status, UInt8(clamping: note), UInt8(clamping: on ? velocity : 0)])
    }

    /// Stop any notes that are still sounding.
    public func allSoundOff() {
        for channel in UInt8(0)...15 {
            send([0xB0 | channel, 120, 0])   // All Sound Off
            send([0xB0 | channel, 123, 0])   // All Notes Off
        }
    }

    public func send(_ bytes: [UInt8]) {
        guard status.isConnected, outputPort != 0, destination != 0 else { return }

        // Give the message plenty of room, so a longer one can never overflow.
        let capacity = 1024
        guard bytes.count > 0, bytes.count + MemoryLayout<MIDIPacketList>.size <= capacity else {
            return
        }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: capacity, alignment: 16)
        defer { raw.deallocate() }
        let list = raw.bindMemory(to: MIDIPacketList.self, capacity: 1)

        let first = MIDIPacketListInit(list)
        _ = MIDIPacketListAdd(list, capacity, first, 0, bytes.count, bytes)
        MIDISend(outputPort, destination, list)
    }

    // MARK: - Receiving

    private func receive(_ events: [KeyEvent]) {
        for event in events {
            if event.isDown {
                heldNotes.insert(event.note)
            } else {
                heldNotes.remove(event.note)
            }
            onKeyEvent?(event)
        }
    }

    /// Work out which keys were pressed or released.
    ///
    /// The keyboard also sends a constant background hum of timing messages that
    /// mean nothing here, so those are ignored.
    private static func parse(_ packetList: UnsafePointer<MIDIPacketList>) -> [KeyEvent] {
        var events: [KeyEvent] = []
        for packet in packetList.unsafeSequence() {
            let bytes = withUnsafeBytes(of: packet.pointee.data) { raw in
                Array(raw.prefix(Int(packet.pointee.length)))
            }
            var i = 0
            while i < bytes.count {
                let status = bytes[i]
                guard status >= 0x80 else { i += 1; continue }   // orphaned data byte
                if status >= 0xF8 { i += 1; continue }           // real-time chatter
                let kind = status & 0xF0
                guard kind == 0x90 || kind == 0x80, i + 2 < bytes.count else {
                    i += 1
                    continue
                }
                let note = Int(bytes[i + 1])
                let velocity = Int(bytes[i + 2])
                // This keyboard reports a release as a press with no force behind
                // it, so check for that or every key looks permanently held.
                let isDown = kind == 0x90 && velocity > 0
                events.append(KeyEvent(note: note, isDown: isDown, velocity: velocity))
                i += 3
            }
        }
        return events
    }
}
