import SwiftUI

/// The keyboard on screen.
///
/// Your real keyboard can only light a key up or leave it dark. This one uses
/// colour to show *why* a key is lit: the note to play, one you got right, a wrong
/// note, or a key you're holding.
struct PianoKeyboardView: View {
    let range: ClosedRange<Int>
    let lit: Set<Int>
    let pressed: Set<Int>
    let wrongKey: Int?

    /// The white keys set the spacing; black keys sit on top, between them.
    private var whiteKeys: [Int] { range.filter { !NoteName.isBlackKey($0) } }

    var body: some View {
        GeometryReader { geo in
            let whiteWidth = geo.size.width / CGFloat(max(whiteKeys.count, 1))
            let blackWidth = whiteWidth * 0.56
            let blackHeight = geo.size.height * 0.62

            ZStack(alignment: .topLeading) {
                HStack(spacing: 1) {
                    ForEach(whiteKeys, id: \.self) { note in
                        key(note, isBlack: false)
                            .frame(width: whiteWidth - 1)
                    }
                }

                ForEach(range.filter { NoteName.isBlackKey($0) }, id: \.self) { note in
                    // Put each black key between the two white keys it belongs to.
                    let whitesBelow = whiteKeys.filter { $0 < note }.count
                    let x = CGFloat(whitesBelow) * whiteWidth - blackWidth / 2
                    key(note, isBlack: true)
                        .frame(width: blackWidth, height: blackHeight)
                        .offset(x: x)
                }
            }
            .background(Color(white: 0.82))
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary, lineWidth: 1))
    }

    @ViewBuilder
    private func key(_ note: Int, isBlack: Bool) -> some View {
        let isWrong = wrongKey == note
        let isLit = lit.contains(note)
        let isPressed = pressed.contains(note)
        let shape = UnevenRoundedRectangle(
            bottomLeadingRadius: isBlack ? 2 : 3, bottomTrailingRadius: isBlack ? 2 : 3
        )

        shape
            .fill(fill(isBlack: isBlack, isLit: isLit, isPressed: isPressed, isWrong: isWrong))
            // Outline them, or white keys vanish against a light background.
            .overlay(shape.stroke(Color(white: isBlack ? 0.15 : 0.72), lineWidth: 0.75))
            .overlay(alignment: .bottom) {
                if note % 12 == 0, !isBlack {
                    Text(NoteName.of(note))
                        .font(.system(size: 8))
                        .foregroundStyle(Color(white: 0.45))
                        .padding(.bottom, 2)
                }
            }
    }

    private func fill(
        isBlack: Bool, isLit: Bool, isPressed: Bool, isWrong: Bool
    ) -> AnyShapeStyle {
        if isWrong { return AnyShapeStyle(.red) }
        if isLit && isPressed { return AnyShapeStyle(.green) }
        if isLit { return AnyShapeStyle(.orange) }
        if isPressed { return AnyShapeStyle(Color.blue.opacity(0.6)) }
        return isBlack
            ? AnyShapeStyle(Color(white: 0.13))
            : AnyShapeStyle(Color.white)
    }
}

/// What the colours mean.
struct KeyboardLegend: View {
    var body: some View {
        HStack(spacing: 14) {
            item(.orange, "Play this")
            item(.green, "Correct")
            item(.red, "Wrong note")
            item(.blue.opacity(0.55), "You're holding")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func item(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(label)
        }
    }
}
