//
//  LocationManager.swift
//  climyte
//
//  Created by Antigravity on 25/7/2026.
//

import Foundation
import CoreLocation

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    
    @Published var location: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus
    @Published var cityName: String?
    @Published var countryName: String?
    
    private var locationContinuation: CheckedContinuation<CLLocation?, Never>?
    
    override init() {
        self.authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }
    
    /// Request location permission and fetch current location.
    /// Returns the location if successful, nil otherwise.
    func requestCurrentLocation() async -> CLLocation? {
        // Request permission if not yet determined
        if authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
            // Wait briefly for the authorization callback
            try? await Task.sleep(nanoseconds: 1_500_000_000)
        }
        
        #if os(iOS)
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            return nil
        }
        #else
        guard authorizationStatus == .authorizedAlways else {
            return nil
        }
        #endif
        
        return await withCheckedContinuation { continuation in
            self.locationContinuation = continuation
            manager.requestLocation()
        }
    }
    
    /// Reverse geocode a location to get the city and country name.
    func reverseGeocode(_ location: CLLocation) async -> (city: String, country: String)? {
        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            if let placemark = placemarks.first {
                let city = placemark.locality ?? placemark.name ?? "Unknown"
                let country = placemark.country ?? ""
                
                await MainActor.run {
                    self.cityName = city
                    self.countryName = country
                }
                
                return (city: city, country: country)
            }
        } catch {
            print("Reverse geocoding error: \(error)")
        }
        return nil
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let loc = locations.first {
            self.location = loc
            locationContinuation?.resume(returning: loc)
            locationContinuation = nil
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
        locationContinuation?.resume(returning: nil)
        locationContinuation = nil
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        self.authorizationStatus = manager.authorizationStatus
    }
}
