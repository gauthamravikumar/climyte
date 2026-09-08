//
//  CityEntry.swift
//  climyte
//

import Foundation

nonisolated extension City {
    /// Stable identity across launches and decodes.
    ///
    /// `id` is a fresh UUID every time a City is created or decoded, so it
    /// can't key persistent state. Equality is already defined by coordinates,
    /// and this matches that.
    var key: String {
        String(format: "%.4f,%.4f", latitude, longitude)
    }

    /// Each city is shown in its own country's units. There is no global
    /// setting and no override.
    var unitSystem: UnitSystem {
        UnitSystem.forCountry(code: countryCode, name: country)
    }
}

/// One page in the app: a city and everything known about its weather.
///
/// A value type held in a `@Published` array rather than a nested
/// `ObservableObject`, because nested observables don't propagate their
/// changes through SwiftUI without manual plumbing.
struct CityEntry: Identifiable, Equatable {
    let city: City

    /// True for the entry derived from CoreLocation. Replaced rather than
    /// duplicated when the device moves, and placed first only when it is new
    /// to the list — once it is there, its position is the reader's to set.
    var isCurrentLocation: Bool = false

    var weather: CityWeather?
    var isLoading: Bool = false
    var errorMessage: String?
    var lastUpdated: Date?

    var id: String { city.key }

    static func == (lhs: CityEntry, rhs: CityEntry) -> Bool {
        lhs.city == rhs.city
            && lhs.isCurrentLocation == rhs.isCurrentLocation
            && lhs.weather?.id == rhs.weather?.id
            && lhs.isLoading == rhs.isLoading
            && lhs.errorMessage == rhs.errorMessage
            && lhs.lastUpdated == rhs.lastUpdated
    }
}
