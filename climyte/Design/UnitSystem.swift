//
//  UnitSystem.swift
//  climyte
//

import SwiftUI

/// Which units readings are shown in.
///
/// The API is always asked for metric and conversion happens at display time,
/// so toggling is instant and works on cached data with no network.
enum UnitSystem: String, Codable, CaseIterable {
    case metric
    case imperial

    /// Seeds the initial choice from the device's region.
    ///
    /// Note: the UK is treated as metric, which is right for temperature but
    /// not for wind and distance. Splitting it out would mean a third state,
    /// which the tap-to-toggle gesture can't express cleanly.
    static var deviceDefault: UnitSystem {
        Locale.current.measurementSystem == .us ? .imperial : .metric
    }

    var toggled: UnitSystem {
        self == .metric ? .imperial : .metric
    }

    // MARK: - Conversion

    func temperatureValue(_ celsius: Double) -> Int {
        let converted = self == .metric ? celsius : celsius * 9 / 5 + 32
        return Int(converted.rounded())
    }

    func temperature(_ celsius: Double) -> String {
        "\(temperatureValue(celsius))°"
    }

    func windSpeed(_ kilometresPerHour: Double) -> String {
        switch self {
        case .metric:
            return "\(Int(kilometresPerHour.rounded())) km/h"
        case .imperial:
            return "\(Int((kilometresPerHour * 0.621371).rounded())) mph"
        }
    }

    func visibility(_ kilometres: Double) -> String {
        switch self {
        case .metric:
            return "\(Int(kilometres.rounded())) km"
        case .imperial:
            return "\(Int((kilometres * 0.621371).rounded())) mi"
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
