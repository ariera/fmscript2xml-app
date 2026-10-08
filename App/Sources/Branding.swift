// Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The app's name and identifiers, defined in one place (D15, D16).
/// The bundle identifier itself is set in App/project.yml.
enum Branding {
    static let appName = "fmscript2xml"
    static let bundleIdentifier = "io.github.ariera.fmscriptpaste"
    static let copyright = "Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera."
    static let license = "GPL-3.0-or-later"
    static let repositoryURL = URL(string: "https://github.com/ariera/fmscript2xml-app")!
    static let licenseURL = URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")!

    /// CFBundleShortVersionString, e.g. "0.1.0".
    static var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0" }
    /// CFBundleVersion (the build number).
    static var build: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0" }

    /// The version people see. Every 0.x release is a beta: "0.1 beta",
    /// "0.1.2 beta". From 1.0 on: the plain version.
    static var displayVersion: String { displayVersion(for: version) }

    static func displayVersion(for version: String) -> String {
        let parts = version.split(separator: ".").map { Int($0) ?? 0 }
        guard parts.first == 0 else { return version }
        let minor = parts.count > 1 ? parts[1] : 0
        let patch = parts.count > 2 ? parts[2] : 0
        return patch == 0 ? "0.\(minor) beta" : "0.\(minor).\(patch) beta"
    }

    /// Why the app exists, for the About window (the README has a longer version).
    static let pitch = "FileMaker can't paste script steps written as text. Until now, every line had to be "
        + "retyped by hand in the Script Workspace: slow and error-prone. \(appName) converts the text "
        + "in a fraction of a second. Copy it, press the shortcut, paste into FileMaker."
}
