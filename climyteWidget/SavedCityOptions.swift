//
//  SavedCityEntity.swift
//  climyteWidget
//

import AppIntents
import Foundation

/// The saved cities, offered as the widget's configuration choice.
///
/// A plain `String` rather than an `AppEntity`. The entity form never came
/// back: whatever was picked, `entities(for:)` was never called to rehydrate
/// it and the parameter arrived at the timeline as nil — masked for a long
/// time by a `defaultResult()` that quietly substituted the first saved city,
/// so the widget looked like it was ignoring the choice rather than never
/// receiving one.
///
/// The value is the city's name, which is also what the configuration sheet
/// shows, so there is nothing to resolve for display.
nonisolated struct SavedCityOptions: DynamicOptionsProvider {
    static func savedCities() -> [City] {
        SavedCities.load(from: AppGroup.defaults, sources: .appGroup)
    }

    func results() async throws -> [String] {
        Self.savedCities().map(\.name)
    }
}

struct SelectCityIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Select City" }
    static var description: IntentDescription { "Choose which saved city this widget shows." }

    @Parameter(title: "City", optionsProvider: SavedCityOptions())
    var cityName: String?

    init() {}

    init(cityName: String?) {
        self.cityName = cityName
    }

    /// The saved city of that name, or nil when it names one since removed.
    ///
    /// Two saved cities could in principle share a name — the list is keyed by
    /// coordinates, not by name — in which case the first wins. That is a
    /// better failure than the whole choice being dropped.
    var city: City? {
        guard let cityName else { return nil }
        return SavedCityOptions.savedCities().first { $0.name == cityName }
    }
}
