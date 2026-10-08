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

    /// Opens the inspector on an entry (or the newest conversion).
    func showInspector(selecting entryID: UUID? = nil) {
        let window = inspector ?? makeWindow(
            title: "Inspector",
            content: InspectorView(),
            size: NSSize(width: 1180, height: 720),
            resizable: true
        )
        window.setFrameAutosaveName("Inspector")
        window.minSize = NSSize(width: 900, height: 540)
        inspector = window
        InspectorModel.shared.show(entryID: entryID)
        present(window)
    }

    /// Opens the inspector on a new, empty draft.
    func showNewDraft() {
        showInspector()
        InspectorModel.shared.newScratch()
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
            // The window server image includes materials (the sidebar) that
            // cacheDisplay leaves blank; fall back to cacheDisplay.
            if let image = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.boundsIgnoreFraming]) {
                try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
            } else if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: url)
            }
            debugLog("inspector snapshot: \(url.path)")
        }
    }
    #endif

    func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: Branding.appName,
            .credits: NSAttributedString(
                attributedString: aboutCredits()
            ),
        ])
    }

    private func aboutCredits() -> NSAttributedString {
        let body: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
        let credits = NSMutableAttributedString(string: "\(Branding.pitch)\n\n", attributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor,
        ])
        credits.append(NSAttributedString(string: "Converter \(FMScriptKit.version)\n\(Branding.copyright)\nLicensed under ", attributes: body))
        var link = body
        link[.link] = Branding.licenseURL
        credits.append(NSAttributedString(string: Branding.license, attributes: link))
        credits.append(NSAttributedString(string: ".\n", attributes: body))
        link[.link] = Branding.repositoryURL
        credits.append(NSAttributedString(string: Branding.repositoryURL.absoluteString.replacingOccurrences(of: "https://", with: ""), attributes: link))
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        credits.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: credits.length))
        return credits
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
