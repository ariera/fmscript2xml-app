// Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
// SPDX-License-Identifier: GPL-3.0-or-later

import FMHistory
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
        static let historyLength = "historyLength"
        static let keepHistory = "keepHistory"
        static let showInDock = "showInDock"
        static let autoPaste = "autoPaste"
    }

    private static var defaults: UserDefaults { .standard }

    /// Strict (leave the clipboard unchanged) or copy what converted.
    static var policy: ConversionPolicy {
        defaults.string(forKey: Key.onErrors).flatMap(ConversionPolicy.init(rawValue:)) ?? .strict
    }

    static var showHUD: Bool { defaults.object(forKey: Key.showHUD) as? Bool ?? true }
    static var playSound: Bool { defaults.object(forKey: Key.playSound) as? Bool ?? true }
    static var historyLength: Int { defaults.object(forKey: Key.historyLength) as? Int ?? HistoryStore.defaultCapacity }
    static var keepHistory: Bool { defaults.object(forKey: Key.keepHistory) as? Bool ?? true }
    static var showInDock: Bool { defaults.bool(forKey: Key.showInDock) }
    static var autoPaste: Bool { defaults.bool(forKey: Key.autoPaste) }

    static var hasCompletedFirstRun: Bool {
        get { defaults.bool(forKey: Key.hasCompletedFirstRun) }
        set { defaults.set(newValue, forKey: Key.hasCompletedFirstRun) }
    }
}
