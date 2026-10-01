//
//  WeekRibbon.swift
//  climyte
//

import CoreGraphics

/// The week's band between its highs and lows, as points to draw.
///
/// Kept apart from the 7-day chart so a Week widget, if one comes back (see
/// LATER.md), would draw the same shape. Only the geometry lives here.
nonisolated enum WeekRibbon {

    /// The band reaches both margins like every other full-width element on
    /// the page, while its vertices stay above the days they belong to. The
    /// half-column at each end continues the slope of the segment beside it
    /// — the week does not stop at Monday, and a flat shoulder would say it
    /// did.
    static func outline(highs: [CGFloat], lows: [CGFloat], at vertices: [CGFloat],
                        width: CGFloat, chartHeight: CGFloat)
        -> (xs: [CGFloat], highs: [CGFloat], lows: [CGFloat]) {
        // Every x needs a high and a low, or the drawing indexes past the end
        // and the app dies at launch. No days is nothing to draw.
        guard !vertices.isEmpty, highs.count == vertices.count, lows.count == vertices.count else {
            return (xs: [], highs: [], lows: [])
        }

        // One day has no slope to continue, so it runs flat to both margins.
        // A forecast whose days have all passed is left with just this.
        guard vertices.count > 1 else {
            return (xs: [0] + vertices + [width],
                    highs: Array(repeating: highs[0], count: 3),
                    lows: Array(repeating: lows[0], count: 3))
        }

        return (xs: [0] + vertices + [width],
                highs: extendedToEdges(highs, at: vertices, width: width, chartHeight: chartHeight),
                lows: extendedToEdges(lows, at: vertices, width: width, chartHeight: chartHeight))
    }

    /// Continues the first and last segments out to the frame's edges.
    /// Clamped to the drawable band, so a steep end cannot push the shape out
    /// of its own frame and into the rule above it.
    private static func extendedToEdges(_ ys: [CGFloat], at xs: [CGFloat],
                                        width: CGFloat, chartHeight: CGFloat) -> [CGFloat] {
        guard ys.count >= 2, xs.count == ys.count else { return ys }

        let inset: CGFloat = 3
        func clamped(_ y: CGFloat) -> CGFloat {
            min(max(y, inset), chartHeight - inset)
        }

        let leadSlope = (ys[1] - ys[0]) / max(xs[1] - xs[0], 1)
        let tailSlope = (ys[ys.count - 1] - ys[ys.count - 2]) / max(xs[xs.count - 1] - xs[xs.count - 2], 1)

        return [clamped(ys[0] - leadSlope * xs[0])]
            + ys
            + [clamped(ys[ys.count - 1] + tailSlope * (width - xs[xs.count - 1]))]
    }
}
