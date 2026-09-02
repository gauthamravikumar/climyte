//
//  FetchDecision.swift
//  climyte
//

import Foundation

/// Whether a widget timeline pass should fetch, defer, or do neither.
///
/// Extracted from the provider so the loop-prevention rule can be tested. Its
/// failure mode is silence: get it wrong in one direction and the widget goes
/// blank on every reconfiguration, get it wrong in the other and it quietly
/// stops refreshing for good.
nonisolated enum FetchDecision: Equatable {
    /// The reading is recent enough; hand it back and fetch nothing.
    case useCache

    /// Hand back the cached reading now and come straight back for the fetch.
    /// Chosen when a fetch is due but blocking would leave a blank widget.
    case deferFetch

    /// Fetch before returning. Either there is nothing to show anyway, or a
    /// previous pass already deferred and this is the one that pays for it.
    case fetchNow

    /// - Parameters:
    ///   - hasReading: whether a cached reading exists for this city.
    ///   - age: how old that reading is.
    ///   - lastDeferral: when a pass last chose `deferFetch`, if ever.
    ///   - window: how long a deferral stays in force.
    static func decide(hasReading: Bool,
                       age: TimeInterval?,
                       lastDeferral: Date?,
                       now: Date = Date(),
                       window: TimeInterval = 120) -> FetchDecision {
        guard hasReading else { return .fetchNow }
        guard ReadingAge.needsRefetch(age) else { return .useCache }

        // A deferral still in force means this is the follow-up pass, and the
        // follow-up is the one that fetches. Letting it defer again is how a
        // widget stops refreshing without anyone noticing.
        if let lastDeferral, now.timeIntervalSince(lastDeferral) < window {
            return .fetchNow
        }
        return .deferFetch
    }
}
