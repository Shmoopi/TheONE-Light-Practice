import Foundation

/// Runs one job at a time, and never lets a stopped job outlive its replacement.
///
/// Playing a song back is a long job that tidies up after itself: as it ends it
/// turns off whatever notes and lamps it left on. Cancelling it is not instant —
/// it has to wake from whatever it was waiting on before it can unwind — so
/// starting the next job straight away leaves the two overlapping, and the old
/// one's tidying turns off the new one's lights and silences its notes.
///
/// Seeking during playback does exactly that, once per drag. So: cancel, wait for
/// the old job to finish unwinding, *then* start the new one.
@MainActor
final class PlaybackRunner {
    private var job: Task<Void, Never>?
    /// Tells a finished job whether it is still the one in charge.
    private var token = 0

    /// Stop whatever is running and start this instead, once the old job has
    /// finished unwinding.
    func replace(with body: @escaping @MainActor () async -> Void) {
        token &+= 1
        let mine = token
        let previous = job
        previous?.cancel()
        job = Task { @MainActor [weak self] in
            await previous?.value
            // Replaced again while waiting our turn — the newer job has the floor.
            guard !Task.isCancelled else { return }
            await body()
            if let self, self.token == mine { self.job = nil }
        }
    }

    /// Stop what is running. It still unwinds in its own time, and whatever starts
    /// next waits for it.
    func cancel() {
        token &+= 1
        job?.cancel()
    }

    /// Wait until nothing is running or unwinding.
    func settle() async {
        await job?.value
    }
}
