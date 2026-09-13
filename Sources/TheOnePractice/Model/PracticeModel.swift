import Foundation
import Observation

/// A song in your library.
public struct SongEntry: Identifiable, Sendable, Hashable {
    public let id = UUID()
    public let url: URL
    public let title: String
    public let noteCount: Int
    public let duration: Double
    public let handSignal: HandSignal

    public var subtitle: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return "\(noteCount) notes · \(minutes):\(String(format: "%02d", seconds))"
    }

    public static func == (a: SongEntry, b: SongEntry) -> Bool { a.url == b.url }
    public func hash(into hasher: inout Hasher) { hasher.combine(url) }
}

/// The state of the app: your songs, your settings, and how you're doing.
@MainActor
@Observable
public final class PracticeModel {

    public enum Mode: String, CaseIterable, Sendable {
        /// Waits for you to play each note. This is the main way to use the app.
        case practice = "Practice"
        /// Plays the song for you, so you can hear and see how it goes.
        case listen = "Listen"
    }

    // MARK: - State

    public let piano = PianoConnection()
    /// Where your songs are kept.
    public let library = SongLibrary()

    public var songs: [SongEntry] = []
    public var selectedSong: SongEntry?
    public var mode: Mode = .practice
    public var handFilter: Lesson.HandFilter = .both
    public var requireSimultaneous = false
    public var soundNotes = true
    /// Move notes that are too high or low onto the keyboard, instead of skipping
    /// them.
    ///
    /// On by default. Most piano music is written for a full-size 88-key piano, so
    /// without this a 61-key keyboard quietly drops notes — and a low-pitched piece
    /// can lose all of them, which just looks broken.
    public var fitToKeyboard = true
    /// How fast to play the song. Below 1 is slower than written.
    public var tempoScale: Double = 0.7

    public private(set) var lesson: Lesson?
    public private(set) var session: LessonSession?
    public private(set) var isRunning = false
    public private(set) var lastError: String?
    public private(set) var statusMessage: String = "Connect the keyboard to begin."
    /// The last wrong note, so it can flash red for a moment.
    public private(set) var lastWrongKey: Int?
    /// Where you're about to jump to, while dragging the progress bar.
    public private(set) var scrubTarget: Int?

    private var playbackTask: Task<Void, Never>?

    public init() {
        piano.onKeyEvent = { [weak self] event in
            self?.handle(event)
        }
        loadSavedSongs()
    }

    /// Load the songs you've added before.
    private func loadSavedSongs() {
        for url in library.songs() {
            guard let entry = makeEntry(for: url) else { continue }
            if !songs.contains(entry) { songs.append(entry) }
        }
        if selectedSong == nil, let first = songs.first { select(first) }
    }

    private func makeEntry(for url: URL) -> SongEntry? {
        guard let file = try? MIDIFile(url: url), !file.notes.isEmpty else { return nil }
        let lesson = Lesson.compile(
            from: file, name: url.deletingPathExtension().lastPathComponent
        )
        return SongEntry(
            url: url,
            title: url.deletingPathExtension().lastPathComponent,
            noteCount: file.notes.count,
            duration: file.duration,
            handSignal: lesson.handSignal
        )
    }

    // MARK: - Library

    /// Add songs to your library.
    ///
    /// Each file is checked, then copied into the app's own folder — so your songs
    /// stay put even if you move or delete the originals.
    public func importSongs(urls: [URL]) {
        for url in urls {
            do {
                // Check it is a song we can actually play before saving a copy.
                let file = try MIDIFile(url: url)
                guard !file.notes.isEmpty else {
                    lastError = "\(url.lastPathComponent) has no notes in it."
                    continue
                }

                let saved = try library.add(url)
                guard let entry = makeEntry(for: saved) else {
                    lastError = "Could not read \(url.lastPathComponent) after saving it."
                    continue
                }
                if !songs.contains(entry) { songs.append(entry) }
                if selectedSong == nil { select(entry) }
                lastError = nil
            } catch {
                lastError = "\(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
    }

    public func reportImportFailure(_ error: Error) {
        lastError = "Import failed: \(error.localizedDescription)"
    }

    public func remove(_ entry: SongEntry) {
        library.remove(entry.url)
        songs.removeAll { $0 == entry }
        if selectedSong == entry {
            selectedSong = songs.first
            if let next = selectedSong { select(next) } else { lesson = nil; session = nil }
        }
    }

    public func select(_ entry: SongEntry) {
        stop()
        selectedSong = entry
        reloadLesson()
    }

    /// Rebuild the song after changing a setting that affects it.
    public func reloadLesson() {
        guard let entry = selectedSong else { lesson = nil; session = nil; return }
        do {
            let file = try MIDIFile(url: entry.url)
            let built = Lesson.compile(
                from: file, name: entry.title, hand: handFilter,
                transposeIntoRange: fitToKeyboard
            )
            lesson = built
            session = LessonSession(lesson: built, requireSimultaneous: requireSimultaneous)
            statusMessage = describe(built)
            lastError = nil
        } catch {
            lesson = nil
            session = nil
            lastError = error.localizedDescription
        }
    }

    private func describe(_ lesson: Lesson) -> String {
        guard !lesson.isEmpty else {
            return "Nothing playable on a 61-key keyboard."
        }
        var parts = ["\(lesson.steps.count) steps"]
        if lesson.chordCount > 0 { parts.append("\(lesson.chordCount) chords") }
        parts.append("hands from \(lesson.handSignal.rawValue)")
        if !lesson.transposedNotes.isEmpty {
            parts.append("\(lesson.transposedNotes.count) notes octave-shifted to fit")
        }
        if !lesson.droppedNotes.isEmpty {
            parts.append("\(lesson.droppedNotes.count) notes dropped")
        }
        return parts.joined(separator: " · ")
    }

    /// Something worth telling you about this song, if anything.
    public var songWarning: String? {
        guard let lesson else { return nil }
        if lesson.isEmpty {
            return fitToKeyboard
                ? "None of this song's notes fit a 61-key keyboard, even shifted by octaves."
                : "None of this song's notes are within the keyboard's range. Turn on “Fit to keyboard”."
        }
        if !lesson.droppedNotes.isEmpty {
            let unique = Set(lesson.droppedNotes).sorted().map(NoteName.of).prefix(4)
            return "\(lesson.droppedNotes.count) notes are outside the keyboard and will not light "
                + "(\(unique.joined(separator: ", "))\(Set(lesson.droppedNotes).count > 4 ? "…" : ""))."
                + (fitToKeyboard ? "" : " Turn on “Fit to keyboard” to shift them in.")
        }
        return nil
    }

    // MARK: - Connection

    public func connect() {
        piano.connect()
        switch piano.status {
        case .connected(let name):
            statusMessage = "Connected to \(name)."
            lastError = nil
            Task { await piano.prepareIfNeeded() }
        case .failed(let reason):
            lastError = reason
        case .disconnected:
            break
        }
    }

    // MARK: - Running

    public func start() {
        guard piano.status.isConnected else {
            lastError = "Connect the keyboard first."
            return
        }
        guard let lesson else {
            lastError = "Import a MIDI file first."
            return
        }
        guard !lesson.isEmpty else {
            lastError = songWarning ?? "This song has no playable notes."
            return
        }
        session = LessonSession(lesson: lesson, requireSimultaneous: requireSimultaneous)
        isRunning = true
        lastWrongKey = nil

        playbackTask = Task { @MainActor in
            await piano.prepareIfNeeded()
            piano.allLampsOff()
            switch mode {
            case .practice:
                showCurrentStep()
                statusMessage = "Play the lit key."
            case .listen:
                await runListenMode(lesson, from: session?.index ?? 0)
            }
        }
    }

    public func stop() {
        playbackTask?.cancel()
        playbackTask = nil
        isRunning = false
        piano.allLampsOff()
        piano.allSoundOff()
    }

    public func restart() {
        stop()
        start()
    }

    // MARK: - Seeking

    /// Show where dragging would take you, without moving there yet.
    ///
    /// The keyboard's lights only change when you let go, rather than flickering
    /// through every note you drag past.
    public func scrub(toFraction fraction: Double) {
        guard let lesson, !lesson.steps.isEmpty else { return }
        scrubTarget = stepIndex(for: fraction, in: lesson)
    }

    /// Jump to a new spot in the song.
    public func seek(toFraction fraction: Double) {
        guard let lesson, !lesson.steps.isEmpty else { return }
        seek(toStep: stepIndex(for: fraction, in: lesson))
    }

    public func seek(toStep step: Int) {
        guard let lesson, !lesson.steps.isEmpty else { return }
        let target = min(max(step, 0), lesson.steps.count - 1)
        scrubTarget = nil

        if session == nil {
            session = LessonSession(lesson: lesson, requireSimultaneous: requireSimultaneous)
        }
        session?.seek(to: target)

        switch (mode, isRunning) {
        case (.listen, true):
            // Start playing again from the new spot.
            playbackTask?.cancel()
            playbackTask = Task { @MainActor in
                await runListenMode(lesson, from: target)
            }
        default:
            // Light up wherever you landed, so you can see where you'll start.
            showCurrentStep()
        }
    }

    private func stepIndex(for fraction: Double, in lesson: Lesson) -> Int {
        let clamped = min(max(fraction, 0), 1)
        let index = Int((Double(lesson.steps.count) * clamped).rounded(.down))
        return min(index, lesson.steps.count - 1)
    }

    /// The note you'd land on, shown while dragging.
    public var scrubLabel: String? {
        guard let scrubTarget, let lesson, lesson.steps.indices.contains(scrubTarget)
        else { return nil }
        return lesson.steps[scrubTarget].keys.map(NoteName.of).joined(separator: " + ")
    }

    // MARK: - Practice mode

    /// Light up whatever you need to play right now.
    private func showCurrentStep() {
        guard let session, session.current != nil else {
            piano.allLampsOff()
            return
        }
        // One note at a time. The keyboard can't dim a light, so showing the next
        // note too would just look like two notes to play at once.
        piano.light(notes: session.keysToLight)
    }

    private func handle(_ event: PianoConnection.KeyEvent) {
        guard isRunning, mode == .practice, session != nil else { return }

        if !event.isDown {
            session?.keyUp(event.note)
            // When chords must be held together, letting go changes what's needed.
            if requireSimultaneous { showCurrentStep() }
            return
        }

        guard let result = session?.keyDown(event.note) else { return }

        if !result.correct {
            lastWrongKey = event.note
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                if self.lastWrongKey == event.note { self.lastWrongKey = nil }
            }
            return
        }

        if result.finished {
            finish()
        } else {
            showCurrentStep()
        }
    }

    private func finish() {
        isRunning = false
        piano.allLampsOff()
        guard let session else { return }
        let percent = Int((session.accuracy * 100).rounded())
        statusMessage = session.mistakes == 0
            ? "Finished — no mistakes."
            : "Finished — \(session.mistakes) mistakes, \(percent)% accuracy."
    }

    // MARK: - Listen mode

    private func runListenMode(_ lesson: Lesson, from startIndex: Int) async {
        statusMessage = "Playing…"
        guard lesson.steps.indices.contains(startIndex) else { return }
        isRunning = true

        let offset = lesson.steps[startIndex].time
        let events = lesson.playback.filter { $0.time >= offset - 0.0001 }
        guard !events.isEmpty else {
            isRunning = false
            statusMessage = lesson.isEmpty
                ? "Nothing playable on a 61-key keyboard — see the warning above."
                : "No notes from this point onward. Drag the timeline back."
            return
        }

        // Time everything from one starting moment, so the song doesn't gradually
        // fall behind.
        let start = ContinuousClock.now
        var sounding: Set<Int> = []
        var stepCursor = startIndex

        for event in events {
            let due = start + .seconds((event.time - offset) / max(tempoScale, 0.01))
            let wait = due - ContinuousClock.now
            if wait > .zero {
                do { try await Task.sleep(for: wait) } catch { break }
            }
            if Task.isCancelled { break }

            if event.isOn {
                piano.setLamps(on: [event.note], off: [])
                if soundNotes { piano.soundNote(event.note, velocity: event.velocity) }
                sounding.insert(event.note)
            } else {
                piano.setLamps(on: [], off: [event.note])
                if soundNotes { piano.soundNote(event.note, on: false) }
                sounding.remove(event.note)
            }

            // Move the progress bar along as the song plays.
            while stepCursor + 1 < lesson.steps.count,
                  lesson.steps[stepCursor + 1].time <= event.time + 0.0001 {
                stepCursor += 1
            }
            if session?.index != stepCursor { session?.seek(to: stepCursor) }
        }

        // Make sure nothing is left sounding.
        if soundNotes {
            for note in sounding { piano.soundNote(note, on: false) }
            piano.allSoundOff()
        }
        piano.allLampsOff()
        isRunning = false
        statusMessage = Task.isCancelled ? "Stopped." : "Finished playing."
    }

    // MARK: - Derived UI state

    /// Keys to show lit on screen.
    public var highlightedKeys: Set<Int> { piano.litNotes }
    /// Keys you're holding down.
    public var pressedKeys: Set<Int> { piano.heldNotes }

    public var upcomingLabel: String {
        if let scrubLabel { return scrubLabel }
        guard let step = session?.current else { return "—" }
        return step.keys.map(NoteName.of).joined(separator: " + ")
    }

    /// Where the progress bar should sit.
    public var timelineProgress: Double {
        if let scrubTarget, let lesson, !lesson.steps.isEmpty {
            return Double(scrubTarget) / Double(lesson.steps.count)
        }
        return session?.progress ?? 0
    }
}
