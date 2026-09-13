import Foundation

public enum Hand: Sendable, Hashable {
    case left, right, unknown
}

/// How we worked out which hand plays what, so the app can be honest about it.
public enum HandSignal: String, Sendable {
    case trackName = "track names"
    case channel = "MIDI channels"
    case track = "track pitch ranges"
    case pitch = "pitch split (approximate)"
    case none = "none"

    public var isReliable: Bool { self == .trackName || self == .channel }
}

/// One thing to play: a single note, or a chord.
public struct LessonStep: Sendable, Identifiable, Equatable {
    public let id: Int
    public let keys: [Int]
    public let hands: [Int: Hand]
    /// Where this comes in the song. Practice never rushes you; this is only used
    /// for the progress bar and for playing the song back.
    public let time: Double

    public var isChord: Bool { keys.count > 1 }
}

/// One note starting or stopping, at a particular moment in the song.
///
/// Playing a song back needs to know exactly when each note begins and ends.
/// Practice doesn't — it waits for you — so the two are kept separate. Without
/// this, the same note played twice in a row runs together as one long sound, and
/// a held bass note gets cut off early.
public struct PlaybackEvent: Sendable, Equatable {
    public let time: Double
    public let note: Int
    public let isOn: Bool
    public let velocity: Int

    public init(time: Double, note: Int, isOn: Bool, velocity: Int = 90) {
        self.time = time
        self.note = note
        self.isOn = isOn
        self.velocity = velocity
    }
}

public struct Lesson: Sendable {
    public let name: String
    public let steps: [LessonStep]
    /// The song as it should sound, for playing back.
    public let playback: [PlaybackEvent]
    public let handSignal: HandSignal
    /// Notes too high or low for this keyboard, which had to be left out.
    public let droppedNotes: [Int]
    /// Notes moved up or down an octave to fit on the keyboard. They'll sound a
    /// little different from the original, so the app says when this happened.
    public let transposedNotes: [Int]

    public var keysUsed: Set<Int> { Set(steps.flatMap(\.keys)) }
    public var chordCount: Int { steps.filter(\.isChord).count }

    public init(
        name: String,
        steps: [LessonStep],
        playback: [PlaybackEvent] = [],
        handSignal: HandSignal,
        droppedNotes: [Int] = [],
        transposedNotes: [Int] = []
    ) {
        self.name = name
        self.steps = steps
        self.playback = playback
        self.handSignal = handSignal
        self.droppedNotes = droppedNotes
        self.transposedNotes = transposedNotes
    }

    /// Nothing in this song can be played on a 61-key keyboard.
    public var isEmpty: Bool { steps.isEmpty }

    /// The tiny gap left between a note ending and the same note starting again.
    ///
    /// Without it, two of the same note in a row blur into one. Twenty thousandths
    /// of a second is too short to notice but enough to hear them separately.
    public static let minRetriggerGap: Double = 0.02

    // MARK: - Compilation

    public enum HandFilter: String, CaseIterable, Sendable {
        case both = "Both hands"
        case right = "Right hand"
        case left = "Left hand"
    }

    /// Turn a song into a list of things to play, one at a time.
    ///
    /// Notes that start together become a chord. How long each note was originally
    /// held doesn't matter here, because practice waits for you rather than moving
    /// on by itself.
    public static func compile(
        from file: MIDIFile,
        name: String,
        hand: HandFilter = .both,
        chordWindow: Double = 0.05,
        range: ClosedRange<Int> = TheOneProtocol.keyRange,
        transposeIntoRange: Bool = false
    ) -> Lesson {
        let (handMap, signal) = assignHands(file)

        var dropped: [Int] = []
        var transposed: [Int] = []
        var playable: [(time: Double, duration: Double, velocity: Int, note: Int, hand: Hand)] = []

        for note in file.notes {
            let assigned = handMap[note.id] ?? .unknown
            switch hand {
            case .both: break
            case .right where assigned != .right: continue
            case .left where assigned != .left: continue
            default: break
            }

            var pitch = note.note
            if !range.contains(pitch) {
                if transposeIntoRange {
                    while pitch < range.lowerBound { pitch += 12 }
                    while pitch > range.upperBound { pitch -= 12 }
                    if range.contains(pitch) { transposed.append(note.note) }
                }
                guard range.contains(pitch) else {
                    dropped.append(note.note)
                    continue
                }
            }
            playable.append((note.start, note.duration, note.velocity, pitch, assigned))
        }

        playable.sort { $0.time == $1.time ? $0.note < $1.note : $0.time < $1.time }

        var steps: [LessonStep] = []
        var group: [(time: Double, duration: Double, velocity: Int, note: Int, hand: Hand)] = []

        func flush() {
            guard let first = group.first else { return }
            var hands: [Int: Hand] = [:]
            for item in group { hands[item.note] = item.hand }
            steps.append(
                LessonStep(
                    id: steps.count,
                    keys: Array(Set(group.map(\.note))).sorted(),
                    hands: hands,
                    time: first.time
                )
            )
            group.removeAll()
        }

        for item in playable {
            if let first = group.first, item.time - first.time > chordWindow { flush() }
            group.append(item)
        }
        flush()

        return Lesson(
            name: name,
            steps: steps,
            playback: playbackEvents(for: playable),
            handSignal: signal,
            droppedNotes: dropped,
            transposedNotes: transposed
        )
    }

    /// Work out exactly when each note starts and stops.
    ///
    /// When the same note is played twice in a row, the first one is shortened
    /// slightly so you can hear them as two notes rather than one.
    private static func playbackEvents(
        for notes: [(time: Double, duration: Double, velocity: Int, note: Int, hand: Hand)]
    ) -> [PlaybackEvent] {
        // Per pitch, so trimming only ever affects the same key.
        var byPitch: [Int: [(start: Double, end: Double, velocity: Int)]] = [:]
        for note in notes {
            byPitch[note.note, default: []].append(
                (note.time, note.time + max(note.duration, 0.01), note.velocity)
            )
        }

        var events: [PlaybackEvent] = []
        for (pitch, var occurrences) in byPitch {
            occurrences.sort { $0.start < $1.start }
            for i in occurrences.indices {
                var end = occurrences[i].end
                if i + 1 < occurrences.count {
                    let nextStart = occurrences[i + 1].start
                    // End this one early enough to be heard separately.
                    end = min(end, nextStart - minRetriggerGap)
                }
                let start = occurrences[i].start
                // Never shorten a note out of existence.
                end = max(end, start + 0.005)
                events.append(PlaybackEvent(time: start, note: pitch, isOn: true,
                                            velocity: occurrences[i].velocity))
                events.append(PlaybackEvent(time: end, note: pitch, isOn: false))
            }
        }

        // Stop notes before starting new ones, or a repeat cancels itself out.
        events.sort {
            $0.time == $1.time
                ? ($0.isOn == $1.isOn ? $0.note < $1.note : !$0.isOn)
                : $0.time < $1.time
        }
        return events
    }

    /// Work out which hand plays each note.
    ///
    /// MIDI files don't have to say, so we try the most reliable clues first and
    /// report which one we ended up using.
    private static func assignHands(_ file: MIDIFile) -> ([UUID: Hand], HandSignal) {
        let leftHints = ["left", "lh", "l.h", "bass"]
        let rightHints = ["right", "rh", "r.h", "melody", "treble"]

        // Best case: the parts are actually labelled "Left Hand" and "Right Hand".
        var byName: [UUID: Hand] = [:]
        var namedAll = !file.notes.isEmpty
        for note in file.notes {
            let lowered = note.trackName.lowercased()
            if leftHints.contains(where: lowered.contains) {
                byName[note.id] = .left
            } else if rightHints.contains(where: lowered.contains) {
                byName[note.id] = .right
            } else {
                namedAll = false
            }
        }
        if namedAll { return (byName, .trackName) }

        // Two separate parts usually means right hand first, left hand second.
        let channels = Set(file.notes.map(\.channel)).sorted()
        if channels.count == 2 {
            var map: [UUID: Hand] = [:]
            for note in file.notes {
                map[note.id] = note.channel == channels[0] ? .right : .left
            }
            return (map, .channel)
        }

        // Two sections: the lower-sounding one is almost always the left hand.
        let tracks = Dictionary(grouping: file.notes, by: \.track)
        if tracks.count == 2 {
            let averages = tracks.mapValues { notes in
                Double(notes.map(\.note).reduce(0, +)) / Double(notes.count)
            }
            if let leftTrack = averages.min(by: { $0.value < $1.value })?.key {
                var map: [UUID: Hand] = [:]
                for note in file.notes {
                    map[note.id] = note.track == leftTrack ? .left : .right
                }
                return (map, .track)
            }
        }

        // Last resort: split at middle C. Wrong wherever the hands cross over,
        // which is why the app tells you when it had to guess this way.
        var map: [UUID: Hand] = [:]
        for note in file.notes {
            map[note.id] = note.note < 60 ? .left : .right
        }
        return (map, .pitch)
    }
}

// MARK: - Session

/// Keeps track of where you are in a song.
///
/// Two rules shape how it feels to use:
///
/// You have to actually press a key for it to count — holding one down from the
/// previous note isn't enough. Otherwise a run of repeated notes would race to the
/// end on its own. It's also just how playing works: playing the same note twice
/// means pressing it twice.
///
/// Wrong notes are counted but never hold you up. It keeps waiting for the right
/// one, so a slip never leaves you stuck.
public struct LessonSession: Sendable {
    public let lesson: Lesson
    public private(set) var index: Int = 0
    public private(set) var held: Set<Int> = []
    /// Which of the keys you need have been pressed since this note came up.
    public private(set) var fresh: Set<Int> = []
    public private(set) var mistakes: Int = 0
    public private(set) var wrongKeys: [Int: Int] = [:]
    public private(set) var stepsCompleted: Int = 0

    /// Make chords require every note held down at once. More demanding; off by
    /// default.
    public var requireSimultaneous: Bool

    public init(lesson: Lesson, requireSimultaneous: Bool = false) {
        self.lesson = lesson
        self.requireSimultaneous = requireSimultaneous
    }

    public var current: LessonStep? {
        index < lesson.steps.count ? lesson.steps[index] : nil
    }

    public var next: LessonStep? {
        index + 1 < lesson.steps.count ? lesson.steps[index + 1] : nil
    }

    public var isFinished: Bool { index >= lesson.steps.count }

    public var remaining: [Int] {
        guard let step = current else { return [] }
        return step.keys.filter { !fresh.contains($0) }
    }

    /// How far through the song you are.
    ///
    /// This is your position, not your score. Skipping ahead moves you along
    /// without pretending you played the notes you skipped.
    public var progress: Double {
        lesson.steps.isEmpty ? 1 : Double(index) / Double(lesson.steps.count)
    }

    /// Which note you're on, out of the total.
    public var positionLabel: String {
        "\(min(index + 1, lesson.steps.count))/\(lesson.steps.count)"
    }

    /// How far into the song this is, in seconds.
    public var currentTime: Double {
        guard !lesson.steps.isEmpty else { return 0 }
        return current?.time ?? lesson.steps[lesson.steps.count - 1].time
    }

    public var totalTime: Double { lesson.steps.last?.time ?? 0 }

    public var accuracy: Double {
        let total = stepsCompleted + mistakes
        return total == 0 ? 1 : Double(stepsCompleted) / Double(total)
    }

    public struct Result: Sendable, Equatable {
        public let key: Int
        public let correct: Bool
        public let stepComplete: Bool
        public let finished: Bool
    }

    public mutating func keyDown(_ key: Int) -> Result {
        held.insert(key)
        guard let step = current else {
            return Result(key: key, correct: false, stepComplete: false, finished: true)
        }
        guard step.keys.contains(key) else {
            mistakes += 1
            wrongKeys[key, default: 0] += 1
            return Result(key: key, correct: false, stepComplete: false, finished: false)
        }

        fresh.insert(key)
        let required = Set(step.keys)
        let satisfied = required.isSubset(of: fresh)
            && (!requireSimultaneous || required.isSubset(of: held))
        guard satisfied else {
            return Result(key: key, correct: true, stepComplete: false, finished: false)
        }

        stepsCompleted += 1
        index += 1
        // A new step starts with nothing credited: keys still physically held do
        // not count until released and pressed again.
        fresh.removeAll()
        return Result(key: key, correct: true, stepComplete: true, finished: isFinished)
    }

    public mutating func keyUp(_ key: Int) {
        held.remove(key)
    }

    public mutating func restart() {
        index = 0
        fresh.removeAll()
        mistakes = 0
        wrongKeys.removeAll()
        stepsCompleted = 0
    }

    /// Jump to a particular point in the song.
    /// Which keys should be lit up right now.
    ///
    /// Normally a key goes dark as soon as you play it, so what's left lit is what
    /// you still owe. But when chords have to be held together, the whole chord
    /// stays lit until you have it — otherwise letting go of one note would leave
    /// you staring at a chord you can no longer see.
    public var keysToLight: Set<Int> {
        guard let step = current else { return [] }
        let all = Set(step.keys)
        return requireSimultaneous ? all : all.subtracting(fresh)
    }

    public mutating func seek(to step: Int) {
        index = min(max(step, 0), lesson.steps.count)
        fresh.removeAll()
    }
}

// MARK: - Note names

public enum NoteName {
    private static let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]

    public static func of(_ note: Int) -> String {
        "\(names[((note % 12) + 12) % 12])\(note / 12 - 1)"
    }

    public static func isBlackKey(_ note: Int) -> Bool {
        [1, 3, 6, 8, 10].contains(((note % 12) + 12) % 12)
    }
}
