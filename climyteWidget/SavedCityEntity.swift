//
//  SavedCityEntity.swift
//  climyteWidget
//

import AppIntents
import Foundation

/// A city the user has saved, offered as the widget's configuration choice.
///
/// Backed by the App Group rather than by anything the extension owns: the
/// list is whatever the app last wrote, so a city added in the app becomes
/// selectable here without the extension knowing anything about the network.
nonisolated struct SavedCityEntity: AppEntity {
    let id: String
    let name: String
    let country: String
    let countryCode: String?
    let latitude: Double
    let longitude: Double

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "City" }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(country)")
    }

    /// `let`, not `var`: a mutable static is nonisolated global shared state,
    /// which is an error in the Swift 6 language mode. The query holds nothing,
    /// so there is nothing to mutate.
    static let defaultQuery = SavedCityQuery()

    var city: City {
        City(id: UUID(), name: name, country: country,
             countryCode: countryCode, latitude: latitude, longitude: longitude)
    }

    init(city: City) {
        self.id = city.key
        self.name = city.name
        self.country = city.country
        self.countryCode = city.countryCode
        self.latitude = city.latitude
        self.longitude = city.longitude
    }
}

nonisolated struct SavedCityQuery: EntityQuery {
    /// Reads through the same type the app writes with, so the two cannot
    /// disagree about what is saved.
    static func savedCities() -> [City] {
        SavedCities.load(from: AppGroup.defaults, sources: .appGroup)
    }

    func entities(for identifiers: [String]) async throws -> [SavedCityEntity] {
        Self.savedCities()
            .filter { identifiers.contains($0.key) }
            .map(SavedCityEntity.init)
    }

    func suggestedEntities() async throws -> [SavedCityEntity] {
        Self.savedCities().map(SavedCityEntity.init)
    }

    func defaultResult() async -> SavedCityEntity? {
        Self.savedCities().first.map(SavedCityEntity.init)
    }
}

struct SelectCityIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Select City" }
    static var description: IntentDescription { "Choose which saved city this widget shows." }

    @Parameter(title: "City")
    var city: SavedCityEntity?

    init() {}

    init(city: SavedCityEntity?) {
        self.city = city
    }
}
