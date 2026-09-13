#!/usr/bin/env python3
"""Generate easy public-domain practice songs as MIDI files.

Written for testing the key lights on a real instrument, so each song is chosen
to make a lamp problem obvious rather than to be musically interesting:

* **Stepwise and diatonic**, so a wrong key number is visible as a gap in an
  otherwise smooth run of lit keys.
* **Two named tracks** ("Right Hand" / "Left Hand"), which gives the compiler its
  authoritative hand signal instead of the pitch-split fallback — and makes the
  two lamp states appear side by side.
* **Comfortably inside 36-96**, so nothing is dropped on a 61-key keyboard.

All three melodies are long out of copyright: Beethoven's Ode to Joy (1824), and
the traditional Twinkle Twinkle and Frère Jacques.

    python tools/make-easy-song.py                 # write all of them
    python tools/make-easy-song.py ode-to-joy      # just one
"""

from __future__ import annotations

import sys
from pathlib import Path

import mido

TICKS = 480
OUT_DIR = Path("samples")

# Note names for readability. Middle C = C4 = 60.
C3, D3, E3, F3, G3, A3, B3 = 48, 50, 52, 53, 55, 57, 59
C4, D4, E4, F4, G4, A4, B4 = 60, 62, 64, 65, 67, 69, 71
C5 = 72
G2, A2, B2 = 43, 45, 47

#: (melody, bass, tempo_bpm, description)
#: Melody and bass are lists of (note, beats). None = rest.
SONGS: dict[str, dict] = {
    "ode-to-joy": {
        "bpm": 80,
        "description": "Beethoven, Ode to Joy — entirely stepwise, ideal for spotting a wrong key",
        "melody": [
            (E4, 1), (E4, 1), (F4, 1), (G4, 1),
            (G4, 1), (F4, 1), (E4, 1), (D4, 1),
            (C4, 1), (C4, 1), (D4, 1), (E4, 1),
            (E4, 1.5), (D4, 0.5), (D4, 2),
            (E4, 1), (E4, 1), (F4, 1), (G4, 1),
            (G4, 1), (F4, 1), (E4, 1), (D4, 1),
            (C4, 1), (C4, 1), (D4, 1), (E4, 1),
            (D4, 1.5), (C4, 0.5), (C4, 2),
        ],
        "bass": [
            (C3, 4), (G2, 4), (C3, 4), (G2, 4),
            (C3, 4), (G2, 4), (C3, 4), (C3, 4),
        ],
    },
    "twinkle": {
        "bpm": 90,
        "description": "Twinkle Twinkle Little Star — wide leaps, checks octave handling",
        "melody": [
            (C4, 1), (C4, 1), (G4, 1), (G4, 1),
            (A4, 1), (A4, 1), (G4, 2),
            (F4, 1), (F4, 1), (E4, 1), (E4, 1),
            (D4, 1), (D4, 1), (C4, 2),
        ],
        "bass": [
            (C3, 4), (C3, 4), (F3, 2), (C3, 2),
            (F3, 2), (C3, 2), (G2, 2), (C3, 2),
        ],
    },
    "frere-jacques": {
        "bpm": 100,
        "description": "Frère Jacques — short, repetitive, good for a quick smoke test",
        "melody": [
            (C4, 1), (D4, 1), (E4, 1), (C4, 1),
            (C4, 1), (D4, 1), (E4, 1), (C4, 1),
            (E4, 1), (F4, 1), (G4, 2),
            (E4, 1), (F4, 1), (G4, 2),
        ],
        "bass": [
            (C3, 4), (C3, 4), (C3, 4), (C3, 4),
        ],
    },
}


def build_track(name: str, events, bpm: int | None = None) -> mido.MidiTrack:
    """Turn (note, beats) pairs into a named MIDI track."""
    track = mido.MidiTrack()
    track.append(mido.MetaMessage("track_name", name=name, time=0))
    if bpm is not None:
        track.append(mido.MetaMessage("set_tempo", tempo=mido.bpm2tempo(bpm), time=0))

    for note, beats in events:
        ticks = int(round(beats * TICKS))
        if note is None:  # rest: carry the time onto the next note-on
            track.append(mido.Message("note_on", note=0, velocity=0, time=ticks))
            continue
        # A short gap between notes so repeated pitches retrigger visibly.
        gap = min(20, max(1, ticks // 12))
        track.append(mido.Message("note_on", note=note, velocity=90, time=0))
        track.append(mido.Message("note_off", note=note, velocity=0, time=ticks - gap))
        track.append(mido.Message("note_on", note=note, velocity=0, time=gap))
    return track


def write_song(key: str) -> Path:
    spec = SONGS[key]
    midi = mido.MidiFile(ticks_per_beat=TICKS)
    midi.tracks.append(build_track("Right Hand", spec["melody"], bpm=spec["bpm"]))
    midi.tracks.append(build_track("Left Hand", spec["bass"]))

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    path = OUT_DIR / f"{key}.mid"
    midi.save(str(path))
    return path


def main() -> int:
    wanted = sys.argv[1:] or list(SONGS)
    unknown = [w for w in wanted if w not in SONGS]
    if unknown:
        print(f"unknown song(s): {', '.join(unknown)}", file=sys.stderr)
        print(f"available: {', '.join(SONGS)}", file=sys.stderr)
        return 1

    for key in wanted:
        path = write_song(key)
        spec = SONGS[key]
        beats = sum(b for _, b in spec["melody"])
        print(f"{path}")
        print(f"  {spec['description']}")
        print(f"  {spec['bpm']} bpm, {beats:g} beats ≈ {beats * 60 / spec['bpm']:.0f}s")
    print("\nplay it:")
    print(f'  python -m theone song play {OUT_DIR / (wanted[0] + ".mid")} \\')
    print('      --port "THE ONE" --codec theone-light --tempo 0.6 --look-ahead 0.4')
    return 0


if __name__ == "__main__":
    sys.exit(main())
