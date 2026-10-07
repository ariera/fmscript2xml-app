// Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
// SPDX-License-Identifier: GPL-3.0-or-later

import FMScriptKit
import Foundation

/// UserDefaults-backed settings (PLAN §8). Views bind to the same keys with
/// @AppStorage.
enum AppSettings {
    enum Key {
        static let onErrors = "onErrors"
        static let showHUD = "showHUD"
        static let playSound = "playSound"
        static let hasCompletedFirstRun = "hasCompletedFirstRun"
    }

    private static var defaults: UserDefaults { .standard }

    /// Strict (leave the clipboard unchanged) or copy what converted.
    static var policy: ConversionPolicy {
        defaults.string(forKey: Key.onErrors).flatMap(ConversionPolicy.init(rawValue:)) ?? .strict
    }

    static var showHUD: Bool { defaults.object(forKey: Key.showHUD) as? Bool ?? true }
    static var playSound: Bool { defaults.object(forKey: Key.playSound) as? Bool ?? true }

    static var hasCompletedFirstRun: Bool {
        get { defaults.bool(forKey: Key.hasCompletedFirstRun) }
        set { defaults.set(newValue, forKey: Key.hasCompletedFirstRun) }
    }
}
