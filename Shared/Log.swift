//
//  Log.swift
//  climyte
//

import Foundation
import os

/// Unified logging, replacing scattered `print` calls.
///
/// Unlike `print`, these survive into Console.app and the device log, carry a
/// level, and are stripped of interpolated values in release builds unless
/// explicitly marked public.
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "climyte"

    static let weather = Logger(subsystem: subsystem, category: "weather")
    static let location = Logger(subsystem: subsystem, category: "location")
    static let cache = Logger(subsystem: subsystem, category: "cache")
}
