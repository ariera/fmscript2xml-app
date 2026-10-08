// Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import FMScriptKit
import SwiftUI

/// AppKit-managed windows. A menu bar app has no always-present SwiftUI
/// scene to call `openWindow` from (notification actions, hotkeys), so the
/// welcome and inspector windows are opened here.
@MainActor
final class WindowManager {
    static let shared = WindowManager()

    private var welcome: NSWindow?
    private var inspector: NSWindow?

    func showWelcome() {
        let window = welcome ?? makeWindow(
            title: "Welcome to \(Branding.appName)",
            content: WelcomeView { [weak self] in self?.welcome?.close() },
            size: NSSize(width: 520, height: 470)
        )
        welcome = window
        present(window)
    }

    func showInspector() {
        let window = inspector ?? makeWindow(
            title: "Last Conversion",
            content: InspectorView(),
            size: NSSize(width: 980, height: 640),
            resizable: true
        )
        window.setFrameAutosaveName("Inspector")
        inspector = window
        present(window)
    }

    #if DEBUG
    /// Opens the inspector, optionally resizes it, and writes its contents to a PNG.
    func snapshotInspector(to url: URL, size: NSSize = NSSize(width: 1600, height: 900)) {
        showInspector()
        guard let window = inspector, let view = window.contentView else { return }
        window.setContentSize(size)
        view.layoutSubtreeIfNeeded()
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
            debugLog("inspector snapshot: \(url.path)")
        }
    }
    #endif

    func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: Branding.appName,
            .credits: NSAttributedString(
                string: "\(Branding.pitch)\n\n\(Branding.copyright)\nLicensed under \(Branding.license).\n"
                    + "Converter \(FMScriptKit.version)\n\(Branding.repositoryURL.absoluteString)",
                attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
            ),
        ])
    }

    private func makeWindow(title: String, content: some View, size: NSSize, resizable: Bool = false) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: resizable ? [.titled, .closable, .miniaturizable, .resizable] : [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.contentViewController = NSHostingController(rootView: content)
        window.setContentSize(size)
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    private func present(_ window: NSWindow) {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
