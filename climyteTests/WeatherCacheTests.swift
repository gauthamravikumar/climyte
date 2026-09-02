//
//  WeatherCacheTests.swift
//  climyteTests
//

import XCTest
@testable import climyte

/// The cache is written by two processes — the app and the widget extension —
/// so its mutations have to survive being interleaved.
@MainActor
final class WeatherCacheTests: XCTestCase {

    private var directory: URL!
    private var cache: WeatherCache!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("climyteCacheTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        cache = WeatherCache(directory: directory)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        cache = nil
        super.tearDown()
    }

    func testAnAbsentFileReadsAsEmptyRatherThanFailing() {
        XCTAssertEqual(cache.loadAll().count, 0)
        XCTAssertNil(cache.load(for: city(0)))
    }

    func testASavedReadingComesBack() {
        cache.save(city: city(1), response: TestResponse.make(temperature: 21))

        XCTAssertEqual(cache.load(for: city(1))?.response.current.temperature_2m, 21)
    }

    func testSavingTheSameCityTwiceReplacesRatherThanDuplicates() {
        cache.save(city: city(1), response: TestResponse.make(temperature: 21))
        cache.save(city: city(1), response: TestResponse.make(temperature: 25))

        XCTAssertEqual(cache.loadAll().count, 1)
        XCTAssertEqual(cache.load(for: city(1))?.response.current.temperature_2m, 25)
    }

    func testPruneKeepsOnlyTheCitiesGiven() {
        for i in 0..<4 { cache.save(city: city(i), response: TestResponse.make()) }

        cache.prune(keeping: [city(1), city(3)])

        XCTAssertEqual(Set(cache.loadAll().map(\.city.key)),
                       Set([city(1).key, city(3).key]))
    }

    /// The defect this coordination exists for.
    ///
    /// Every save is a read-modify-write of the whole file. Run two of them
    /// against each other and, unsynchronised, both read the same starting
    /// state and the second write discards the first city entirely. It is not
    /// corruption — each write is atomic — which is exactly why it goes
    /// unnoticed: the file stays valid and a city just quietly isn't in it.
    func testConcurrentSavesDoNotDiscardEachOther() {
        let count = 24
        let cities = (0..<count).map { city($0) }
        // Built here rather than inside the loop: only the cache is under test.
        let responses = cities.map { _ in TestResponse.make() }
        let cache = self.cache!

        DispatchQueue.concurrentPerform(iterations: count) { index in
            cache.save(city: cities[index], response: responses[index])
        }

        let stored = Set(cache.loadAll().map(\.city.key))
        XCTAssertEqual(stored.count, count,
                       "\(count - stored.count) of \(count) saves were lost")
    }

    /// Pruning races saving in the same way: the app removes a city at the
    /// moment the widget writes one.
    func testConcurrentPrunesAndSavesLeaveTheFileIntact() {
        let cities = (0..<12).map { city($0) }
        let responses = cities.map { _ in TestResponse.make() }
        let cache = self.cache!

        DispatchQueue.concurrentPerform(iterations: cities.count) { index in
            if index.isMultiple(of: 3) {
                cache.prune(keeping: cities)
            } else {
                cache.save(city: cities[index], response: responses[index])
            }
        }

        // Whatever survived must be well-formed and free of duplicates.
        let all = cache.loadAll()
        XCTAssertEqual(Set(all.map(\.city.key)).count, all.count, "Duplicate entries")
        XCTAssertFalse(all.isEmpty, "Everything was lost")
    }

    /// Pruning used to run only on an explicit delete, so a city that left the
    /// saved list any other way kept its payload on disk forever. A real
    /// device was found holding ten cached cities for three saved ones.
    func testPruningIsDrivenByTheSavedListNotByDeletion() {
        for i in 0..<6 { cache.save(city: city(i), response: TestResponse.make()) }
        XCTAssertEqual(cache.loadAll().count, 6)

        // The saved list changes without any city being "removed".
        cache.prune(keeping: [city(1), city(4)])

        XCTAssertEqual(Set(cache.loadAll().map(\.city.key)),
                       Set([city(1).key, city(4).key]))
    }

    func testPruningWithNothingToDropLeavesTheFileAlone() throws {
        for i in 0..<3 { cache.save(city: city(i), response: TestResponse.make()) }
        let file = directory.appendingPathComponent("cached-weather.json")
        let before = try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date

        cache.prune(keeping: (0..<3).map { city($0) })

        let after = try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date
        XCTAssertEqual(before, after, "A prune that drops nothing should not rewrite the file")
        XCTAssertEqual(cache.loadAll().count, 3)
    }

    // MARK: - Helpers

    /// Distinct coordinates, because `City.key` is built from them.
    private func city(_ index: Int) -> City {
        City(id: UUID(), name: "City \(index)", country: "Testland", countryCode: "AU",
             latitude: Double(index) + 0.5, longitude: Double(index) + 0.25)
    }
}
