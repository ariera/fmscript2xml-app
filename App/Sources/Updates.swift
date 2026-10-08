// Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Observation
import Sparkle

/// Sparkle updates from the appcast published with each GitHub Release.
///
/// Uses Sparkle's standard pieces: `SPUStandardUpdaterController` for the
/// update UI, `checkForUpdateInformation()` for a silent check whose result
/// Settings and About show, `checkForUpdates()` to install, and gentle
/// scheduled reminders, recommended for apps without a Dock icon.
///
/// Updates are off until the build carries Sparkle's public EdDSA key
/// (`SPARKLE_PUBLIC_ED_KEY` in App/project.yml). Debug builds don't check
/// unless launched with `-FMSPEnableUpdates YES`, so development builds
/// don't offer the published release.
@MainActor
@Observable
final class Updates: NSObject {
    static let shared = Updates()

    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(displayVersion: String)
        case failed(String)
    }

    private(set) var status: Status = .idle
    /// Mirrors `SPUUpdater.canCheckForUpdates` (false while a check runs).
    private(set) var canCheckForUpdates = false

    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?

    var isAvailable: Bool { controller != nil }

    func start() {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? ""
        guard !key.isEmpty, !feed.isEmpty else { return }
        #if DEBUG
        guard UserDefaults.standard.bool(forKey: "FMSPEnableUpdates") else { return }
        #endif
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
        self.controller = controller
        canCheckObservation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, change in
            // Read the value from the change: the updater itself is main-actor isolated
            let value = change.newValue ?? false
            MainActor.assumeIsolated { self?.canCheckForUpdates = value }
        }
    }

    /// Opens Sparkle's update window: shows the available update and installs it.
    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    /// Checks the appcast without any UI; the result goes to `status`.
    func checkInBackground() {
        guard let updater = controller?.updater, updater.canCheckForUpdates else { return }
        // Keep showing a known result while it's refreshed
        switch status {
        case .idle, .failed: status = .checking
        case .checking, .upToDate, .available: break
        }
        updater.checkForUpdateInformation()
    }

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }
}

extension Updates: SPUUpdaterDelegate {
    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = Branding.displayVersion(for: item.displayVersionString)
        MainActor.assumeIsolated { status = .available(displayVersion: version) }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        MainActor.assumeIsolated { status = .upToDate }
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        let nsError = error as NSError
        // "No update" also arrives here as an abort with SUNoUpdateError
        let isNoUpdate = nsError.domain == SUSparkleErrorDomain && nsError.code == Int(SUError.noUpdateError.rawValue)
        let message = error.localizedDescription
        MainActor.assumeIsolated { status = isNoUpdate ? .upToDate : .failed(message) }
    }
}

extension Updates: SPUStandardUserDriverDelegate {
    /// A menu bar app has no Dock icon to badge, so Sparkle's scheduled
    /// update alerts are shown as gentle reminders.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }
}
