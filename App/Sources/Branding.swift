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
}
