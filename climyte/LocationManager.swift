//
//  LocationManager.swift
//  climyte
//
//  Created by Antigravity on 25/7/2026.
//

import Foundation
import os
import CoreLocation

/// Thin CoreLocation wrapper exposing a single async "where am I?" call.
/// Deliberately not an `ObservableObject` — no view observes it directly.
final class LocationManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    private var locationContinuation: CheckedContinuation<CLLocation?, Never>?
    private var authorizationContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
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
        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            if let placemark = placemarks.first {
                let city = placemark.locality ?? placemark.name ?? "Unknown"
                let country = placemark.country ?? ""
                return (city: city, country: country, countryCode: placemark.isoCountryCode)
            }
        } catch {
            Log.location.error("Reverse geocoding failed: \(error.localizedDescription)")
        }
        return nil
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.first else { return }
        locationContinuation?.resume(returning: loc)
        locationContinuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Log.location.error("Location request failed: \(error.localizedDescription)")
        locationContinuation?.resume(returning: nil)
        locationContinuation = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        // Fires once when the delegate is set, before the user has answered.
        guard status != .notDetermined else { return }
        authorizationContinuation?.resume(returning: status)
        authorizationContinuation = nil
    }
}
