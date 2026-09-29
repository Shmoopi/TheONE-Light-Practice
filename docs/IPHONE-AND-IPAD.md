# Running it on an iPhone or iPad

The app is the same on all three platforms. THE ONE Light speaks ordinary USB
MIDI, and CoreMIDI is on iOS and iPadOS too, so the lights work exactly as they
do on a Mac.

## What you need

- An iPad or iPhone running **iOS 17** or later
- A way to plug the keyboard in:
  - **iPad or iPhone with USB-C** — a USB-C to USB-B cable, or USB-C to USB-A with
    the keyboard's own cable
  - **Lightning iPhone or iPad** — Apple's *Lightning to USB Camera Adapter*. Use
    the version with a power passthrough if the keyboard won't wake up; some
    keyboards draw more than the port gives on its own.
- **Xcode** on a Mac, to build and install it. There's no App Store build.

## Building it

```
open TheOnePractice.xcodeproj
```

Pick the **TheONE Light Practice** scheme and press Run.

To put it on a real device you need a signing team, which is free with any Apple
ID:

1. Select the **TheONE Light Practice** target → **Signing & Capabilities**.
2. Tick **Automatically manage signing** and choose your team.
3. Change the **Bundle Identifier** to something of your own, like
   `com.yourname.lightpractice` — `local.theone.lightpractice` may already be
   taken by someone else's build.

Or from the command line:

```
xcodebuild -project TheOnePractice.xcodeproj \
           -scheme "TheONE Light Practice" \
           -destination 'generic/platform=iOS Simulator' build
```

The project reads its sources straight out of `Sources/TheOnePractice`, the same
folder `swift build` uses for the Mac app — so there's one copy of the code and
nothing to keep in step. Adding a file to that folder adds it to the iOS app too,
with no project file to edit.

## Getting songs onto it

The song library is the app's own folder in the **Files** app, so:

- Open **Files → On My iPhone/iPad → TheONE Light Practice** and drop `.mid`
  files straight in. They appear in the app next time you bring it to the front.
- Or share a MIDI file to the app from Mail, Messages, or a download.
- Or use the **Import** button in the app.

For a few songs to start with, run `python3 Scripts/make-easy-song.py` in this
repository and copy what lands in `Samples/` across.

## Things that differ from the Mac

- **On iPhone**, the song list is a separate screen — tap the back arrow to reach
  it. The keyboard on screen is 61 keys wide either way, so turning the phone
  sideways makes it much easier to read.
- **Leaving the app** turns the keyboard's lights off. It doesn't keep playing in
  the background.
- **Bluetooth MIDI** works if your keyboard is already paired in another app;
  there is no pairing screen here yet. A cable is more reliable anyway.

## If it can't find the keyboard

The same things go wrong here as on a Mac, plus one more: iOS only powers a USB
device through the adapter if the adapter is the powered kind, or the keyboard is
plugged into the mains. If the keyboard's own screen is dark, that's the problem.
