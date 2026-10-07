// Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// Reads and writes FileMaker objects on the macOS pasteboard.
///
/// FileMaker's clipboard "binary" format is just the `fmxmlsnippet` XML as
/// UTF-8, tagged with a four-char type code such as `XMSS` (script steps) under
/// the pasteboard type `CorePasteboardFlavorType 0x584D5353`. No AppleScript is
/// involved and FileMaker doesn't need to be installed (PLAN §1).
public enum FMClipboard {
    /// FileMaker object flavors, by four-char code.
    public enum Flavor: String, CaseIterable, Sendable {
        case scriptSteps = "XMSS"
        case scripts = "XMSC"
        case customFunctions = "XMFN"
        case fields = "XMFD"
        case baseTables = "XMTB"
        case valueLists = "XMVL"
        case layoutObjects = "XML2"

        /// e.g. `CorePasteboardFlavorType 0x584D5353` for XMSS.
        public var pasteboardType: NSPasteboard.PasteboardType {
            let hex = rawValue.utf8.map { String(format: "%02X", $0) }.joined()
            return NSPasteboard.PasteboardType("CorePasteboardFlavorType 0x\(hex)")
        }

        /// The flavor for the first element inside `<fmxmlsnippet>`.
        init?(elementName: String) {
            switch elementName {
            case "Step": self = .scriptSteps
            case "Script", "Group": self = .scripts
            case "CustomFunction": self = .customFunctions
            case "Field": self = .fields
            case "BaseTable": self = .baseTables
            case "ValueList": self = .valueLists
            case "Layout": self = .layoutObjects
            default: return nil
            }
        }
    }

    public struct InvalidXMLError: Error, CustomStringConvertible, Sendable {
        public let description: String
    }

    /// Checks that `xml` is an `fmxmlsnippet` FileMaker can paste, and returns
    /// its flavor (same rules as the Python `validate_fm_xml`).
    @discardableResult
    public static func validate(_ xml: String) throws(InvalidXMLError) -> Flavor {
        if xml.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw InvalidXMLError(description: "XML string is empty")
        }
        guard xml.contains("<fmxmlsnippet") else {
            throw InvalidXMLError(description: "XML must contain <fmxmlsnippet> element")
        }
        guard xml.contains("</fmxmlsnippet>") else {
            throw InvalidXMLError(description: "XML must have closing </fmxmlsnippet> tag")
        }
        guard xml.contains(#"type="FMObjectList""#) || xml.contains(#"type="LayoutObjectList""#) else {
            throw InvalidXMLError(description: #"fmxmlsnippet must have type="FMObjectList" or type="LayoutObjectList""#)
        }
        return try detectFlavor(xml)
    }

    /// The flavor of the first object inside `<fmxmlsnippet …>`.
    public static func detectFlavor(_ xml: String) throws(InvalidXMLError) -> Flavor {
        guard let open = xml.range(of: "<fmxmlsnippet"),
              let close = xml[open.upperBound...].firstIndex(of: ">")
        else { throw InvalidXMLError(description: "XML must be wrapped in <fmxmlsnippet> element") }
        var rest = xml[xml.index(after: close)...].drop { $0.isWhitespace }
        // Skip leading comments (e.g. <!-- ERROR: … -->)
        while rest.hasPrefix("<!--"), let end = rest.range(of: "-->") {
            rest = rest[end.upperBound...].drop { $0.isWhitespace }
        }
        guard rest.first == "<" else {
            throw InvalidXMLError(description: "Could not find FileMaker object element inside fmxmlsnippet")
        }
        let name = String(rest.dropFirst().prefix { $0.isLetter || $0.isNumber || $0 == "_" })
        guard let flavor = Flavor(elementName: name) else {
            throw InvalidXMLError(description: "Unknown FileMaker object type: '\(name)'. "
                + "Expected one of: Step, Script, Group, CustomFunction, Field, BaseTable, ValueList, Layout")
        }
        return flavor
    }

    /// Replaces the pasteboard contents with FileMaker objects.
    ///
    /// - Parameter alsoAsText: also write the XML as plain text, so pasting
    ///   outside FileMaker gives the XML (see PLAN §10, Phase 0).
    public static func write(
        _ xml: String,
        flavor: Flavor = .scriptSteps,
        alsoAsText: Bool = false,
        to pasteboard: NSPasteboard = .general
    ) {
        // NSPasteboardItem rejects the legacy flavor type (not a UTI), while
        // NSPasteboard maps it to its dynamic UTI (dyn.ah62d4rv4gk8zuxnxnq for XMSS).
        let types: [NSPasteboard.PasteboardType] = alsoAsText ? [flavor.pasteboardType, .string] : [flavor.pasteboardType]
        pasteboard.declareTypes(types, owner: nil)
        pasteboard.setData(Data(xml.utf8), forType: flavor.pasteboardType)
        if alsoAsText { pasteboard.setString(xml, forType: .string) }
    }

    /// Validates `xml` and writes it under its detected flavor.
    @discardableResult
    public static func writeValidated(_ xml: String, alsoAsText: Bool = false, to pasteboard: NSPasteboard = .general) throws(InvalidXMLError) -> Flavor {
        let flavor = try validate(xml)
        write(xml, flavor: flavor, alsoAsText: alsoAsText, to: pasteboard)
        return flavor
    }

    /// The pasteboard's plain text, if any.
    public static func text(from pasteboard: NSPasteboard = .general) -> String? {
        pasteboard.string(forType: .string)
    }

    /// The FileMaker flavors currently on the pasteboard.
    public static func flavors(on pasteboard: NSPasteboard = .general) -> [Flavor] {
        Flavor.allCases.filter { pasteboard.availableType(from: [$0.pasteboardType]) != nil }
    }

    /// The XML of the first FileMaker flavor on the pasteboard.
    public static func readXML(from pasteboard: NSPasteboard = .general) -> (flavor: Flavor, xml: String)? {
        for flavor in flavors(on: pasteboard) {
            if let data = pasteboard.data(forType: flavor.pasteboardType),
               let xml = String(data: data, encoding: .utf8) {
                return (flavor, xml)
            }
        }
        return nil
    }
}
