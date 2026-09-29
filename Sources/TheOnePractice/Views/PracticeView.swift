import SwiftUI

struct PracticeView: View {
    let model: PracticeModel

    var body: some View {
        GeometryReader { window in
            VStack(spacing: 0) {
                header
                Divider()
                controls
                Divider()
                songSection
                keyboard(height: keyboardHeight(inWindowOf: window.size.height))
            }
        }
        .background(.background)
    }

    // MARK: - Header

    /// The song title and what the app is up to, with any problem alongside —
    /// or underneath, when there isn't room beside it.
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                titleBlock
                Spacer(minLength: 12)
                errorBlock
            }
            VStack(alignment: .leading, spacing: 6) {
                titleBlock
                errorBlock
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(model.selectedSong?.title ?? "TheONE Light Practice")
                .font(.title2.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            Text(model.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private var errorBlock: some View {
        if let error = model.lastError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .lineLimit(3)
                .frame(maxWidth: 320, alignment: .leading)
                .help(error)
        }
    }

    // MARK: - Controls

    /// The settings wrap onto as many rows as they need; Start and Restart never
    /// wrap and never shrink, so they stay where your hand expects them.
    private var controls: some View {
        HStack(alignment: .center, spacing: 14) {
            FlowLayout(spacing: 14, rowSpacing: 8) {
                modePicker
                handPicker
                if model.mode == .listen {
                    speedControl
                    soundToggle
                } else {
                    chordToggle
                }
                fitToggle
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            transport
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var modePicker: some View {
        Picker("Mode", selection: Binding(
            get: { model.mode },
            set: { model.mode = $0; model.stop() }
        )) {
            ForEach(PracticeModel.Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .fixedSize()
        .help("Practice waits for you to play each note. Listen plays the song.")
    }

    private var handPicker: some View {
        Picker("Hands", selection: Binding(
            get: { model.handFilter },
            set: { model.handFilter = $0; model.reloadLesson() }
        )) {
            ForEach(Lesson.HandFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .fixedSize()
        .help("Practise one hand at a time, which is how a two-hand piece is learned")
    }

    private var speedControl: some View {
        HStack(spacing: 6) {
            Text("Speed").font(.caption)
            Slider(value: Binding(
                get: { model.tempoScale },
                set: { model.tempoScale = $0 }
            ), in: 0.25...1.5)
            .frame(width: 110)
            Text("\(model.tempoScale, specifier: "%.2f")×")
                .font(.caption.monospacedDigit())
                .frame(width: 42, alignment: .leading)
        }
        .help("Slow a tricky passage right down to hear how it goes")
    }

    private var soundToggle: some View {
        Toggle("Sound", isOn: Binding(
            get: { model.soundNotes },
            set: { model.soundNotes = $0 }
        ))
        .fixedSize()
        .help("Also sound the notes. The lamp protocol is silent by design.")
    }

    private var chordToggle: some View {
        Toggle("Hold chords together", isOn: Binding(
            get: { model.requireSimultaneous },
            set: { model.requireSimultaneous = $0; model.reloadLesson() }
        ))
        .fixedSize()
        .help("Require every note of a chord to be down at once. The whole "
              + "chord stays lit until you have them all.")
    }

    private var fitToggle: some View {
        Toggle("Fit to keyboard", isOn: Binding(
            get: { model.fitToKeyboard },
            set: { model.fitToKeyboard = $0; model.reloadLesson() }
        ))
        .fixedSize()
        .help("Octave-shift notes outside the 61 keys instead of dropping them. "
              + "Most piano MIDI is written for 88 keys.")
    }

    private var transport: some View {
        HStack(spacing: 8) {
            Button(model.isRunning ? "Stop" : "Start") {
                model.isRunning ? model.stop() : model.start()
            }
            // Keep the width steady, or everything beside it shuffles on every
            // press.
            .frame(minWidth: 54)
            .keyboardShortcut(.space, modifiers: [])
            .buttonStyle(.borderedProminent)
            .disabled(model.lesson == nil)

            Button("Restart", systemImage: "arrow.counterclockwise") { model.restart() }
                .disabled(model.lesson == nil)
                .labelStyle(.iconOnly)
                .help("Start again from the beginning")
        }
        .fixedSize()
    }

    // MARK: - Now playing

    /// Centred when there's room, scrolling when there isn't — rather than
    /// squashing the note you're meant to be reading.
    private var songSection: some View {
        GeometryReader { area in
            ScrollView(.vertical) {
                VStack(spacing: 0) {
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
                }
                .frame(maxWidth: .infinity, minHeight: area.size.height)
                .padding(.horizontal, 16)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

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
                        // A four-note chord in a narrow window shrinks rather than
                        // wrapping or being cut off.
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: model.upcomingLabel)
                }
            }

            VStack(spacing: 8) {
                timeline(session)
                FlowLayout(spacing: 18, rowSpacing: 8, alignment: .top) {
                    stat("Step", session.positionLabel)
                    stat("Played", "\(session.stepsCompleted)")
                    stat("Mistakes", "\(session.mistakes)")
                    stat("Accuracy", "\(Int((session.accuracy * 100).rounded()))%")
                }
                .frame(maxWidth: 520)
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
                .frame(maxWidth: 520)
                .multilineTextAlignment(.center)
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
                Spacer(minLength: 8)
                if model.scrubTarget != nil {
                    Text("Release to jump here")
                        .font(.caption2)
                        .foregroundStyle(.tint)
                        .lineLimit(1)
                } else if !model.isRunning, session.index > 0 {
                    Text(model.mode == .listen
                         ? "Playing from step \(session.index + 1)"
                         : "Practising from step \(session.index + 1)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
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

    /// The keyboard gives up height first when the window is short, but never so
    /// much that you can't tell the keys apart.
    private func keyboardHeight(inWindowOf height: CGFloat) -> CGFloat {
        min(max(height * 0.18, 56), 118)
    }

    private func keyboard(height: CGFloat) -> some View {
        VStack(spacing: 8) {
            PianoKeyboardView(
                range: TheOneProtocol.keyRange,
                lit: model.highlightedKeys,
                pressed: model.pressedKeys,
                wrongKey: model.lastWrongKey
            )
            .frame(height: height)
            KeyboardLegend()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
}
