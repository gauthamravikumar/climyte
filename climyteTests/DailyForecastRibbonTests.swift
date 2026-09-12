//
//  DailyForecastRibbonTests.swift
//  climyteTests
//

import XCTest
@testable import climyte

/// The week's ribbon has an x for each day plus one at each margin, and a high
/// and a low at every one of those. When the counts disagree the drawing
/// indexes past the end — a crash at launch, not a bad chart.
final class DailyForecastRibbonTests: XCTestCase {

    /// A forecast whose days have all passed keeps only its last one, so a
    /// cache a week old is enough to get here. The app crashed on every launch.
    func testASingleDayHasAHighAndLowAtEveryX() {
        let outline = DailyForecastView.outline(highs: [20], lows: [40], at: [150],
                                                width: 300, chartHeight: 68)

        XCTAssertEqual(outline.xs, [0, 150, 300])
        XCTAssertEqual(outline.highs.count, outline.xs.count)
        XCTAssertEqual(outline.lows.count, outline.xs.count)
    }

    func testNoDaysDrawsNothing() {
        let outline = DailyForecastView.outline(highs: [], lows: [], at: [],
                                                width: 300, chartHeight: 68)

        XCTAssertTrue(outline.xs.isEmpty)
        XCTAssertTrue(outline.highs.isEmpty)
        XCTAssertTrue(outline.lows.isEmpty)
    }

    func testAWeekReachesBothMargins() {
        let vertices: [CGFloat] = [20, 60, 100, 140, 180, 220, 260]
        let outline = DailyForecastView.outline(highs: [30, 25, 20, 22, 28, 30, 26],
                                                lows: [45, 40, 38, 40, 44, 46, 42],
                                                at: vertices, width: 280, chartHeight: 68)

        XCTAssertEqual(outline.xs, [0] + vertices + [280])
        XCTAssertEqual(outline.highs.count, outline.xs.count)
        XCTAssertEqual(outline.lows.count, outline.xs.count)
    }
}
