//
//  DeferralStoreTests.swift
//  climyteTests
//

import XCTest
@testable import climyte

/// Deferrals are per city. A single shared marker meant one widget deferring
/// could push another widget's very next pass down the blocking path — and
/// that pass might be the one that had to be fast.
@MainActor
final class DeferralStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!
    private var store: DeferralStore!

    private let sydney = "-33.8688,151.2093"
    private let denver = "39.7392,-104.9847"

    override func setUp() {
        super.setUp()
        suiteName = "climyteTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = DeferralStore(defaults: defaults, window: 120)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil; suiteName = nil; store = nil
        super.tearDown()
    }

    func testNothingIsDeferredToBeginWith() {
        XCTAssertNil(store.lastDeferral(forCity: sydney))
    }

    func testADeferralComesBack() {
        let at = Date()
        store.record(forCity: sydney, at: at)

        XCTAssertEqual(store.lastDeferral(forCity: sydney)?.timeIntervalSinceReferenceDate ?? 0,
                       at.timeIntervalSinceReferenceDate, accuracy: 0.001)
    }

    /// The defect this type exists for.
    func testOneCitysDeferralDoesNotAffectAnother() {
        store.record(forCity: sydney)

        XCTAssertNotNil(store.lastDeferral(forCity: sydney))
        XCTAssertNil(store.lastDeferral(forCity: denver),
                     "A widget showing Denver has nothing to learn from one showing Sydney")
    }

    func testClearingOneCityLeavesTheOthers() {
        store.record(forCity: sydney)
        store.record(forCity: denver)

        store.clear(forCity: sydney)

        XCTAssertNil(store.lastDeferral(forCity: sydney))
        XCTAssertNotNil(store.lastDeferral(forCity: denver))
    }

    /// A deferral that never got its follow-up must stop counting, so the
    /// widget falls back to fetching inline rather than deferring for ever.
    func testADeferralExpiresWithTheWindow() {
        let old = Date().addingTimeInterval(-300)
        store.record(forCity: sydney, at: old)

        XCTAssertNil(store.lastDeferral(forCity: sydney))
    }

    func testADeferralInsideTheWindowStillCounts() {
        store.record(forCity: sydney, at: Date().addingTimeInterval(-30))

        XCTAssertNotNil(store.lastDeferral(forCity: sydney))
    }

    /// Cities the reader removed must not accumulate here the way they once
    /// did in the weather cache.
    func testLongDeadEntriesArePrunedOnWrite() {
        for i in 0..<20 {
            store.record(forCity: "ghost-\(i)", at: Date().addingTimeInterval(-5_000))
        }
        store.record(forCity: sydney)

        let stored = defaults.dictionary(forKey: "widget_deferred_fetches") as? [String: Double] ?? [:]
        XCTAssertEqual(stored.count, 1, "Only the live deferral should remain")
        XCTAssertNotNil(stored[sydney])
    }

    /// The single global marker this replaced was live for one build, so it
    /// is sitting in shared defaults on any device that installed it.
    func testTheGlobalMarkerItReplacedIsCleanedUp() {
        defaults.set(Date().timeIntervalSinceReferenceDate, forKey: "widget_deferred_fetch_at")

        _ = DeferralStore(defaults: defaults)

        XCTAssertNil(defaults.object(forKey: "widget_deferred_fetch_at"))
    }

    func testTheStoreEmptiesItselfRatherThanLeavingAnEmptyDictionary() {
        store.record(forCity: sydney)
        store.clear(forCity: sydney)

        XCTAssertNil(defaults.object(forKey: "widget_deferred_fetches"))
    }
}
