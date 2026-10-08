// Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// The update state for Settings and About: checking, up to date, or an
/// "Install Update…" button that opens Sparkle's update window.
struct UpdateStatusView: View {
    private var updates = Updates.shared

    var body: some View {
        if updates.isAvailable {
            HStack(spacing: 8) {
                switch updates.status {
                case .idle, .checking:
                    ProgressView().controlSize(.small)
                    Text("Checking for updates…").foregroundStyle(.secondary)
                case .upToDate:
                    Label("Up to date", systemImage: "checkmark.circle").foregroundStyle(.secondary)
                    Button("Check Again") { updates.checkInBackground() }
                        .controlSize(.small)
                        .disabled(!updates.canCheckForUpdates)
                case .available(let version):
                    Label("Version \(version) is available", systemImage: "arrow.down.circle.fill")
                        .foregroundStyle(.tint)
                    Button("Install Update…") { updates.checkForUpdates() }
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                        .disabled(!updates.canCheckForUpdates)
                case .failed(let message):
                    Label("Couldn't check for updates", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                        .help(message)
                    Button("Try Again") { updates.checkInBackground() }
                        .controlSize(.small)
                        .disabled(!updates.canCheckForUpdates)
                }
            }
            .font(.callout)
        } else {
            Text("Updates are off in this build.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
