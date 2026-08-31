//
//  SafeRounding.swift
//  climyte
//

import Foundation

nonisolated extension Double {

    /// Converts to `Int` without trapping.
    ///
    /// `Int(someDouble)` is not a conversion, it is an assertion: infinity,
    /// NaN, or any magnitude past `Int.max` terminates the process. Every
    /// number the app rounds for display arrives from a weather API, and a
    /// remote service sending something absurd should produce an absurd
    /// reading on screen, not take the app down with it.
    ///
    /// Out-of-range values saturate; NaN — which has no nearest integer —
    /// becomes zero, because there is nothing better and it cannot crash.
    func toInt(_ rule: FloatingPointRoundingRule = .toNearestOrAwayFromZero) -> Int {
        guard !isNaN else { return 0 }

        let value = rounded(rule)
        if value >= Double(Int.max) { return .max }
        if value <= Double(Int.min) { return .min }
        return Int(value)
    }
}
