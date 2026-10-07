// Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
// SPDX-License-Identifier: GPL-3.0-or-later

import FMScriptKit
import KeyboardShortcuts
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @AppStorage(AppSettings.Key.onErrors) private var onErrors = ConversionPolicy.strict.rawValue
    @AppStorage(AppSettings.Key.showHUD) private var showHUD = true
    @AppStorage(AppSettings.Key.playSound) private var playSound = true

    var body: some View {
        Form {
            Section("Shortcuts") {
                KeyboardShortcuts.Recorder("Convert clipboard:", name: .convertClipboard)
                KeyboardShortcuts.Recorder("Open inspector:", name: .openInspector)
            }

            Section("Conversion") {
                Picker("On errors:", selection: $onErrors) {
                    Text("Leave clipboard unchanged").tag(ConversionPolicy.strict.rawValue)
                    Text("Copy what converted").tag(ConversionPolicy.continueOnError.rawValue)
                }
                Text(onErrors == ConversionPolicy.strict.rawValue
                     ? "If any step can't be converted, nothing is copied and you get a notification."
                     : "Steps that can't be converted are skipped; the rest is copied.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Feedback") {
                Toggle("Show HUD after converting", isOn: $showHUD)
                Toggle("Play sound", isOn: $playSound)
            }

            Section("General") {
                LaunchAtLoginToggle()
            }

            Section("FileMaker Pro") {
                FileMakerInstallations()
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Launch at login via SMAppService (D2).
struct LaunchAtLoginToggle: View {
    @State private var status = SMAppService.mainApp.status
    @State private var error: String?

    var body: some View {
        Toggle("Launch at login", isOn: Binding(
            get: { status == .enabled || status == .requiresApproval },
            set: { setEnabled($0) }
        ))
        if status == .requiresApproval {
            HStack {
                Text("Approve \(Branding.appName) in System Settings → General → Login Items.")
                    .font(.caption)
                Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                    .controlSize(.small)
            }
        }
        if let error {
            Text(error).font(.caption).foregroundStyle(.red)
        }
    }

    private func setEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        status = SMAppService.mainApp.status
    }
}

/// Installed FileMaker Pro versions (informational; FileMaker isn't needed
/// for converting).
struct FileMakerInstallations: View {
    private let apps = FileMakerDetector.installations()

    var body: some View {
        if apps.isEmpty {
            Text("No FileMaker Pro found. That's fine: it isn't needed for converting.")
                .foregroundStyle(.secondary)
        } else {
            ForEach(apps, id: \.url) { app in
                LabeledContent(app.name, value: app.version)
            }
        }
    }
}

enum FileMakerDetector {
    struct Installation {
        let name: String
        let version: String
        let url: URL
    }

    static let bundleIdentifiers = ["com.filemaker.client.pro12", "com.filemaker.client.advanced12"]

    static func installations() -> [Installation] {
        var seen = Set<URL>()
        return bundleIdentifiers
            .flatMap { NSWorkspace.shared.urlsForApplications(withBundleIdentifier: $0) }
            .filter { seen.insert($0.standardizedFileURL).inserted }
            .map { url in
                let info = Bundle(url: url)?.infoDictionary
                return Installation(
                    name: url.deletingPathExtension().lastPathComponent,
                    version: info?["CFBundleShortVersionString"] as? String ?? "?",
                    url: url
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
