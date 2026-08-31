//
//  UnitSystem.swift
//  climyte
//

import SwiftUI

/// Which units readings are shown in.
///
/// The API is always asked for metric and conversion happens at display time,
/// so toggling is instant and works on cached data with no network.
nonisolated enum UnitSystem: String, Codable, CaseIterable {
    case metric
    case imperial

    /// The countries that report temperature in Fahrenheit. Everywhere else
    /// uses Celsius, so metric is the default rather than a guess.
    private static let fahrenheitCountryCodes: Set<String> = [
        "US", // United States
        "BS", // Bahamas
        "BZ", // Belize
        "KY", // Cayman Islands
        "PW", // Palau
        "FM", // Micronesia
        "MH", // Marshall Islands
        "LR", // Liberia
    ]

    /// Country names for the same set, used only for cities saved before the
    /// ISO code was stored. New cities always carry a code.
    private static let fahrenheitCountryNames: Set<String> = [
        "United States", "Bahamas", "Belize", "Cayman Islands",
        "Palau", "Micronesia", "Marshall Islands", "Liberia",
    ]

    /// Picks units from the country a city is in, not from the device.
    ///
    /// Note: the UK is treated as metric, which is right for temperature but
    /// not for wind and distance. Splitting it out would need a third system
    /// for one country's mixed conventions.
    static func forCountry(code: String?, name: String?) -> UnitSystem {
        if let code, fahrenheitCountryCodes.contains(code.uppercased()) {
            return .imperial
        }
        if code == nil, let name, fahrenheitCountryNames.contains(name) {
            return .imperial
        }
        return .metric
    }

    // MARK: - Conversion

    func temperatureValue(_ celsius: Double) -> Int {
        let converted = self == .metric ? celsius : celsius * 9 / 5 + 32
        return converted.toInt()
    }

    func temperature(_ celsius: Double) -> String {
        "\(temperatureValue(celsius))°"
    }

    func windSpeed(_ kilometresPerHour: Double) -> String {
        switch self {
        case .metric:
            return "\(kilometresPerHour.toInt()) km/h"
        case .imperial:
            return "\((kilometresPerHour * 0.621371).toInt()) mph"
        }
    }

    func precipitation(_ millimetres: Double) -> String {
        switch self {
        case .metric:
            return String(format: "%.1f mm", millimetres)
        case .imperial:
            return String(format: "%.2f in", millimetres / 25.4)
        }
    }

    func visibility(_ kilometres: Double) -> String {
        switch self {
        case .metric:
            return "\(kilometres.toInt()) km"
        case .imperial:
            return "\((kilometres * 0.621371).toInt()) mi"
        }
    }
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
