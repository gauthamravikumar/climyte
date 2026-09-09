//
//  LocationManager.swift
//  climyte
//
//  Created by Antigravity on 25/7/2026.
//

import Foundation
import os
import CoreLocation

/// The parts of `CLLocationManager` this app uses.
///
/// A protocol so the permission and failure paths can be tested. They are the
/// ones worth testing: each awaits a continuation that only something else
/// resumes, and a path that forgets to resume one does not return a wrong
/// answer — it never returns at all.
protocol LocationProviding: AnyObject {
    var authorizationStatus: CLAuthorizationStatus { get }
    var desiredAccuracy: CLLocationAccuracy { get set }
    var locationDelegate: CLLocationManagerDelegate? { get set }

    func requestWhenInUseAuthorization()
    func requestLocation()
}

extension CLLocationManager: LocationProviding {
    /// Named apart from `delegate` so this does not shadow the real property.
    var locationDelegate: CLLocationManagerDelegate? {
        get { delegate }
        set { delegate = newValue }
    }
}

/// The only four fields the app takes from a reverse geocode.
///
/// Narrower than `CLPlacemark` on purpose: a placemark cannot meaningfully be
/// constructed in a test, and nothing here needs one.
nonisolated struct GeocodedPlace {
    let locality: String?
    let name: String?
    let country: String?
    let isoCountryCode: String?
}

protocol Geocoding {
    func firstPlacemark(for location: CLLocation) async throws -> GeocodedPlace?
}

extension CLGeocoder: Geocoding {
    func firstPlacemark(for location: CLLocation) async throws -> GeocodedPlace? {
        try await reverseGeocodeLocation(location).first.map {
            GeocodedPlace(locality: $0.locality, name: $0.name,
                          country: $0.country, isoCountryCode: $0.isoCountryCode)
        }
    }
}

/// Thin CoreLocation wrapper exposing a single async "where am I?" call.
/// Deliberately not an `ObservableObject` — no view observes it directly.
final class LocationManager: NSObject, CLLocationManagerDelegate {
    private let manager: LocationProviding
    private let geocoder: Geocoding

    private var locationContinuation: CheckedContinuation<CLLocation?, Never>?
    private var authorizationContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?

    /// Both dependencies are resolved inside the initialiser rather than as
    /// default arguments, which are evaluated in a nonisolated context.
    init(manager: LocationProviding? = nil, geocoder: Geocoding? = nil) {
        self.manager = manager ?? CLLocationManager()
        self.geocoder = geocoder ?? CLGeocoder()
        super.init()
        self.manager.locationDelegate = self
        self.manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    /// Whether the reader has actually refused, as opposed to not being asked
    /// yet or having said yes. `requestCurrentLocation` returning nil cannot
    /// answer this on its own — a failed fix looks the same from outside.
    var accessIsRefused: Bool {
        let status = manager.authorizationStatus
        return status == .denied || status == .restricted
    }

    /// Requests permission if needed, then fetches the current location.
    /// Returns nil when permission is refused or the fix fails.
    func requestCurrentLocation() async -> CLLocation? {
        var status = manager.authorizationStatus

        // Wait for the user's actual answer rather than guessing at a duration.
        if status == .notDetermined {
            status = await withCheckedContinuation { continuation in
                guard authorizationContinuation == nil else {
                    // A prior request is already in flight; don't strand its continuation.
                    continuation.resume(returning: manager.authorizationStatus)
                    return
                }
                authorizationContinuation = continuation
                manager.requestWhenInUseAuthorization()
            }
        }

        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            guard locationContinuation == nil else {
                continuation.resume(returning: nil)
                return
            }
            locationContinuation = continuation
            manager.requestLocation()
        }
    }

    /// Reverse geocode a location to get the city and country name.
    func reverseGeocode(_ location: CLLocation) async -> (city: String, country: String, countryCode: String?)? {
        do {
            guard let place = try await geocoder.firstPlacemark(for: location) else { return nil }
            let city = place.locality ?? place.name ?? "Unknown"
            return (city: city, country: place.country ?? "", countryCode: place.isoCountryCode)
        } catch {
            Log.location.error("Reverse geocoding failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Delegate callbacks
    //
    // The CLLocationManagerDelegate methods forward to these, which read the
    // injected provider rather than the CLLocationManager they are handed —
    // so a test can drive the same paths without one.

    func handleLocations(_ locations: [CLLocation]) {
        guard let location = locations.first else { return }
        locationContinuation?.resume(returning: location)
        locationContinuation = nil
    }

    func handleFailure(_ error: Error) {
        Log.location.error("Location request failed: \(error.localizedDescription)")
        locationContinuation?.resume(returning: nil)
        locationContinuation = nil
    }

    func handleAuthorizationChange() {
        // Fires once when the delegate is set, before the user has answered.
        guard manager.authorizationStatus != .notDetermined else { return }
        authorizationContinuation?.resume(returning: manager.authorizationStatus)
        authorizationContinuation = nil
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        handleLocations(locations)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        handleFailure(error)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        handleAuthorizationChange()
    }
}
