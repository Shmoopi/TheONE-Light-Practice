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

    python3 Scripts/make-easy-song.py                 # write all of them
    python3 Scripts/make-easy-song.py ode-to-joy      # just one

Nothing outside the standard library is needed — the tests run this to produce
their fixtures, so it has to work on a bare machine.
"""

from __future__ import annotations

import sys
from pathlib import Path

TICKS = 480
OUT_DIR = Path(__file__).resolve().parent.parent / "Samples"

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


def variable_length(value: int) -> bytes:
    """A delta time, in the packed form MIDI files store times in."""
    if value < 0:
        raise ValueError(f"delta times cannot be negative: {value}")
    out = bytearray([value & 0x7F])
    value >>= 7
    while value:
        out.append((value & 0x7F) | 0x80)
        value >>= 7
    out.reverse()
    return bytes(out)


def build_track(name: str, events, bpm: int | None = None) -> bytes:
    """Turn (note, beats) pairs into a named MIDI track chunk."""
    title = name.encode("utf-8")
    body = bytearray()
    body += variable_length(0) + b"\xff\x03" + variable_length(len(title)) + title
    if bpm is not None:
        microseconds_per_beat = round(60_000_000 / bpm)
        body += variable_length(0) + b"\xff\x51\x03"
        body += microseconds_per_beat.to_bytes(3, "big")

    for note, beats in events:
        ticks = int(round(beats * TICKS))
        if note is None:  # rest: carry the time onto the next note-on
            body += variable_length(ticks) + bytes([0x90, 0, 0])
            continue
        # A short gap between notes so repeated pitches retrigger visibly.
        gap = min(20, max(1, ticks // 12))
        body += variable_length(0) + bytes([0x90, note, 90])
        body += variable_length(ticks - gap) + bytes([0x80, note, 0])
        body += variable_length(gap) + bytes([0x90, note, 0])

    body += variable_length(0) + b"\xff\x2f\x00"   # end of track
    return b"MTrk" + len(body).to_bytes(4, "big") + bytes(body)


def write_song(key: str) -> Path:
    spec = SONGS[key]
    tracks = [
        build_track("Right Hand", spec["melody"], bpm=spec["bpm"]),
        build_track("Left Hand", spec["bass"]),
    ]
    # Format 1: several tracks played together, on one timeline.
    header = b"MThd" + (6).to_bytes(4, "big")
    header += (1).to_bytes(2, "big")
    header += len(tracks).to_bytes(2, "big")
    header += TICKS.to_bytes(2, "big")

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    path = OUT_DIR / f"{key}.mid"
    path.write_bytes(header + b"".join(tracks))
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
    print("\nOpen the app, drag one onto the song list, and press Start.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
