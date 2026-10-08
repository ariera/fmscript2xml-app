// Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The app's name and identifiers, defined in one place (D15, D16).
/// The bundle identifier itself is set in App/project.yml.
enum Branding {
    static let appName = "FM Script Paste"
    static let bundleIdentifier = "io.github.ariera.fmscriptpaste"
    static let copyright = "Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera."
    static let license = "GPL-3.0-or-later"
    static let repositoryURL = URL(string: "https://github.com/ariera/fmscript2xml-app")!
    static let licenseURL = URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")!

    /// Why the app exists, for the About window (the README has a longer version).
    static let pitch = "FileMaker can't paste script steps written as text. Until now, every line had to be "
        + "retyped by hand in the Script Workspace: slow and error-prone. \(appName) converts the text "
        + "in a fraction of a second. Copy it, press the shortcut, paste into FileMaker."
}
