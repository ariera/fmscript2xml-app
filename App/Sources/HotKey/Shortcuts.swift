// Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
// SPDX-License-Identifier: GPL-3.0-or-later

import KeyboardShortcuts

// Global shortcuts (D3). KeyboardShortcuts uses Carbon RegisterEventHotKey,
// so no Accessibility permission is needed.
extension KeyboardShortcuts.Name {
    /// Convert the clipboard; default ⌃⌥⌘F.
    static let convertClipboard = Self("convertClipboard", default: .init(.f, modifiers: [.control, .option, .command]))
    /// Open the inspector; no default.
    static let openInspector = Self("openInspector")
}
