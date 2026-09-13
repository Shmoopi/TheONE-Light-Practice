import SwiftUI

/// A progress bar you can drag, like the one in a video player.
///
/// Click anywhere to jump there. While you're dragging, the handle follows your
/// mouse rather than the song, and nothing actually moves until you let go. Arrow
/// keys work too.
struct SeekSlider: View {
    /// Playback position, 0...1.
    var progress: Double
    /// Called as you drag, to show where you'd end up.
    var onScrub: (Double) -> Void = { _ in }
    /// Called once, when you let go.
    var onSeek: (Double) -> Void

    @State private var dragFraction: Double?
    @State private var isHovering = false

    private var displayed: Double { dragFraction ?? progress }
    private var isDragging: Bool { dragFraction != nil }

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let trackHeight: CGFloat = isDragging || isHovering ? 8 : 5
            let knob: CGFloat = isDragging ? 16 : (isHovering ? 14 : 11)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                    .frame(height: trackHeight)

                Capsule()
                    .fill(.tint)
                    .frame(width: width * clamp(displayed), height: trackHeight)

                Circle()
                    .fill(.white)
                    .shadow(radius: isDragging ? 3 : 1, y: 0.5)
                    .frame(width: knob, height: knob)
                    // Keep the handle inside the bar at both ends.
                    .offset(x: (width - knob) * clamp(displayed))
            }
            .frame(height: 18)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.12), value: isHovering)
            .animation(.easeOut(duration: 0.12), value: isDragging)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let fraction = clamp(value.location.x / width)
                        dragFraction = fraction
                        onScrub(fraction)
                    }
                    .onEnded { value in
                        let fraction = clamp(value.location.x / width)
                        dragFraction = nil
                        onSeek(fraction)
                    }
            )
            .onHover { isHovering = $0 }
        }
        .frame(height: 18)
        .accessibilityElement()
        .accessibilityLabel("Song position")
        .accessibilityValue("\(Int((displayed * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            let step = 0.02
            switch direction {
            case .increment: onSeek(clamp(progress + step))
            case .decrement: onSeek(clamp(progress - step))
            @unknown default: break
            }
        }
    }

    private func clamp(_ value: Double) -> Double { min(max(value, 0), 1) }
}

/// A time like 1:23. The digits are evenly spaced so they don't jiggle.
struct TimeLabel: View {
    let seconds: Double

    var body: some View {
        Text(formatted)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
    }

    private var formatted: String {
        let total = max(Int(seconds.rounded()), 0)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
