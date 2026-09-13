import Foundation

/// Reads a MIDI file.
///
/// Pulls out the notes, when each one starts and how long it lasts, and the names
/// of the parts. Those names matter: a part called "Left Hand" is the only
/// reliable way to know which hand plays what.
public struct MIDIFile: Sendable {

    public struct Note: Sendable, Identifiable, Equatable {
        public let id = UUID()
        public let note: Int
        /// Seconds from the start of the file.
        public let start: Double
        public let duration: Double
        public let velocity: Int
        public let track: Int
        public let channel: Int
        public let trackName: String

        public var end: Double { start + duration }

        public static func == (a: Note, b: Note) -> Bool {
            a.note == b.note && a.start == b.start && a.track == b.track
        }
    }

    public enum ParseError: LocalizedError, Equatable {
        case notAMIDIFile
        case truncated(String)
        case unsupported(String)

        public var errorDescription: String? {
            switch self {
            case .notAMIDIFile:
                "That file is not a MIDI file — it has no MThd header."
            case .truncated(let detail):
                "The MIDI file ends unexpectedly (\(detail))."
            case .unsupported(let detail):
                "Unsupported MIDI file: \(detail)."
            }
        }
    }

    public let notes: [Note]
    public let trackNames: [String]
    public let ticksPerBeat: Int
    /// Length in seconds.
    public var duration: Double { notes.map(\.end).max() ?? 0 }

    // MARK: - Parsing

    public init(data: Data) throws {
        var reader = Reader(data: data)

        guard reader.readASCII(4) == "MThd" else { throw ParseError.notAMIDIFile }
        let headerLength = try reader.readUInt32()
        let format = try reader.readUInt16()
        let trackCount = try reader.readUInt16()
        let division = try reader.readInt16()
        // Skip any header bytes beyond the six we understand.
        if headerLength > 6 { reader.skip(Int(headerLength) - 6) }

        guard format == 0 || format == 1 else {
            throw ParseError.unsupported("format \(format); only 0 and 1 are supported")
        }
        guard division > 0 else {
            throw ParseError.unsupported("SMPTE time division; only ticks-per-beat is supported")
        }
        self.ticksPerBeat = Int(division)

        // First pass: find the speed changes. They're stored in one part but apply
        // to all of them, so we need them before working out any timings.
        var trackData: [Data] = []
        for _ in 0..<trackCount {
            guard let chunk = try reader.readChunk() else { break }
            trackData.append(chunk)
        }

        let tempoMap = Self.tempoMap(from: trackData, ticksPerBeat: Int(division))

        // Second pass: the notes, timed in seconds.
        var allNotes: [Note] = []
        var names: [String] = []
        for (index, chunk) in trackData.enumerated() {
            let (trackNotes, name) = try Self.parseTrack(
                chunk, index: index, tempoMap: tempoMap, ticksPerBeat: Int(division)
            )
            allNotes.append(contentsOf: trackNotes)
            names.append(name)
        }

        self.notes = allNotes.sorted {
            $0.start == $1.start ? $0.note < $1.note : $0.start < $1.start
        }
        self.trackNames = names
    }

    public init(url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    // MARK: - Tempo

    /// Where the song changes speed, and to what.
    private static func tempoMap(from tracks: [Data], ticksPerBeat: Int) -> [(tick: Int, usPerBeat: Int)] {
        var map: [(tick: Int, usPerBeat: Int)] = []
        for chunk in tracks {
            var reader = Reader(data: chunk)
            var tick = 0
            var runningStatus: UInt8 = 0
            while !reader.isAtEnd {
                guard let delta = try? reader.readVarLength() else { break }
                tick += delta
                guard let event = try? reader.readEvent(runningStatus: &runningStatus) else { break }
                if case .meta(let type, let payload) = event, type == 0x51, payload.count >= 3 {
                    let us = (Int(payload[0]) << 16) | (Int(payload[1]) << 8) | Int(payload[2])
                    map.append((tick, us))
                }
            }
        }
        map.sort { $0.tick < $1.tick }
        if map.isEmpty || map[0].tick > 0 {
            map.insert((0, 500_000), at: 0)   // MIDI default: 120 bpm
        }
        return map
    }

    private static func seconds(
        atTick target: Int, tempoMap: [(tick: Int, usPerBeat: Int)], ticksPerBeat: Int
    ) -> Double {
        var seconds = 0.0
        var lastTick = 0
        var usPerBeat = tempoMap.first?.usPerBeat ?? 500_000

        for entry in tempoMap {
            if entry.tick >= target { break }
            let span = entry.tick - lastTick
            seconds += Double(span) * Double(usPerBeat) / (Double(ticksPerBeat) * 1_000_000)
            lastTick = entry.tick
            usPerBeat = entry.usPerBeat
        }
        let span = target - lastTick
        seconds += Double(span) * Double(usPerBeat) / (Double(ticksPerBeat) * 1_000_000)
        return seconds
    }

    // MARK: - Tracks

    private static func parseTrack(
        _ chunk: Data, index: Int,
        tempoMap: [(tick: Int, usPerBeat: Int)], ticksPerBeat: Int
    ) throws -> ([Note], String) {
        var reader = Reader(data: chunk)
        var tick = 0
        var runningStatus: UInt8 = 0
        var name = ""
        var notes: [Note] = []
        // Notes that have started but not finished yet.
        var open: [Int: (tick: Int, velocity: Int)] = [:]

        while !reader.isAtEnd {
            guard let delta = try? reader.readVarLength() else { break }
            tick += delta
            guard let event = try? reader.readEvent(runningStatus: &runningStatus) else { break }

            switch event {
            case .meta(let type, let payload):
                if type == 0x03, name.isEmpty {
                    name = String(decoding: payload)
                }
            case .channel(let status, let data1, let data2):
                let kind = status & 0xF0
                let channel = Int(status & 0x0F)
                let key = channel << 8 | Int(data1)

                if kind == 0x90, data2 > 0 {
                    open[key] = (tick, Int(data2))
                } else if kind == 0x80 || (kind == 0x90 && data2 == 0) {
                    guard let started = open.removeValue(forKey: key) else { break }
                    let startSeconds = seconds(
                        atTick: started.tick, tempoMap: tempoMap, ticksPerBeat: ticksPerBeat
                    )
                    let endSeconds = seconds(
                        atTick: tick, tempoMap: tempoMap, ticksPerBeat: ticksPerBeat
                    )
                    notes.append(
                        Note(
                            note: Int(data1),
                            start: startSeconds,
                            duration: max(endSeconds - startSeconds, 0.01),
                            velocity: started.velocity,
                            track: index,
                            channel: channel,
                            trackName: name
                        )
                    )
                }
            case .sysex:
                break
            }
        }

        // If a note never ends, give it a short length rather than losing it.
        for (key, started) in open {
            let startSeconds = seconds(atTick: started.tick, tempoMap: tempoMap, ticksPerBeat: ticksPerBeat)
            notes.append(
                Note(
                    note: key & 0xFF, start: startSeconds, duration: 0.25,
                    velocity: started.velocity, track: index,
                    channel: key >> 8, trackName: name
                )
            )
        }

        // The part's name can appear after its first notes, so fill it in.
        if !name.isEmpty {
            notes = notes.map {
                Note(note: $0.note, start: $0.start, duration: $0.duration,
                     velocity: $0.velocity, track: $0.track, channel: $0.channel,
                     trackName: name)
            }
        }
        return (notes, name)
    }

    // MARK: - Byte reader

    private struct Reader {
        let data: Data
        var offset: Int = 0

        var isAtEnd: Bool { offset >= data.count }

        mutating func skip(_ count: Int) { offset += count }

        mutating func byte() throws -> UInt8 {
            guard offset < data.count else { throw ParseError.truncated("expected a byte") }
            defer { offset += 1 }
            return data[data.startIndex + offset]
        }

        mutating func readASCII(_ count: Int) -> String? {
            guard offset + count <= data.count else { return nil }
            let slice = data[(data.startIndex + offset)..<(data.startIndex + offset + count)]
            offset += count
            return String(data: slice, encoding: .ascii)
        }

        mutating func readUInt16() throws -> UInt16 {
            let hi = try byte(), lo = try byte()
            return UInt16(hi) << 8 | UInt16(lo)
        }

        mutating func readInt16() throws -> Int16 {
            Int16(bitPattern: try readUInt16())
        }

        mutating func readUInt32() throws -> UInt32 {
            var value: UInt32 = 0
            for _ in 0..<4 { value = value << 8 | UInt32(try byte()) }
            return value
        }

        /// A number stored across as many bytes as it needs.
        mutating func readVarLength() throws -> Int {
            var value = 0
            for _ in 0..<4 {
                let b = try byte()
                value = value << 7 | Int(b & 0x7F)
                if b & 0x80 == 0 { return value }
            }
            throw ParseError.truncated("variable-length quantity longer than 4 bytes")
        }

        mutating func readChunk() throws -> Data? {
            guard let type = readASCII(4) else { return nil }
            let length = Int(try readUInt32())
            guard offset + length <= data.count else {
                throw ParseError.truncated("track chunk claims \(length) bytes")
            }
            let start = data.startIndex + offset
            offset += length
            guard type == "MTrk" else { return try readChunk() }   // skip unknown chunks
            return data[start..<(start + length)]
        }

        enum Event {
            case channel(status: UInt8, data1: UInt8, data2: UInt8)
            case meta(type: UInt8, payload: Data)
            case sysex
        }

        mutating func readEvent(runningStatus: inout UInt8) throws -> Event {
            var status = try byte()

            if status < 0x80 {
                // Files often leave out repeated instructions, so reuse the last one.
                guard runningStatus >= 0x80 else {
                    throw ParseError.truncated("data byte with no running status")
                }
                offset -= 1
                status = runningStatus
            } else if status < 0xF0 {
                runningStatus = status
            }

            switch status {
            case 0xFF:
                let type = try byte()
                let length = try readVarLength()
                guard offset + length <= data.count else {
                    throw ParseError.truncated("meta event length \(length)")
                }
                let start = data.startIndex + offset
                offset += length
                // Take a real copy. A slice of the file remembers where it came
                // from, and reading it as if it started at zero crashes.
                return .meta(type: type, payload: Data(data[start..<(start + length)]))

            case 0xF0, 0xF7:
                let length = try readVarLength()
                skip(length)
                return .sysex

            default:
                let kind = status & 0xF0
                let data1 = try byte()
                // A couple of message types are one byte shorter than the rest.
                let data2: UInt8 = (kind == 0xC0 || kind == 0xD0) ? 0 : try byte()
                return .channel(status: status, data1: data1, data2: data2)
            }
        }
    }
}

private extension String {
    init(decoding data: Data) {
        self = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
    }
}
