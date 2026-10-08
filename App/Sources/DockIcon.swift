// Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// Shows or hides the Dock icon. The app is LSUIElement (menu bar only) by
/// default; "Show in Dock" switches it to a regular app.
@MainActor
enum DockIcon {
    static func apply(show: Bool) {
        let policy: NSApplication.ActivationPolicy = show ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        if !show {
            // Leaving the Dock deactivates the app; keep open windows in front
            DispatchQueue.main.async { NSApp.activate() }
        }
    }
}
