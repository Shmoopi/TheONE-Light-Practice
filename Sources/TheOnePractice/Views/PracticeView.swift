import SwiftUI

struct PracticeView: View {
    let model: PracticeModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            controls
            Divider()

            Spacer(minLength: 12)

            if let session = model.session, !session.lesson.steps.isEmpty {
                nowPlaying(session)
            } else {
                ContentUnavailableView(
                    "No song selected",
                    systemImage: "music.note",
                    description: Text("Import a MIDI file and pick it from the sidebar.")
                )
            }

            Spacer(minLength: 12)

            keyboard
        }
        .background(.background)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.selectedSong?.title ?? "TheONE Light Practice")
                    .font(.title2.weight(.semibold))
                Text(model.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let error = model.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: 320, alignment: .trailing)
                    .help(error)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 16) {
            Picker("Mode", selection: Binding(
                get: { model.mode },
                set: { model.mode = $0; model.stop() }
            )) {
                ForEach(PracticeModel.Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 190)
            .help("Practice waits for you to play each note. Listen plays the song.")

            Picker("Hands", selection: Binding(
                get: { model.handFilter },
                set: { model.handFilter = $0; model.reloadLesson() }
            )) {
                ForEach(Lesson.HandFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .frame(width: 150)
            .help("Practise one hand at a time, which is how a two-hand piece is learned")

            if model.mode == .listen {
                HStack(spacing: 6) {
                    Text("Speed").font(.caption)
                    Slider(value: Binding(
                        get: { model.tempoScale },
                        set: { model.tempoScale = $0 }
                    ), in: 0.25...1.5)
                    .frame(width: 110)
                    Text("\(model.tempoScale, specifier: "%.2f")×")
                        .font(.caption.monospacedDigit())
                        .frame(width: 40, alignment: .leading)
                }
                Toggle("Sound", isOn: Binding(
                    get: { model.soundNotes },
                    set: { model.soundNotes = $0 }
                ))
                .help("Also sound the notes. The lamp protocol is silent by design.")
            } else {
                Toggle("Hold chords together", isOn: Binding(
                    get: { model.requireSimultaneous },
                    set: { model.requireSimultaneous = $0; model.reloadLesson() }
                ))
                .help("Require every note of a chord to be down at once. The whole "
                      + "chord stays lit until you have them all.")
            }

            Toggle("Fit to keyboard", isOn: Binding(
                get: { model.fitToKeyboard },
                set: { model.fitToKeyboard = $0; model.reloadLesson() }
            ))
            .help("Octave-shift notes outside the 61 keys instead of dropping them. "
                  + "Most piano MIDI is written for 88 keys.")

            Spacer()

            Button(model.isRunning ? "Stop" : "Start") {
                model.isRunning ? model.stop() : model.start()
            }
            .keyboardShortcut(.space, modifiers: [])
            .buttonStyle(.borderedProminent)
            .disabled(model.lesson == nil)

            Button("Restart", systemImage: "arrow.counterclockwise") { model.restart() }
                .disabled(model.lesson == nil)
                .labelStyle(.iconOnly)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Now playing

    @ViewBuilder
    private func nowPlaying(_ session: LessonSession) -> some View {
        VStack(spacing: 18) {
            if model.mode == .practice {
                VStack(spacing: 4) {
                    Text(session.isFinished ? "Done" : "Play")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(session.isFinished ? "🎉" : model.upcomingLabel)
                        .font(.system(size: 56, weight: .light, design: .rounded))
                        .contentTransition(.numericText())
                        .animation(.snappy, value: model.upcomingLabel)
                }
            }

            VStack(spacing: 8) {
                timeline(session)
                HStack(spacing: 18) {
                    stat("Step", session.positionLabel)
                    stat("Played", "\(session.stepsCompleted)")
                    stat("Mistakes", "\(session.mistakes)")
                    stat("Accuracy", "\(Int((session.accuracy * 100).rounded()))%")
                }
            }

            if let warning = model.songWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: 520)
                    .multilineTextAlignment(.center)
            }

            if !session.lesson.handSignal.isReliable, model.handFilter != .both {
                Label(
                    "Hands inferred from \(session.lesson.handSignal.rawValue) — the split may be wrong where the hands cross.",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    /// The progress bar. Drag it to move around the song; let go to jump there.
    @ViewBuilder
    private func timeline(_ session: LessonSession) -> some View {
        VStack(spacing: 2) {
            SeekSlider(
                progress: model.timelineProgress,
                onScrub: { model.scrub(toFraction: $0) },
                onSeek: { model.seek(toFraction: $0) }
            )
            HStack {
                TimeLabel(seconds: session.currentTime)
                Spacer()
                if model.scrubTarget != nil {
                    Text("Release to jump here")
                        .font(.caption2)
                        .foregroundStyle(.tint)
                } else if !model.isRunning, session.index > 0 {
                    Text("Practising from step \(session.index + 1)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                TimeLabel(seconds: session.totalTime)
            }
        }
        .frame(maxWidth: 520)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.title3.monospacedDigit().weight(.medium))
            Text(label).font(.caption2).foregroundStyle(.secondary).textCase(.uppercase)
        }
    }

    // MARK: - Keyboard

    private var keyboard: some View {
        VStack(spacing: 8) {
            PianoKeyboardView(
                range: TheOneProtocol.keyRange,
                lit: model.highlightedKeys,
                pressed: model.pressedKeys,
                wrongKey: model.lastWrongKey
            )
            .frame(height: 110)
            KeyboardLegend()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
}
