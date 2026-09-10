//
//  RainOutlook.swift
//  climyte
//

import Foundation

/// Rain at one city over the next two hours, in quarter-hour steps.
///
/// One point rather than a grid, on purpose. A map of the surrounding region
/// needs a hundred-odd coordinates, and the API bills a multi-point request by
/// its locations — which put a rain map past the free tier's per-minute budget.
/// This rides along with the forecast request already made for the city, so it
/// costs nothing at all.
///
/// What it cannot do, in exchange: rain passing twenty kilometres north is
/// invisible here. It knows what happens over the city and nothing else.
nonisolated struct RainOutlook: Equatable {

    nonisolated struct Step: Equatable {
        let time: Date

        /// Millimetres falling in this quarter hour.
        let millimetres: Double
    }

    let steps: [Step]

    /// Below this a step is not worth drawing. A tenth of a millimetre in
    /// fifteen minutes is the line between damp air and rain.
    static let wetThreshold: Double = 0.1

    /// How far ahead to look. Two hours: long enough to answer "do I need to
    /// leave now", short enough that the model is still worth believing.
    static let stepCount = 8

    var isDry: Bool {
        !steps.contains { $0.millimetres >= Self.wetThreshold }
    }

    /// Everything expected to fall across the window.
    var total: Double {
        steps.reduce(0) { $0 + $1.millimetres }
    }

    /// When it starts, or nil if it never does.
    var arrival: Step? {
        steps.first { $0.millimetres >= Self.wetThreshold }
    }

    /// The heaviest quarter-hour.
    var peak: Step? {
        steps.max { $0.millimetres < $1.millimetres }
    }

    /// The peak as a rate, which is the number people recognise: a quarter of
    /// an hour's fall is four times as much in an hour.
    var peakRatePerHour: Double {
        (peak?.millimetres ?? 0) * 4
    }

    /// What the tallest bar is measured against.
    ///
    /// Scaled to the heaviest step, but never to less than half a millimetre,
    /// so a drizzle draws as a low bar rather than filling the chart and
    /// reading like a downpour. The absolute figures are in the line above; the
    /// bars carry only the shape.
    var scale: Double {
        max(peak?.millimetres ?? 0, 0.5)
    }
}

extension RainOutlook {

    /// Builds the outlook from the forecast response's quarter-hour block.
    ///
    /// Returns nil when the response carries no usable steps — an older cached
    /// response, or a place the model publishes no minutely data for — and the
    /// section then does not appear at all.
    init?(times: [String], precipitation: [Double?], parser: DateFormatter, now: Date) {
        guard !times.isEmpty else { return nil }

        // The request asks for a past day, so the block can begin before now. A
        // quarter-hour that has already passed is not an outlook; keep the one
        // in progress and everything after it.
        let earliest = now.addingTimeInterval(-15 * 60)

        var collected: [Step] = []
        for index in times.indices {
            guard collected.count < Self.stepCount else { break }
            guard let date = parser.date(from: times[index]), date >= earliest else { continue }

            // A null step is the model saying "nothing here", not a hole.
            let millimetres: Double = precipitation.value(at: index) ?? 0
            collected.append(Step(time: date, millimetres: max(millimetres, 0)))
        }

        guard !collected.isEmpty else { return nil }
        self.steps = collected
    }
}
