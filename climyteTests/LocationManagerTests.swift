//
//  LocationManagerTests.swift
//  climyteTests
//

import XCTest
import CoreLocation
@testable import climyte

/// The permission and geocoding paths.
///
/// Worth testing precisely because of how they fail: each awaits a
/// continuation that only a delegate callback resumes, so a path that forgets
/// to resume one does not produce a wrong answer — it hangs the caller
/// forever. Every test here has a timeout for that reason.
@MainActor
final class LocationManagerTests: XCTestCase {

    private var provider: StubLocationProvider!
    private var geocoder: StubGeocoder!

    override func setUp() {
        super.setUp()
        provider = StubLocationProvider()
        geocoder = StubGeocoder()
    }

    override func tearDown() {
        provider = nil
        geocoder = nil
        super.tearDown()
    }

    // MARK: - Permission refused

    func testARefusedPermissionReturnsNoLocationAndAsksForNoFix() async throws {
        for status in [CLAuthorizationStatus.denied, .restricted] {
            provider = StubLocationProvider()
            provider.authorizationStatus = status
            let manager = makeManager()

            let location = try await withTimeout { await manager.requestCurrentLocation() }

            XCTAssertNil(location, "\(status) should yield no location")
            XCTAssertFalse(provider.requestedLocation,
                           "\(status): asking for a fix we cannot have wastes a callback")
            XCTAssertFalse(provider.requestedAuthorization,
                           "\(status): the answer is already known, so do not re-prompt")
        }
    }

    /// The prompt is shown, and the reader says no.
    func testAPromptAnsweredWithNoReturnsNoLocation() async throws {
        provider.authorizationStatus = .notDetermined
        let manager = makeManager()
        provider.onRequestAuthorization = { [weak manager] in
            self.provider.authorizationStatus = .denied
            manager?.handleAuthorizationChange()
        }

        let location = try await withTimeout { await manager.requestCurrentLocation() }

        XCTAssertNil(location)
        XCTAssertTrue(provider.requestedAuthorization)
        XCTAssertFalse(provider.requestedLocation)
    }

    /// The delegate fires once when it is set, before the reader has answered.
    /// Treating that as an answer would resume the continuation with
    /// `.notDetermined` and refuse a permission never actually declined.
    func testAnEarlyNotDeterminedCallbackIsNotMistakenForAnAnswer() async throws {
        provider.authorizationStatus = .notDetermined
        let manager = makeManager()
        provider.onRequestAuthorization = { [weak manager] in
            // The spurious callback first, then the real one.
            manager?.handleAuthorizationChange()
            self.provider.authorizationStatus = .authorizedWhenInUse
            manager?.handleAuthorizationChange()
        }
        provider.onRequestLocation = { [weak manager] in
            manager?.handleLocations([Self.melbourne])
        }

        let location = try await withTimeout { await manager.requestCurrentLocation() }

        XCTAssertEqual(location?.coordinate.latitude, Self.melbourne.coordinate.latitude)
    }

    func testAPromptAnsweredWithYesFetchesTheLocation() async throws {
        provider.authorizationStatus = .notDetermined
        let manager = makeManager()
        provider.onRequestAuthorization = { [weak manager] in
            self.provider.authorizationStatus = .authorizedAlways
            manager?.handleAuthorizationChange()
        }
        provider.onRequestLocation = { [weak manager] in
            manager?.handleLocations([Self.melbourne])
        }

        let location = try await withTimeout { await manager.requestCurrentLocation() }

        XCTAssertNotNil(location)
        XCTAssertTrue(provider.requestedLocation)
    }

    // MARK: - The fix itself failing

    func testAFailedFixReturnsNilRatherThanHanging() async throws {
        provider.authorizationStatus = .authorizedWhenInUse
        let manager = makeManager()
        provider.onRequestLocation = { [weak manager] in
            manager?.handleFailure(CLError(.locationUnknown))
        }

        let location = try await withTimeout { await manager.requestCurrentLocation() }

        XCTAssertNil(location)
    }

    /// An empty update is not an answer; the real one arrives afterwards.
    func testAnEmptyLocationUpdateDoesNotResolveTheRequest() async throws {
        provider.authorizationStatus = .authorizedWhenInUse
        let manager = makeManager()
        provider.onRequestLocation = { [weak manager] in
            manager?.handleLocations([])
            manager?.handleLocations([Self.melbourne])
        }

        let location = try await withTimeout { await manager.requestCurrentLocation() }

        XCTAssertEqual(location?.coordinate.longitude, Self.melbourne.coordinate.longitude)
    }

    /// A second callback after the continuation has been resumed must be
    /// ignored, not resumed twice — resuming a continuation twice traps.
    func testALateSecondCallbackIsIgnored() async throws {
        provider.authorizationStatus = .authorizedWhenInUse
        let manager = makeManager()
        provider.onRequestLocation = { [weak manager] in
            manager?.handleLocations([Self.melbourne])
        }

        _ = try await withTimeout { await manager.requestCurrentLocation() }

        // Whatever arrives now has no continuation waiting for it.
        manager.handleLocations([Self.melbourne])
        manager.handleFailure(CLError(.network))
        manager.handleAuthorizationChange()
    }

    // MARK: - Reverse geocoding

    func testAGeocodingFailureReturnsNil() async {
        geocoder.result = .failure(CLError(.geocodeFoundNoResult))
        let place = await makeManager().reverseGeocode(Self.melbourne)

        XCTAssertNil(place)
    }

    func testNoPlacemarkReturnsNil() async {
        geocoder.result = .success(nil)
        let place = await makeManager().reverseGeocode(Self.melbourne)

        XCTAssertNil(place)
    }

    func testAPlacemarkWithoutALocalityFallsBackToItsName() async {
        geocoder.result = .success(GeocodedPlace(locality: nil, name: "Kangaroo Ground",
                                                 country: "Australia", isoCountryCode: "AU"))
        let place = await makeManager().reverseGeocode(Self.melbourne)

        XCTAssertEqual(place?.city, "Kangaroo Ground")
        XCTAssertEqual(place?.countryCode, "AU")
    }

    /// Somewhere with no name at all still has to produce a usable city, since
    /// the result becomes a saved entry.
    func testAPlacemarkWithNoNamesAtAllIsStillUsable() async {
        geocoder.result = .success(GeocodedPlace(locality: nil, name: nil,
                                                 country: nil, isoCountryCode: nil))
        let place = await makeManager().reverseGeocode(Self.melbourne)

        XCTAssertEqual(place?.city, "Unknown")
        XCTAssertEqual(place?.country, "", "An absent country is empty, not the word nil")
        XCTAssertNil(place?.countryCode)
    }

    func testTheLocalityWinsOverTheName() async {
        geocoder.result = .success(GeocodedPlace(locality: "Melbourne", name: "Some Street",
                                                 country: "Australia", isoCountryCode: "AU"))
        let place = await makeManager().reverseGeocode(Self.melbourne)

        XCTAssertEqual(place?.city, "Melbourne")
    }

    // MARK: - Helpers

    private static let melbourne = CLLocation(latitude: -37.8136, longitude: 144.9631)

    private func makeManager() -> LocationManager {
        LocationManager(manager: provider, geocoder: geocoder)
    }

    /// Fails rather than hanging the whole suite if a continuation is stranded.
    ///
    /// Deliberately not a task group. A group awaits its children when the
    /// scope ends, so a child stuck on a continuation nobody resumes would
    /// hang here too — the precise failure this exists to report. Verified by
    /// deleting a `resume` in the source: with a group the suite hung until
    /// killed; this returns a failure in two seconds. The stuck task is
    /// abandoned, which leaks it for the rest of the run and is the right
    /// trade in a test.
    private func withTimeout<T>(
        _ seconds: Double = 2,
        _ work: @escaping @MainActor () async -> T
    ) async throws -> T {
        let box = ResultBox<T>()
        let worker = Task { @MainActor in box.value = await work() }
        defer { worker.cancel() }

        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if let value = box.value { return value }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        throw StrandedContinuation()
    }

    private struct StrandedContinuation: Error, CustomStringConvertible {
        var description: String { "Timed out — a continuation was never resumed" }
    }
}

@MainActor
private final class ResultBox<T> {
    var value: T?
}

@MainActor
private final class StubLocationProvider: LocationProviding {
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var desiredAccuracy: CLLocationAccuracy = 0
    weak var locationDelegate: CLLocationManagerDelegate?

    private(set) var requestedAuthorization = false
    private(set) var requestedLocation = false

    var onRequestAuthorization: (() -> Void)?
    var onRequestLocation: (() -> Void)?

    func requestWhenInUseAuthorization() {
        requestedAuthorization = true
        onRequestAuthorization?()
    }

    func requestLocation() {
        requestedLocation = true
        onRequestLocation?()
    }
}

private final class StubGeocoder: Geocoding, @unchecked Sendable {
    var result: Result<GeocodedPlace?, Error> = .success(nil)

    func firstPlacemark(for location: CLLocation) async throws -> GeocodedPlace? {
        try result.get()
    }
}
