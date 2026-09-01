//
//  UnitSystem.swift
//  climyte
//

import SwiftUI

/// Which units a city's readings are shown in.
///
/// Four independent choices rather than one metric/imperial switch, because
/// almost no country is wholly one or the other. Britain reports weather in
/// Celsius and rainfall in millimetres, but wind in miles per hour and
/// visibility in miles. A single enum could not express that, so the UK was
/// filed under metric and shown wind speeds no forecast there would use.
///
/// The API is always asked for metric and conversion happens at display time,
/// so this works on cached data with no network.
nonisolated struct UnitSystem: Equatable {

    enum Temperature: Equatable { case celsius, fahrenheit }
    enum Speed: Equatable { case kilometresPerHour, milesPerHour }
    enum Distance: Equatable { case kilometres, miles }
    enum Rainfall: Equatable { case millimetres, inches }

    let temperatureUnit: Temperature
    let speedUnit: Speed
    let distanceUnit: Distance
    let rainfallUnit: Rainfall

    /// Celsius, km/h, kilometres, millimetres. What most of the world uses.
    static let metric = UnitSystem(temperatureUnit: .celsius,
                                   speedUnit: .kilometresPerHour,
                                   distanceUnit: .kilometres,
                                   rainfallUnit: .millimetres)

    /// Fahrenheit, mph, miles, inches. The United States and its territories.
    static let imperial = UnitSystem(temperatureUnit: .fahrenheit,
                                     speedUnit: .milesPerHour,
                                     distanceUnit: .miles,
                                     rainfallUnit: .inches)

    /// Celsius and millimetres, but miles per hour and miles.
    ///
    /// The mix Britain actually uses: the Met Office forecasts in Celsius and
    /// millimetres, while road signs, speed limits and visibility reports are
    /// in miles.
    static let british = UnitSystem(temperatureUnit: .celsius,
                                    speedUnit: .milesPerHour,
                                    distanceUnit: .miles,
                                    rainfallUnit: .millimetres)

    // MARK: - Country mapping

    /// Fahrenheit, miles per hour, miles and inches.
    ///
    /// There is no country that reports Fahrenheit and then measures wind in
    /// km/h — where Fahrenheit survives, so do miles. So this is one list
    /// rather than two: the United States, its territories, and the states
    /// that kept American conventions.
    private static let imperialCodes: Set<String> = [
        "US", // United States
        "PR", // Puerto Rico
        "GU", // Guam
        "VI", // U.S. Virgin Islands
        "AS", // American Samoa
        "MP", // Northern Mariana Islands
        "BS", // Bahamas
        "BZ", // Belize
        "KY", // Cayman Islands
        "PW", // Palau
        "FM", // Micronesia
        "MH", // Marshall Islands
        "LR", // Liberia
    ]

    /// Celsius, but miles and miles per hour: the United Kingdom, its overseas
    /// territories, and the Commonwealth states that kept imperial road units.
    private static let milesCodes: Set<String> = [
        "GB", // United Kingdom
        "AI", // Anguilla
        "BM", // Bermuda
        "VG", // British Virgin Islands
        "FK", // Falkland Islands
        "GI", // Gibraltar
        "MS", // Montserrat
        "SH", // Saint Helena
        "TC", // Turks and Caicos Islands
        "AG", // Antigua and Barbuda
        "DM", // Dominica
        "GD", // Grenada
        "KN", // Saint Kitts and Nevis
        "LC", // Saint Lucia
        "VC", // Saint Vincent and the Grenadines
        "MM", // Myanmar
        "WS", // Samoa
    ]

    /// Country names for cities saved before the ISO code was stored. New
    /// cities always carry a code, so this only covers upgrades.
    private static let namesByCode: [String: String] = [
        "United States": "US", "Bahamas": "BS", "Belize": "BZ",
        "Cayman Islands": "KY", "Palau": "PW", "Micronesia": "FM",
        "Marshall Islands": "MH", "Liberia": "LR",
        "United Kingdom": "GB", "Myanmar": "MM", "Bermuda": "BM",
        "Gibraltar": "GI", "Samoa": "WS",
    ]

    /// Picks units from the country a city is in, not from the device.
    static func forCountry(code: String?, name: String?) -> UnitSystem {
        // An empty string is not a country code. Treating it as one meant a
        // legacy city with a blank code never reached the name fallback.
        let trimmed = code?.trimmingCharacters(in: .whitespaces).uppercased()
        let resolved = (trimmed?.isEmpty == false ? trimmed : nil)
            ?? name.flatMap { namesByCode[$0] }

        guard let resolved else { return .metric }

        if imperialCodes.contains(resolved) { return .imperial }
        if milesCodes.contains(resolved) { return .british }
        return .metric
    }

    // MARK: - Conversion

    func temperatureValue(_ celsius: Double) -> Int {
        let converted = temperatureUnit == .celsius ? celsius : celsius * 9 / 5 + 32
        return converted.toInt()
    }

    func temperature(_ celsius: Double) -> String {
        "\(temperatureValue(celsius))°"
    }

    func windSpeed(_ kilometresPerHour: Double) -> String {
        switch speedUnit {
        case .kilometresPerHour:
            return "\(kilometresPerHour.toInt()) km/h"
        case .milesPerHour:
            return "\((kilometresPerHour * Self.milesPerKilometre).toInt()) mph"
        }
    }

    func visibility(_ kilometres: Double) -> String {
        switch distanceUnit {
        case .kilometres:
            return "\(kilometres.toInt()) km"
        case .miles:
            return "\((kilometres * Self.milesPerKilometre).toInt()) mi"
        }
    }

    /// Formatted through the reader's locale, so a German reader sees "9,5 mm".
    /// `String(format:)` has no locale and always emits a full stop.
    func precipitation(_ millimetres: Double) -> String {
        switch rainfallUnit {
        case .millimetres:
            return "\(millimetres.formatted(.number.precision(.fractionLength(1)))) mm"
        case .inches:
            let inches = millimetres / Self.millimetresPerInch
            return "\(inches.formatted(.number.precision(.fractionLength(2)))) in"
        }
    }

    private static let milesPerKilometre = 0.621371
    private static let millimetresPerInch = 25.4
}

// MARK: - Environment

private struct UnitSystemKey: EnvironmentKey {
    static let defaultValue = UnitSystem.metric
}

extension EnvironmentValues {
    var unitSystem: UnitSystem {
        get { self[UnitSystemKey.self] }
        set { self[UnitSystemKey.self] = newValue }
    }
}
