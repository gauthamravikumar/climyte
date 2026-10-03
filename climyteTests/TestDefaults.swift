//
//  TestDefaults.swift
//  climyteTests
//

import Foundation

/// Settings for tests, kept apart from the app's.
///
/// Each test class has one suite under a fixed name, emptied before and after
/// every test. A fresh random name per test kept tests apart too, but every
/// suite leaves a file behind, even emptied — the system writes it back after
/// the run ends — so each run added about sixty `climyteTests.<UUID>.plist`
/// files to the simulator, 866 of them before this. Fixed names leave a few
/// files that each run reuses.
nonisolated enum TestDefaults {
    /// The named suite, emptied. Tests run one at a time, so a test class can
    /// reuse its name without one test seeing another's settings.
    static func suite(_ name: String) -> UserDefaults {
        discard(name)
        return UserDefaults(suiteName: name)!
    }

    static func discard(_ name: String) {
        UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
    }
}
