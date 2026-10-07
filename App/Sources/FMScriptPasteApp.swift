// Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
// SPDX-License-Identifier: GPL-3.0-or-later

import FMScriptKit
import KeyboardShortcuts
import SwiftUI

@main
struct FMScriptPasteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
        } label: {
            // Template image: macOS tints it for light/dark menu bars
            Image("MenuBarIcon")
                .accessibilityLabel(Branding.appName)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        KeyboardShortcuts.onKeyUp(for: .convertClipboard) {
            Task { @MainActor in AppModel.shared.convertClipboard() }
        }
        KeyboardShortcuts.onKeyUp(for: .openInspector) {
            Task { @MainActor in WindowManager.shared.showInspector() }
        }
        Notifications.shared.configure()
        if !AppSettings.hasCompletedFirstRun {
            WindowManager.shared.showWelcome()
        }
        #if DEBUG
        // Lets scripts trigger a conversion without the hotkey
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("\(Branding.bundleIdentifier).debug.convert"), object: nil, queue: .main
        ) { _ in
            Task { @MainActor in AppModel.shared.convertClipboard() }
        }
        #endif
    }
}

/// The menu bar menu.
struct MenuContent: View {
    @Environment(\.openSettings) private var openSettings
    private var model = AppModel.shared

    var body: some View {
        Button("Convert Clipboard") { model.convertClipboard() }
        if let shortcut = KeyboardShortcuts.getShortcut(for: .convertClipboard) {
            Text("Shortcut: \(shortcut.description)")
        }

        Divider()

        if let last = model.lastRecord {
            Text(last.menuSummary)
            Button("Show Last Conversion…") { WindowManager.shared.showInspector() }
        } else {
            Text("No conversions yet")
        }

        Divider()

        Button("Settings…") {
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")
        Button("Welcome Guide…") { WindowManager.shared.showWelcome() }
        Button("About \(Branding.appName)") { WindowManager.shared.showAbout() }

        Divider()

        Button("Quit \(Branding.appName)") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
