// Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import FMClipboard
import Testing

@Suite struct ClipboardTests {
    let snippet = #"<?xml version="1.0" ?><fmxmlsnippet type="FMObjectList"><Step enable="True" id="93" name="Beep"/></fmxmlsnippet>"#

    @Test func flavorPasteboardTypes() {
        #expect(FMClipboard.Flavor.scriptSteps.pasteboardType.rawValue == "CorePasteboardFlavorType 0x584D5353")
        #expect(FMClipboard.Flavor.scripts.pasteboardType.rawValue == "CorePasteboardFlavorType 0x584D5343")
        #expect(FMClipboard.Flavor.customFunctions.pasteboardType.rawValue == "CorePasteboardFlavorType 0x584D464E")
    }

    @Test func validation() throws {
        #expect(try FMClipboard.validate(snippet) == .scriptSteps)
        #expect(throws: FMClipboard.InvalidXMLError.self) { try FMClipboard.validate("") }
        #expect(throws: FMClipboard.InvalidXMLError.self) {
            try FMClipboard.validate(#"<fmxmlsnippet type="FMObjectList"/>"#)
        }
        #expect(try FMClipboard.validate(#"<fmxmlsnippet type="FMObjectList"><Script name="x"></Script></fmxmlsnippet>"#) == .scripts)
        #expect(try FMClipboard.validate(#"<fmxmlsnippet type="FMObjectList"><!-- ERROR: x --><Step/></fmxmlsnippet>"#) == .scriptSteps)
    }

    @Test func roundTripOnAPrivatePasteboard() throws {
        let pb = NSPasteboard(name: .init("fmscript2xml-tests-\(UUID().uuidString)"))
        defer { pb.releaseGlobally() }
        FMClipboard.write(snippet, flavor: .scriptSteps, alsoAsText: true, to: pb)
        #expect(FMClipboard.flavors(on: pb) == [.scriptSteps])
        let read = try #require(FMClipboard.readXML(from: pb))
        #expect(read.xml == snippet)
        #expect(pb.data(forType: FMClipboard.Flavor.scriptSteps.pasteboardType) == Data(snippet.utf8))
        #expect(FMClipboard.text(from: pb) == snippet)
    }
}
