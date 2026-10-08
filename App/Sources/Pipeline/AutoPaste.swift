// Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import ApplicationServices

/// Optional ⌘V after converting (PLAN §4 step 7). Posting key events needs
/// Accessibility permission, requested only when the setting is turned on.
@MainActor
enum AutoPaste {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that leads to Privacy & Security → Accessibility.
    static func requestTrust() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    /// Waits until the shortcut's modifier keys are released (so the paste
    /// isn't ⌃⌥⌘V), then sends ⌘V to the frontmost app.
    static func pasteWhenKeysReleased() {
        guard isTrusted else {
            Feedback.shared.show(.warning("Auto-paste needs Accessibility permission"))
            return
        }
        Task {
            let modifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
            for _ in 0..<40 where !CGEventSource.flagsState(.combinedSessionState).intersection(modifiers).isEmpty {
                try? await Task.sleep(for: .milliseconds(25))
            }
            try? await Task.sleep(for: .milliseconds(30))
            let source = CGEventSource(stateID: .hidSystemState)
            let vKey: CGKeyCode = 9
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: down)
                event?.flags = .maskCommand
                event?.post(tap: .cghidEventTap)
            }
        }
    }
}
