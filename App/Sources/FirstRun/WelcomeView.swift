// Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
// SPDX-License-Identifier: GPL-3.0-or-later

import KeyboardShortcuts
import ServiceManagement
import SwiftUI

/// First-run window: explains the shortcut and offers launch at login.
struct WelcomeView: View {
    let onDone: () -> Void
    @State private var launchAtLogin = true

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading) {
                    Text(Branding.appName).font(.title.bold())
                    Text("Plain-text script steps in, FileMaker steps out.")
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                step(1, "Copy script steps as text (from an editor, a chat, a diff…).")
                step(2, "Press the shortcut. The clipboard now holds FileMaker steps.")
                step(3, "Paste into a script in FileMaker's Script Workspace.")
            }

            KeyboardShortcuts.Recorder("Shortcut:", name: .convertClipboard)

            Text("If a step can't be converted, the clipboard is left unchanged and a notification tells you which line to fix. The app lives in the menu bar.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Used the Automator Quick Action before? Turn its shortcut off in System Settings → Keyboard → Keyboard Shortcuts → Services, so the two don't collide.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Launch \(Branding.appName) at login", isOn: $launchAtLogin)

            HStack {
                Spacer()
                Button("Get Started") { finish() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(n)").font(.callout.monospacedDigit().bold()).foregroundStyle(.tint)
            Text(text)
        }
    }

    private func finish() {
        if launchAtLogin, SMAppService.mainApp.status != .enabled {
            try? SMAppService.mainApp.register()
        } else if !launchAtLogin, SMAppService.mainApp.status == .enabled {
            try? SMAppService.mainApp.unregister()
        }
        AppSettings.hasCompletedFirstRun = true
        Task { _ = await Notifications.shared.requestAuthorization() }
        onDone()
    }
}
