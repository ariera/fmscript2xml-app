// Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
// SPDX-License-Identifier: GPL-3.0-or-later

import FMHistory
import FMScriptKit
import KeyboardShortcuts
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @AppStorage(AppSettings.Key.onErrors) private var onErrors = ConversionPolicy.strict.rawValue
    @AppStorage(AppSettings.Key.showHUD) private var showHUD = true
    @AppStorage(AppSettings.Key.playSound) private var playSound = true
    @AppStorage(AppSettings.Key.historyLength) private var historyLength = HistoryStore.defaultCapacity
    @AppStorage(AppSettings.Key.keepHistory) private var keepHistory = true
    @AppStorage(AppSettings.Key.showInDock) private var showInDock = false
    @AppStorage(AppSettings.Key.autoPaste) private var autoPaste = false
    @State private var confirmClear = false
    @State private var accessibilityTrusted = AutoPaste.isTrusted
    private var history: HistoryStore { AppModel.shared.history }

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

            Section("After converting") {
                Toggle("Show HUD", isOn: $showHUD)
                Toggle("Play sound", isOn: $playSound)
                Toggle("Paste automatically (⌘V)", isOn: $autoPaste)
                    .onChange(of: autoPaste) { _, on in
                        if on && !AutoPaste.isTrusted { AutoPaste.requestTrust() }
                        accessibilityTrusted = AutoPaste.isTrusted
                    }
                if autoPaste && !accessibilityTrusted {
                    HStack {
                        Text("Needs Accessibility permission for \(Branding.appName).")
                            .font(.caption)
                        Button("Open Accessibility Settings") { AutoPaste.openAccessibilitySettings() }
                            .controlSize(.small)
                        Button("Check Again") { accessibilityTrusted = AutoPaste.isTrusted }
                            .controlSize(.small)
                    }
                }
            }

            Section("History") {
                Stepper(value: $historyLength, in: HistoryStore.capacityRange, step: 5) {
                    LabeledContent("Keep the last", value: historyLength == 0 ? "off" : "\(historyLength) conversions")
                }
                .onChange(of: historyLength) { _, value in AppModel.shared.setHistoryLength(value) }
                Toggle("Keep history after quitting", isOn: $keepHistory)
                    .onChange(of: keepHistory) { _, value in AppModel.shared.setKeepHistory(value) }
                Text(keepHistory
                     ? "Saved on this Mac only, in Application Support. Scripts can contain credentials."
                     : "History is kept in memory and forgotten when the app quits.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let error = history.lastError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                Button("Clear History…") { confirmClear = true }
                    .disabled(history.entries.isEmpty)
            }

            Section("General") {
                LaunchAtLoginToggle()
                Toggle("Show in Dock", isOn: $showInDock)
                    .onChange(of: showInDock) { _, value in DockIcon.apply(show: value) }
                if Updates.shared.isAvailable {
                    Toggle("Check for updates automatically", isOn: Binding(
                        get: { Updates.shared.automaticallyChecks },
                        set: { Updates.shared.automaticallyChecks = $0 }
                    ))
                }
            }

            Section("FileMaker Pro") {
                FileMakerInstallations()
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
        .confirmationDialog("Clear the conversion history?", isPresented: $confirmClear) {
            Button("Clear History", role: .destructive) { InspectorModel.shared.clearHistory() }
        }
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
