// Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import FMScriptKit
import SwiftUI

/// The About window: sized to its text, so nothing scrolls.
struct AboutView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            VStack(spacing: 4) {
                Text(Branding.appName).font(.title2.bold())
                Text("Version \(Branding.displayVersion) (\(Branding.build))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Text(Branding.pitch)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            VStack(spacing: 4) {
                Group {
                    Text("Converter \(FMScriptKit.version)")
                    Text(Branding.copyright)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Text("Licensed under").foregroundStyle(.secondary)
                    Link(Branding.license, destination: Branding.licenseURL)
                }
                Link("github.com/ariera/fmscript2xml-app", destination: Branding.repositoryURL)
            }
            .font(.caption)
        }
        .padding(.horizontal, 28)
        .padding(.top, 20)
        .padding(.bottom, 24)
        .frame(width: 400)
    }
}
