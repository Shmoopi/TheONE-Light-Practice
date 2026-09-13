# How the app talks to the keyboard

Only interesting if you're curious or want to build something similar. You don't
need any of this to use the app.

THE ONE Light connects over USB and appears as an ordinary MIDI keyboard. Playing
its keys sends normal MIDI notes. Lighting them up does not — that uses messages
specific to this make of keyboard, which aren't written down anywhere public.

They were worked out by watching what the official app sends over the USB
connection, then checking each guess against a real keyboard.

## Turning a light on

```
A2  <light>  <state>

state 0  off
state 1  on
```

The keyboard also accepts states 2 and 3, but on this model they look identical to
state 1 — the lights are a single colour and can't be dimmed.

The message type is Poly Key Aftertouch, chosen (presumably) because a keyboard
without pressure-sensitive keys never sends it, so it's free to mean something
else. Usefully, it makes no sound.

## Light numbers aren't note numbers

```
light = note − 21
```

The keyboard numbers its lights from the bottom key of a full-size 88-key piano,
even though it only has 61 keys. Middle C is note 60, so it's light 39.

This is the easiest thing to get wrong, because getting it wrong still works —
keys light up, just the wrong ones, and the whole song sounds shifted.

## The greeting

The keyboard ignores light messages until it's been greeted. Send these once when
you connect, about 15 milliseconds apart:

```
F0 00 20 2B 69 00 00 55 79 F7
F0 00 20 2B 69 41 01 00 F7
F0 00 20 2B 69 01 00 00 F7
F0 00 20 2B 69 09 01 6E F7
F0 00 20 2B 69 06 00 02 00 F7
F0 00 20 2B 69 06 00 00 01 F7
F0 00 20 2B 69 06 00 01 00 F7
F0 00 20 2B 69 06 01 02 79 00 00 F7
F0 00 20 2B 69 06 01 00 79 00 00 F7
F0 00 20 2B 69 06 01 01 79 00 00 F7
```

Skip it and the keyboard accepts every light message and does nothing at all,
which is indistinguishable from getting the messages wrong.

We don't know what the individual lines mean. They're copied exactly from the
official app, and together they work.

## Other things worth knowing

**The keyboard never answers.** It doesn't confirm anything or report errors. The
only thing it sends unprompted is a steady stream of timing messages, plus the
notes you play.

**It may be playing when you plug it in.** If it's running a demo it streams notes
out continuously, which is confusing if you're watching the connection. An "all
notes off" message stops it.

**One program at a time.** If the official app is connected, it will be driving the
lights and fighting anything else that tries.

## Other models

All of this was worked out on a **THE ONE Light**. Other keyboards in the range
have different lights — some have colour — and may well differ. The light numbering
starting from a full-size piano suggests the same scheme is used across the range,
but that's a guess, not something tested.
