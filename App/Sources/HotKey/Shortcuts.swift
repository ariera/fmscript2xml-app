// Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
// SPDX-License-Identifier: GPL-3.0-or-later

import KeyboardShortcuts

// Global shortcuts (D3). KeyboardShortcuts uses Carbon RegisterEventHotKey,
// so no Accessibility permission is needed.
extension KeyboardShortcuts.Name {
    /// Convert the clipboard; default ⌃⌥⌘F.
    static let convertClipboard = Self("convertClipboard", default: .init(.f, modifiers: [.control, .option, .command]))
    /// Open the inspector. Off by default; turning it on in Settings uses
    /// ⌃⌥⇧⌘F unless another shortcut is recorded.
    static let openInspector = Self("openInspector")
}

@MainActor
enum InspectorShortcut {
    static let defaultShortcut = KeyboardShortcuts.Shortcut(.f, modifiers: [.control, .option, .shift, .command])

    static func apply(enabled: Bool) {
        if enabled {
            if KeyboardShortcuts.getShortcut(for: .openInspector) == nil {
                KeyboardShortcuts.setShortcut(defaultShortcut, for: .openInspector)
            }
            KeyboardShortcuts.enable(.openInspector)
        } else {
            KeyboardShortcuts.disable(.openInspector)
        }
    }
}
