//
//  WeekColumnsLayout.swift
//  climyte
//

import SwiftUI

/// Lays the week out on a single pitch, with the first day starting on the
/// leading edge and the last ending on the trailing one.
///
/// An equal share of the width per day cannot do both: the last day is placed
/// at the start of its own column and whatever it does not fill is left as
/// dead space on the right. Setting the last day's own width aside first and
/// dividing what remains gives every day the same pitch and lands the row on
/// both margins.
struct WeekColumnsLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 0,
               height: subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        guard let last = sizes.last, subviews.count > 1 else {
            subviews.first?.place(at: CGPoint(x: bounds.minX, y: bounds.minY),
                                  anchor: .topLeading, proposal: .unspecified)
            return
        }

        let pitch = (bounds.width - last.width) / CGFloat(subviews.count - 1)
        for index in subviews.indices {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + pitch * CGFloat(index), y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(sizes[index])
            )
        }
    }
}
