import SwiftUI

/// Lays views out in a row, starting a new row when one runs out of width.
///
/// SwiftUI has no wrapping stack of its own, and an `HStack` doesn't wrap — it
/// squeezes, so in a narrow window a row of controls ends up crushed together with
/// its labels clipped. Anything that should stay whole, like a slider and its
/// caption, goes in as one item.
struct FlowLayout: Layout {
    /// Space between items on the same row.
    var spacing: CGFloat = 12
    /// Space between rows.
    var rowSpacing: CGFloat = 8
    /// How items shorter than the tallest one in their row line up against it.
    var alignment: VerticalAlignment = .center

    func sizeThatFits(
        proposal: ProposedViewSize, subviews: Subviews, cache: inout Void
    ) -> CGSize {
        let limit = proposal.width ?? .infinity
        let rows = rows(of: subviews, within: limit)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +)
            + rowSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: min(width, limit), height: height)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void
    ) {
        var y = bounds.minY
        for row in rows(of: subviews, within: bounds.width) {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y + offset(of: item.size.height, inRowOf: row.height)),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }
            y += row.height + rowSpacing
        }
    }

    private func offset(of height: CGFloat, inRowOf rowHeight: CGFloat) -> CGFloat {
        if alignment == .top { return 0 }
        if alignment == .bottom { return rowHeight - height }
        return (rowHeight - height) / 2
    }

    // MARK: - Working out the rows

    private struct Item {
        let index: Int
        let size: CGSize
    }

    private struct Row {
        var items: [Item] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(of subviews: Subviews, within limit: CGFloat) -> [Row] {
        // A width of zero turns up while the layout is still settling; treat it as
        // "no room to speak of" rather than dividing everything by nothing.
        let limit = max(limit, 1)
        var rows: [Row] = []
        var row = Row()

        for index in subviews.indices {
            var size = subviews[index].sizeThatFits(.unspecified)
            // Something wider than the whole row still has to go somewhere.
            size.width = min(size.width, limit)

            if !row.items.isEmpty, row.width + spacing + size.width > limit {
                rows.append(row)
                row = Row()
            }
            row.width = row.items.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.items.append(Item(index: index, size: size))
        }

        if !row.items.isEmpty { rows.append(row) }
        return rows
    }
}
