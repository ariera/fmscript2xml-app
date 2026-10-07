// Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
// SPDX-License-Identifier: GPL-3.0-or-later

// Phase 0 spike: put an fmxmlsnippet file on the clipboard as FileMaker objects.
//
//   swift run spike-paste <file.xml> [--with-text] [--flavor XMSS]
//   swift run spike-paste --read      # show what's on the clipboard

import AppKit
import FMClipboard

func usage() -> Never {
    print("""
    usage: spike-paste <file.xml> [--with-text] [--flavor XMSS|XMSC|XMFN|...]
           spike-paste --read
    """)
    exit(2)
}

func describePasteboard() {
    let pb = NSPasteboard.general
    print("Pasteboard types:")
    for t in pb.types ?? [] {
        let size = pb.data(forType: t)?.count ?? 0
        print("  \(t.rawValue)  (\(size) bytes)")
    }
    if let (flavor, xml) = FMClipboard.readXML(from: pb) {
        print("\nFileMaker \(flavor.rawValue) XML:\n\(xml)")
    }
}

var args = Array(CommandLine.arguments.dropFirst())
if args == ["--read"] {
    describePasteboard()
    exit(0)
}

let withText = args.contains("--with-text")
args.removeAll { $0 == "--with-text" }
var forcedFlavor: FMClipboard.Flavor?
if let i = args.firstIndex(of: "--flavor") {
    guard i + 1 < args.count, let f = FMClipboard.Flavor(rawValue: args[i + 1]) else { usage() }
    forcedFlavor = f
    args.removeSubrange(i...(i + 1))
}
guard args.count == 1 else { usage() }

let path = args[0]
guard let xml = try? String(contentsOfFile: path, encoding: .utf8) else {
    print("error: can't read \(path)")
    exit(1)
}
do {
    let detected = try FMClipboard.validate(xml)
    let flavor = forcedFlavor ?? detected
    FMClipboard.write(xml, flavor: flavor, alsoAsText: withText)
    print("Wrote \(xml.utf8.count) bytes as \(flavor.rawValue)\(withText ? " + plain text" : "").")
    print("Now paste into FileMaker (e.g. the Script Workspace).\n")
    describePasteboard()
} catch {
    print("error: \(error)")
    exit(1)
}
