//
//  RainOutlookTests.swift
//  climyteTests
//

import XCTest
@testable import climyte

final class RainOutlookTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_788_960_000)

    // MARK: - Reading the response

    /// The forecast request asks for a past day, so the quarter-hour block can
    /// begin well before now. Showing those would make "the next 2 hours" a lie.
    func testStepsBeforeNowAreDropped() throws {
        let outlook = try XCTUnwrap(make(
            offsets: [-120, -60, -15, 0, 15, 30],
            millimetres: [9, 9, 0.2, 0.3, 0.4, 0]
        ))

        // The quarter hour in progress is kept: it has not finished raining yet.
        XCTAssertEqual(outlook.steps.count, 4)
        XCTAssertEqual(outlook.steps.map(\.millimetres), [0.2, 0.3, 0.4, 0])
    }

    func testNoMoreThanTwoHoursIsKept() throws {
        let outlook = try XCTUnwrap(make(
            offsets: Array(stride(from: 0, through: 180, by: 15)),
            millimetres: Array(repeating: 0.2, count: 13)
        ))

        XCTAssertEqual(outlook.steps.count, RainOutlook.stepCount)
    }

    /// A null step is the model saying "nothing here", not a gap in the data.
    func testNullStepsReadAsDry() throws {
        let outlook = try XCTUnwrap(make(
            offsets: [0, 15, 30], millimetres: [0.4, nil, 0.2]
        ))

        XCTAssertEqual(outlook.steps.map(\.millimetres), [0.4, 0, 0.2])
    }

    /// A negative amount is meaningless and would draw a bar hanging below the
    /// baseline.
    func testNegativeAmountsAreClampedToZero() throws {
        let outlook = try XCTUnwrap(make(offsets: [0, 15], millimetres: [-3, 0.2]))
        XCTAssertEqual(outlook.steps[0].millimetres, 0)
    }

    func testAnEmptyOrEntirelyPastBlockGivesNothing() {
        XCTAssertNil(make(offsets: [], millimetres: []))
        XCTAssertNil(make(offsets: [-180, -120, -60], millimetres: [1, 1, 1]))
    }

    /// An unreadable timestamp must not take the rest of the block with it.
    func testAnUnreadableTimestampSkipsOnlyItsOwnStep() throws {
        let times = ["not a date", string(offset: 15), string(offset: 30)]
        let outlook = try XCTUnwrap(
            RainOutlook(times: times, precipitation: [5, 0.3, 0.4],
                        parser: formatter(), now: now)
        )

        XCTAssertEqual(outlook.steps.map(\.millimetres), [0.3, 0.4])
    }

    // MARK: - What the card says

    func testDryMeansNoStepReachesTheThreshold() throws {
        let damp = try XCTUnwrap(make(offsets: [0, 15], millimetres: [0.05, 0.09]))
        XCTAssertTrue(damp.isDry)

        let wet = try XCTUnwrap(make(offsets: [0, 15], millimetres: [0, 0.1]))
        XCTAssertFalse(wet.isDry)
    }

    func testTotalIsEverythingExpectedToFall() throws {
        let outlook = try XCTUnwrap(make(
            offsets: [0, 15, 30, 45], millimetres: [0.3, 0.5, 0.8, 0.1]
        ))
        XCTAssertEqual(outlook.total, 1.7, accuracy: 0.0001)
    }

    func testArrivalIsTheFirstWetStepNotTheHeaviest() throws {
        let outlook = try XCTUnwrap(make(
            offsets: [0, 15, 30], millimetres: [0, 0.2, 4.0]
        ))

        XCTAssertEqual(outlook.arrival?.millimetres, 0.2)
        XCTAssertEqual(outlook.peak?.millimetres, 4.0)
    }

    /// The rate is the number people recognise, and a quarter hour's fall is
    /// four times as much in an hour. Reporting the bucket as though it were an
    /// hourly rate would understate a downpour fourfold.
    func testPeakRateIsPerHourNotPerQuarter() throws {
        let outlook = try XCTUnwrap(make(offsets: [0, 15], millimetres: [0.5, 1.5]))
        XCTAssertEqual(outlook.peakRatePerHour, 6.0, accuracy: 0.0001)
    }

    /// Scaling purely to the heaviest step would draw a drizzle at full height,
    /// where it reads as a downpour.
    func testDrizzleDoesNotFillTheChart() throws {
        let drizzle = try XCTUnwrap(make(offsets: [0, 15], millimetres: [0.1, 0.2]))
        XCTAssertEqual(drizzle.scale, 0.5, accuracy: 0.0001)

        let downpour = try XCTUnwrap(make(offsets: [0, 15], millimetres: [1, 3]))
        XCTAssertEqual(downpour.scale, 3, accuracy: 0.0001,
                       "past the floor the chart scales to what is actually falling")
    }

    // MARK: - The next 24 hours

    /// London at 2 pm: every drop fell before 5 am. None of it may count.
    func testRainThatHasAlreadyFallenIsLeftOut() throws {
        let rain: [Double?] = [0.4, 0.2, 0, 0.6, 0.1] + Array(repeating: 0.0, count: 19)
        let chance: [Int?] = [62, 71, 76, 76, 69] + Array(repeating: 0, count: 19)
        let ahead = try XCTUnwrap(hours(from: -10, rain: rain, chance: chance))

        XCTAssertEqual(ahead.chance, 0)
        XCTAssertEqual(ahead.amount, 0, accuracy: 0.0001)
        XCTAssertNil(ahead.start)
    }

    /// The hour already under way has not finished raining.
    func testTheHourInProgressCounts() throws {
        let ahead = try XCTUnwrap(hours(from: 0, rain: [2, 0], chance: [90, 0]))

        XCTAssertEqual(ahead.amount, 2, accuracy: 0.0001)
        XCTAssertEqual(ahead.chance, 90)
        XCTAssertEqual(ahead.start, now.addingTimeInterval(-20 * 60), "that hour began before now")
    }

    func testOnlyTwentyFourHoursCount() throws {
        let ahead = try XCTUnwrap(hours(from: 0, rain: Array(repeating: 1, count: 48),
                                        chance: Array(repeating: 50, count: 48)))
        XCTAssertEqual(ahead.amount, 24, accuracy: 0.0001)
    }

    /// The same measure the day's figure used — its peak hour — so the 20%
    /// threshold keeps its meaning.
    func testTheChanceIsTheHighestHourAhead() throws {
        let ahead = try XCTUnwrap(hours(from: 0, rain: [0, 0, 0], chance: [10, 80, 30]))
        XCTAssertEqual(ahead.chance, 80)
    }

    func testTheStartIsTheFirstMeasurableRainNotTheFirstDamp() throws {
        let ahead = try XCTUnwrap(hours(from: 0, rain: [0, 0.05, 0.3, 2], chance: [0, 20, 60, 90]))
        XCTAssertEqual(ahead.start, now.addingTimeInterval(TimeInterval((-20 + 120) * 60)))
    }

    /// A cached response from before hourly rain was requested carries neither
    /// array. Nothing beats a guess from stale daily figures.
    func testAResponseWithoutHourlyRainGivesNothing() {
        XCTAssertNil(RainAhead(times: [string(offset: 40)], precipitation: nil, probability: nil,
                               parser: formatter(), now: now))
    }

    func testAMissingProbabilityLeavesTheChanceUnknown() throws {
        let ahead = try XCTUnwrap(hours(from: 0, rain: [1, 0], chance: nil))

        XCTAssertNil(ahead.chance)
        XCTAssertEqual(ahead.amount, 1, accuracy: 0.0001)
    }

    // MARK: - Helpers

    /// Hourly times on the hour, starting `first` hours from the one in
    /// progress. `now` is twenty minutes past the hour.
    private func hours(from first: Int, rain: [Double?], chance: [Int?]?) -> RainAhead? {
        let times = rain.indices.map { string(offset: -20 + 60 * (first + $0)) }
        return RainAhead(times: times, precipitation: rain, probability: chance,
                         parser: formatter(), now: now)
    }

    private func formatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }

    private func string(offset minutes: Int) -> String {
        formatter().string(from: now.addingTimeInterval(TimeInterval(minutes * 60)))
    }

    private func make(offsets: [Int], millimetres: [Double?]) -> RainOutlook? {
        RainOutlook(
            times: offsets.map { string(offset: $0) },
            precipitation: millimetres,
            parser: formatter(),
            now: now
        )
    }
}
