//
//  SavedCityOptions.swift
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

    /// A newly placed widget stores the first saved city as its choice.
    /// Without a default it stored nothing, and the picker showed its own
    /// label, "City", beside a widget that was showing a real city.
    func defaultResult() async -> String? {
        Self.savedCities().first?.name
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

    /// The city this widget shows, or the name of the one it was set to if
    /// that city has since been removed.
    var resolved: WidgetCity {
        WidgetCity.resolve(name: cityName, saved: SavedCityOptions.savedCities())
    }
}
