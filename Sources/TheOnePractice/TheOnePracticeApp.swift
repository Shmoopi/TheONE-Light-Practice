import SwiftUI

/// TheONE Light Practice — a practice companion for THE ONE Light keyboard.
///
/// Drives the instrument's key lights over the protocol in
/// ``TheOneProtocol`` so that any MIDI file can be learned, rather than only the
/// songs in the vendor app's closed library.
@main
struct TheOnePracticeApp: App {
    init() {
        // Used to make the pictures in the README.
        if Screenshots.runIfRequested() { exit(0) }
    }

    var body: some Scene {
        WindowGroup("TheONE Light Practice") {
            ContentView()
        }
        .defaultSize(width: 1020, height: 680)
        .commands {
            CommandGroup(replacing: .newItem) {}   // nothing to create from scratch
        }
    }
}
