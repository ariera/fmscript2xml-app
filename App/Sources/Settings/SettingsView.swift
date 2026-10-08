// Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
// SPDX-License-Identifier: GPL-3.0-or-later

import FMHistory
import FMScriptKit
import KeyboardShortcuts
import ServiceManagement
import SwiftUI

/// Settings, as standard macOS toolbar tabs. Each tab is a short grouped
/// form, so the window stays small.
struct SettingsView: View {
    enum Tab: String {
        case general, shortcuts, conversion, history, updates
    }

    @AppStorage("settingsTab") private var tab = Tab.general

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(Tab.general)
            ShortcutSettings()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
                .tag(Tab.shortcuts)
            ConversionSettings()
                .tabItem { Label("Conversion", systemImage: "arrow.left.arrow.right") }
                .tag(Tab.conversion)
            HistorySettings()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(Tab.history)
            UpdateSettings()
                .tabItem { Label("Updates", systemImage: "arrow.down.circle") }
                .tag(Tab.updates)
        }
        .frame(width: 520)
        .onAppear { Updates.shared.checkInBackground() }
    }
}

/// A tab's content: a grouped form, as tall as its content.
private struct SettingsPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        Form { content }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct GeneralSettings: View {
    @AppStorage(AppSettings.Key.showInDock) private var showInDock = false

    var body: some View {
        SettingsPage {
            Section {
                LaunchAtLoginToggle()
                Toggle("Show in Dock", isOn: $showInDock)
                    .onChange(of: showInDock) { _, value in DockIcon.apply(show: value) }
            }
            Section("FileMaker Pro") {
                FileMakerInstallations()
            }
        }
    }
}

private struct ShortcutSettings: View {
    @AppStorage(AppSettings.Key.inspectorShortcutEnabled) private var inspectorShortcutEnabled = false

    var body: some View {
        SettingsPage {
            Section {
                KeyboardShortcuts.Recorder("Convert clipboard:", name: .convertClipboard)
            }
            Section {
                Toggle("Shortcut to open the inspector", isOn: $inspectorShortcutEnabled)
                    .onChange(of: inspectorShortcutEnabled) { _, on in InspectorShortcut.apply(enabled: on) }
                if inspectorShortcutEnabled {
                    KeyboardShortcuts.Recorder("Open inspector:", name: .openInspector)
                }
            }
        }
    }
}

private struct ConversionSettings: View {
    @AppStorage(AppSettings.Key.onErrors) private var onErrors = ConversionPolicy.strict.rawValue
    @AppStorage(AppSettings.Key.showHUD) private var showHUD = true
    @AppStorage(AppSettings.Key.playSound) private var playSound = true
    @AppStorage(AppSettings.Key.autoPaste) private var autoPaste = false
    @State private var accessibilityTrusted = AutoPaste.isTrusted

    var body: some View {
        SettingsPage {
            Section {
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
        }
    }
}

private struct HistorySettings: View {
    @AppStorage(AppSettings.Key.historyLength) private var historyLength = HistoryStore.defaultCapacity
    @AppStorage(AppSettings.Key.keepHistory) private var keepHistory = true
    @State private var confirmClear = false
    private var history: HistoryStore { AppModel.shared.history }

    var body: some View {
        SettingsPage {
            Section {
                Stepper(value: $historyLength, in: HistoryStore.capacityRange, step: 5) {
                    LabeledContent("Keep the last", value: historyLength == 0 ? "off" : "\(historyLength) conversions")
                }
                .onChange(of: historyLength) { _, value in AppModel.shared.setHistoryLength(value) }
                Toggle("Keep history after quitting", isOn: $keepHistory)
                    .onChange(of: keepHistory) { _, value in AppModel.shared.setKeepHistory(value) }
                Text(keepHistory
                     ? "Saved on this Mac only, in Application Support. Scripts can contain credentials. "
                         + "Pinned entries don't count toward the limit."
                     : "History is kept in memory and forgotten when the app quits. Pinned entries are still saved.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let error = history.lastError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            Section {
                Button("Clear History…") { confirmClear = true }
                    .disabled(history.unpinnedEntries.isEmpty)
            }
        }
        .confirmationDialog("Clear the conversion history?", isPresented: $confirmClear) {
            Button("Clear History", role: .destructive) { InspectorModel.shared.clearHistory() }
        } message: {
            Text("Pinned entries are kept.")
        }
    }
}

private struct UpdateSettings: View {
    private var updates = Updates.shared

    var body: some View {
        SettingsPage {
            Section {
                LabeledContent("Version", value: "\(Branding.displayVersion) (\(Branding.build))")
                UpdateStatusView()
            }
            if updates.isAvailable {
                Section {
                    Toggle("Check for updates automatically", isOn: Binding(
                        get: { updates.automaticallyChecks },
                        set: { updates.automaticallyChecks = $0 }
                    ))
                }
            }
        }
        .onAppear { updates.checkInBackground() }
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
