//
//  CityLink.swift
//  climyte
//

import Foundation

/// The link a widget carries to its city's page in the app.
///
/// Tapping a widget used to open the app wherever it last was, so a widget
/// for New York could land you on Melbourne. The city is named by its key,
/// the same coordinates that identify it everywhere else.
nonisolated enum CityLink {
    static let scheme = "climyte"

    static func url(for city: City) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "city"
        components.queryItems = [URLQueryItem(name: "key", value: city.key)]
        return components.url
    }

    /// The city key a link names, or nil for anything that isn't one.
    static func cityKey(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == scheme, components.host == "city" else { return nil }
        return components.queryItems?.first { $0.name == "key" }?.value
    }
}
