// Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
// SPDX-License-Identifier: GPL-3.0-or-later

import FMHistory
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
        // tools/release.sh launches the built app with -FMSPSmokeTest YES to
        // check that it starts (all frameworks load), then expects it to quit.
        if UserDefaults.standard.bool(forKey: "FMSPSmokeTest") {
            FileHandle.standardOutput.write(Data("smoke test: ok \(Branding.displayVersion) (\(Branding.build))\n".utf8))
            exit(0)
        }
        DockIcon.apply(show: AppSettings.showInDock)
        KeyboardShortcuts.onKeyUp(for: .convertClipboard) {
            Task { @MainActor in AppModel.shared.convertClipboard() }
        }
        KeyboardShortcuts.onKeyUp(for: .openInspector) {
            Task { @MainActor in WindowManager.shared.showInspector() }
        }
        InspectorShortcut.apply(enabled: AppSettings.inspectorShortcutEnabled)
        Notifications.shared.configure()
        Updates.shared.start()
        if !AppSettings.hasCompletedFirstRun {
            WindowManager.shared.showWelcome()
        }
        #if DEBUG
        // Let scripts drive the app without the hotkey. A channel
        // (-FMSPDebugChannel <name>) keeps a test instance from reacting to
        // triggers meant for another one, and vice versa.
        let channel = UserDefaults.standard.string(forKey: "FMSPDebugChannel").map { ".\($0)" } ?? ""
        func debugName(_ hook: String) -> Notification.Name {
            Notification.Name("\(Branding.bundleIdentifier).debug\(channel).\(hook)")
        }
        DistributedNotificationCenter.default().addObserver(
            forName: debugName("convert"), object: nil, queue: .main
        ) { _ in
            Task { @MainActor in AppModel.shared.convertClipboard() }
        }
        DistributedNotificationCenter.default().addObserver(
            forName: debugName("snapshotInspector"), object: nil, queue: .main
        ) { note in
            let path = note.object as? String ?? NSTemporaryDirectory() + "inspector.png"
            Task { @MainActor in WindowManager.shared.snapshotInspector(to: URL(filePath: path)) }
        }
        DistributedNotificationCenter.default().addObserver(
            forName: debugName("inspector"), object: nil, queue: .main
        ) { note in
            let command = note.object as? String ?? ""
            Task { @MainActor in InspectorModel.shared.debugCommand(command) }
        }
        DistributedNotificationCenter.default().addObserver(
            forName: debugName("snapshotAbout"), object: nil, queue: .main
        ) { note in
            let path = note.object as? String ?? NSTemporaryDirectory() + "about.png"
            Task { @MainActor in WindowManager.shared.snapshotAbout(to: URL(filePath: path)) }
        }
        DistributedNotificationCenter.default().addObserver(
            forName: debugName("snapshotSettings"), object: nil, queue: .main
        ) { note in
            let path = note.object as? String ?? NSTemporaryDirectory() + "settings.png"
            Task { @MainActor in
                // The Settings scene can only be opened from SwiftUI, so host
                // the same view in a plain window for the snapshot
                let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
                window.title = "Settings"
                window.makeKeyAndOrderFront(nil)
                NSApp.activate()
                try? await Task.sleep(for: .milliseconds(800))
                defer { window.close() }
                if let image = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.bestResolution]) {
                    try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: URL(filePath: path))
                    debugLog("settings snapshot: \(path)")
                }
            }
        }
        #endif
    }

    /// Clicking the Dock icon (when shown) opens the inspector.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { WindowManager.shared.showInspector() }
        return true
    }

    /// Closing the last window never quits a menu bar app.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

/// The menu bar menu.
struct MenuContent: View {
    @Environment(\.openSettings) private var openSettings
    private var model = AppModel.shared
    private static let recentCount = 8

    var body: some View {
        Button("Convert Clipboard") { model.convertClipboard() }
        if let shortcut = KeyboardShortcuts.getShortcut(for: .convertClipboard) {
            Text("Shortcut: \(shortcut.description)")
        }

        Divider()

        let pinned = model.history.pinnedEntries.prefix(Self.recentCount)
        if !pinned.isEmpty {
            Text("Pinned")
            ForEach(pinned) { entry in entryButton(entry) }
        }
        if model.history.capacity > 0 {
            let recent = model.history.unpinnedEntries.prefix(Self.recentCount)
            if recent.isEmpty && pinned.isEmpty {
                Text("No conversions yet")
            } else if !recent.isEmpty {
                Text("Recent — click to copy again")
                ForEach(recent) { entry in entryButton(entry) }
            }
        } else if let last = model.lastEntry, !last.isPinned {
            Button {
                model.activate(last)
            } label: {
                Image(systemName: last.status.symbol)
                Text("Last: \(last.shortTitle(maxLength: 40))")
            }
        }

        Button("Inspector…") { WindowManager.shared.showInspector() }
        Button("New Draft…") { WindowManager.shared.showNewDraft() }

        Divider()

        Button("Settings…") {
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")
        if Updates.shared.isAvailable {
            Button("Check for Updates…") { Updates.shared.checkForUpdates() }
        }
        Button("Welcome Guide…") { WindowManager.shared.showWelcome() }
        Button("About \(Branding.appName)") { WindowManager.shared.showAbout() }

        Divider()

        Button("Quit \(Branding.appName)") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func entryButton(_ entry: HistoryEntry) -> some View {
        Button {
            model.activate(entry)
        } label: {
            Image(systemName: entry.status.symbol)
            Text("\(entry.shortTitle(maxLength: 40))  ·  \(entry.date.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated)))")
        }
    }
}
