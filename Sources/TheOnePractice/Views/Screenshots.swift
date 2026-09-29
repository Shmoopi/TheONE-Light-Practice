// Command-line tooling for the developer, not part of the app on iPhone or iPad —
// there is no command line to pass flags on, and no AppKit to write PNGs with.
#if os(macOS)

import AppKit
import SwiftUI

/// Saves pictures of the app's screens, used in the README.
///
/// Run the app with `--screenshots <folder>` and it writes the images and quits.
@MainActor
enum Screenshots {

    /// Play a song to the keyboard without opening a window.
    ///
    /// `--play <file>` is here for checking that a song really does drive the
    /// lights, which is hard to be sure of from the app alone.
    static func playIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--play"), arguments.count > flag + 1
        else { return false }

        let url = URL(fileURLWithPath: arguments[flag + 1])
        let seconds = arguments.firstIndex(of: "--seconds")
            .flatMap { arguments.count > $0 + 1 ? Double(arguments[$0 + 1]) : nil } ?? 15

        do {
            let file = try MIDIFile(url: url)
            let lesson = Lesson.compile(from: file, name: url.lastPathComponent)
            print("\(lesson.steps.count) steps, \(lesson.playback.count) note events")
            print("hands from \(lesson.handSignal.rawValue), \(lesson.droppedNotes.count) notes left out")

            let piano = PianoConnection()
            piano.connect()
            guard piano.status.isConnected else {
                print("could not connect: \(piano.status.description)")
                return true
            }
            print("connected to \(piano.status.description)")

            let semaphore = DispatchSemaphore(value: 0)
            Task { @MainActor in
                await piano.prepareIfNeeded()
                piano.allLampsOff()
                let start = ContinuousClock.now
                var lit = 0
                for event in lesson.playback where event.time < seconds {
                    let due = start + .seconds(event.time)
                    let wait = due - ContinuousClock.now
                    if wait > .zero { try? await Task.sleep(for: wait) }
                    if event.isOn {
                        piano.setLamps(on: [event.note], off: [])
                        lit += 1
                    } else {
                        piano.setLamps(on: [], off: [event.note])
                    }
                }
                piano.allLampsOff()
                print("lit \(lit) keys over \(seconds)s")
                semaphore.signal()
            }
            semaphore.wait()
        } catch {
            print("could not read \(url.lastPathComponent): \(error.localizedDescription)")
        }
        return true
    }

    static func runIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--screenshots") else { return false }
        let folder = arguments.count > flag + 1
            ? URL(fileURLWithPath: arguments[flag + 1])
            : URL(fileURLWithPath: "screenshots")
        capture(into: folder)
        return true
    }

    static func capture(into folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        for (name, view) in scenes() {
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.cgImage else {
                FileHandle.standardError.write(Data("could not render \(name)\n".utf8))
                continue
            }
            let url = folder.appendingPathComponent("\(name).png")
            write(image, to: url)
            print("wrote \(url.path)")
        }
    }

    private static func write(_ image: CGImage, to url: URL) {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url)
    }

    // MARK: - Scenes

    private static func scenes() -> [(String, AnyView)] {
        [
            ("practice", AnyView(practiceScene())),
            ("keyboard", AnyView(keyboardScene())),
        ]
    }

    /// The main screen, part-way through a song.
    private static func practiceScene() -> some View {
        let lesson = exampleLesson()
        var session = LessonSession(lesson: lesson)
        for _ in 0..<11 { _ = session.keyDown(session.current?.keys.first ?? 0) }
        _ = session.keyDown(99)   // a wrong note, so the figures aren't all zero

        return ScreenshotFrame {
            VStack(spacing: 18) {
                VStack(spacing: 4) {
                    Text("PLAY")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(session.current.map { $0.keys.map(NoteName.of).joined(separator: " + ") } ?? "—")
                        .font(.system(size: 56, weight: .light, design: .rounded))
                }

                VStack(spacing: 8) {
                    ExampleSeekBar(progress: session.progress)
                    HStack(spacing: 18) {
                        stat("Step", session.positionLabel)
                        stat("Played", "\(session.stepsCompleted)")
                        stat("Mistakes", "\(session.mistakes)")
                        stat("Accuracy", "\(Int((session.accuracy * 100).rounded()))%")
                    }
                }

                PianoKeyboardView(
                    range: TheOneProtocol.keyRange,
                    lit: Set(session.current?.keys ?? []),
                    pressed: [55],
                    wrongKey: nil
                )
                .frame(height: 110)
                KeyboardLegend()
            }
            .padding(24)
            .frame(width: 760)
        }
    }

    /// A close-up of the keyboard with every colour showing.
    private static func keyboardScene() -> some View {
        ScreenshotFrame {
            VStack(spacing: 10) {
                PianoKeyboardView(
                    range: 48...84,
                    lit: [60, 64],
                    pressed: [64, 67],
                    wrongKey: 67
                )
                .frame(height: 130)
                KeyboardLegend()
            }
            .padding(24)
            .frame(width: 700)
        }
    }

    private static func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.title3.monospacedDigit().weight(.medium))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private static func exampleLesson() -> Lesson {
        // The opening of Ode to Joy.
        let melody = [64, 64, 65, 67, 67, 65, 64, 62, 60, 60, 62, 64, 64, 62, 62]
        return Lesson(
            name: "Ode to Joy",
            steps: melody.enumerated().map { index, note in
                LessonStep(id: index, keys: [note], hands: [note: .right],
                           time: Double(index) * 0.5)
            },
            handSignal: .trackName
        )
    }
}

/// A plain background, so the pictures look the same everywhere.
private struct ScreenshotFrame<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .environment(\.colorScheme, .light)
            .background(Color(white: 0.98))
    }
}

/// A still version of the progress bar, for the pictures.
private struct ExampleSeekBar: View {
    let progress: Double

    var body: some View {
        VStack(spacing: 2) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary).frame(height: 5)
                    Capsule().fill(.tint).frame(width: geo.size.width * progress, height: 5)
                    Circle().fill(.white).shadow(radius: 1, y: 0.5)
                        .frame(width: 11, height: 11)
                        .offset(x: (geo.size.width - 11) * progress)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 18)
            HStack {
                Text("0:05").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                Text("0:24").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: 520)
    }
}

#endif
