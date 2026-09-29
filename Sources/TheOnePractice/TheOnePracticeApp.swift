import SwiftUI

/// TheONE Light Practice — a practice companion for THE ONE Light keyboard.
///
/// Drives the instrument's key lights over the protocol in
/// ``TheOneProtocol`` so that any MIDI file can be learned, rather than only the
/// songs in the vendor app's closed library.
///
/// The same code runs on the Mac, on iPad and on iPhone: the keyboard speaks
/// ordinary USB MIDI, which CoreMIDI gives us on all three.
@main
struct TheOnePracticeApp: App {
    init() {
        #if os(macOS)
        // Used to make the pictures in the README.
        if Screenshots.runIfRequested() { exit(0) }
        if Screenshots.playIfRequested() { exit(0) }
        #endif
    }

    var body: some Scene {
        WindowGroup("TheONE Light Practice") {
            ContentView()
        }
        #if os(macOS)
        .defaultSize(width: 1020, height: 680)
        #endif
        .commands {
            CommandGroup(replacing: .newItem) {}   // nothing to create from scratch
        }
    }
}
