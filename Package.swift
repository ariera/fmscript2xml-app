// swift-tools-version: 6.0
// Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
// SPDX-License-Identifier: GPL-3.0-or-later

import PackageDescription

let package = Package(
    name: "fmscript2xml",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FMScriptKit", targets: ["FMScriptKit"]),
        .library(name: "FMClipboard", targets: ["FMClipboard"]),
        .executable(name: "fmscript2xml", targets: ["fmscript2xml"]),
    ],
    targets: [
        // The converter. Pure Swift: no AppKit/SwiftUI (CLAUDE.md).
        .target(
            name: "FMScriptKit",
            resources: [
                .copy("Resources/steps.json"),
                .copy("Resources/html-entities.json"),
            ]
        ),
        // NSPasteboard read/write for FileMaker clipboard flavors.
        .target(name: "FMClipboard"),
        // Swift CLI, drop-in for the Python `fmscript2xml` CLI.
        .executableTarget(
            name: "fmscript2xml",
            dependencies: ["FMScriptKit", "FMClipboard"]
        ),
        // Phase 0 spike: put an fmxmlsnippet file on the clipboard as XMSS.
        .executableTarget(
            name: "spike-paste",
            dependencies: ["FMClipboard"]
        ),
        .testTarget(
            name: "FMScriptKitTests",
            dependencies: ["FMScriptKit", "FMClipboard"]
        ),
        .testTarget(
            name: "ConformanceTests",
            dependencies: ["FMScriptKit"],
            resources: [.copy("Resources/requires-db-ids.json")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
