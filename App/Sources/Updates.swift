// Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Sparkle

/// Sparkle updates from the appcast published with each GitHub Release.
///
/// Updates are off until the build carries Sparkle's public EdDSA key
/// (`SPARKLE_PUBLIC_ED_KEY` in App/project.yml): without it Sparkle can't
/// verify downloads, so dev builds simply don't offer updates.
@MainActor
final class Updates {
    static let shared = Updates()

    private var controller: SPUStandardUpdaterController?

    var isAvailable: Bool { controller != nil }

    func start() {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? ""
        guard !key.isEmpty, !feed.isEmpty else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }
}
