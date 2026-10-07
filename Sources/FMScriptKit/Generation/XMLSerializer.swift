// Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
// SPDX-License-Identifier: GPL-3.0-or-later

/// Writes the `fmxmlsnippet` document byte-for-byte as the Python
/// implementation does.
///
/// Python builds an ElementTree, serializes it, wraps `<Calculation>` text in
/// CDATA, re-parses the result with minidom (expat) and pretty-prints it with
/// two-space indentation. When the re-parse or pretty-print fails (invalid
/// XML characters or element names, or `]]>` inside a calculation) it returns
/// the compact ElementTree serialization instead. Both paths are emulated here.
struct XMLSerializer {
    static let rootStartTag = #"<fmxmlsnippet type="FMObjectList">"#

    struct Output {
        var xml: String
        /// UTF-8 offsets of each top-level element in `xml`.
        var stepRanges: [Range<Int>]
    }

    static func serialize(_ steps: [XElement], errorComments: [String] = []) -> Output {
        let pretty = steps.allSatisfy(isWellFormed)
        var w = Writer()
        let comments = errorComments.map { "  <!-- ERROR: \($0) -->" }.joined(separator: "\n")

        if pretty {
            w.write(#"<?xml version="1.0" ?>"# + "\n")
            if steps.isEmpty {
                w.write(#"<fmxmlsnippet type="FMObjectList"/>"# + "\n")
            } else {
                w.write(rootStartTag)
                if !comments.isEmpty { w.write("\n" + comments) }
                w.write("\n")
                for step in steps {
                    w.write("  ")
                    let start = w.offset
                    writePretty(step, indent: "  ", to: &w)
                    w.ranges.append(start..<(w.offset - 1))  // without the trailing newline
                }
                w.write("</fmxmlsnippet>\n")
            }
        } else {
            if steps.isEmpty {
                w.write(#"<fmxmlsnippet type="FMObjectList" />"#)
            } else {
                w.write(rootStartTag)
                if !comments.isEmpty { w.write("\n" + comments) }
                for step in steps {
                    let start = w.offset
                    writeCompact(step, to: &w)
                    w.ranges.append(start..<w.offset)
                }
                w.write("</fmxmlsnippet>")
            }
        }
        return Output(xml: w.out, stepRanges: w.ranges)
    }

    private struct Writer {
        var out = ""
        var offset = 0
        var ranges: [Range<Int>] = []

        mutating func write(_ s: String) {
            out += s
            offset += s.utf8.count
        }
    }

    // MARK: minidom toprettyxml(indent="  ")

    private static func writePretty(_ e: XElement, indent: String, to w: inout Writer) {
        w.write("<" + e.name)
        for a in e.attributes {
            w.write(" \(a.name)=\"\(minidomEscape(a.value))\"")
        }
        let text = e.text ?? ""
        let hasText = !text.isEmpty
        if !hasText && e.children.isEmpty {
            w.write("/>\n")
            return
        }
        w.write(">")
        if hasText && e.children.isEmpty {
            w.write(textNode(e, text))
        } else {
            w.write("\n")
            let inner = indent + "  "
            if hasText { w.write(minidomEscape(inner + normalizeNewlines(text) + "\n")) }
            for child in e.children {
                w.write(inner)
                writePretty(child, indent: inner, to: &w)
            }
            w.write(indent)
        }
        w.write("</\(e.name)>\n")
    }

    private static func textNode(_ e: XElement, _ text: String) -> String {
        e.name == "Calculation"
            ? "<![CDATA[\(normalizeNewlines(text))]]>"
            : minidomEscape(normalizeNewlines(text))
    }

    /// minidom `_write_data`: & < " > (raw tabs and newlines are kept).
    private static func minidomEscape(_ s: String) -> String {
        guard s.unicodeScalars.contains(where: { $0 == "&" || $0 == "<" || $0 == "\"" || $0 == ">" }) else { return s }
        return s.pyReplace("&", "&amp;").pyReplace("<", "&lt;").pyReplace("\"", "&quot;").pyReplace(">", "&gt;")
    }

    /// expat end-of-line handling: "\r\n" and "\r" become "\n".
    private static func normalizeNewlines(_ s: String) -> String {
        guard s.unicodeScalars.contains("\r") else { return s }
        return s.pyReplace("\r\n", "\n").pyReplace("\r", "\n")
    }

    // MARK: ElementTree tostring (fallback)

    private static func writeCompact(_ e: XElement, to w: inout Writer) {
        w.write("<" + e.name)
        for a in e.attributes {
            w.write(" \(a.name)=\"\(etEscapeAttribute(a.value))\"")
        }
        let text = e.text ?? ""
        if text.isEmpty && e.children.isEmpty {
            w.write(" />")
            return
        }
        w.write(">")
        if !text.isEmpty {
            w.write(e.name == "Calculation" && e.children.isEmpty ? "<![CDATA[\(text)]]>" : etEscapeText(text))
        }
        for child in e.children { writeCompact(child, to: &w) }
        w.write("</\(e.name)>")
    }

    private static func etEscapeText(_ s: String) -> String {
        s.pyReplace("&", "&amp;").pyReplace("<", "&lt;").pyReplace(">", "&gt;")
    }

    private static func etEscapeAttribute(_ s: String) -> String {
        etEscapeText(s).pyReplace("\"", "&quot;")
            .pyReplace("\r", "&#13;").pyReplace("\n", "&#10;").pyReplace("\t", "&#09;")
    }

    // MARK: Would expat (namespace-aware) accept it?

    static func isWellFormed(_ e: XElement) -> Bool {
        guard isXMLName(e.name) else { return false }
        for a in e.attributes where !isXMLName(a.name) || !isXMLText(a.value) { return false }
        if let text = e.text {
            guard isXMLText(text) else { return false }
            if e.name == "Calculation" && e.children.isEmpty && !text.isEmpty && text.pyContains("]]>") { return false }
        }
        return e.children.allSatisfy(isWellFormed)
    }

    /// XML 1.0 `Char`.
    private static func isXMLText(_ s: String) -> Bool {
        s.unicodeScalars.allSatisfy { c in
            switch c.value {
            case 0x9, 0xA, 0xD, 0x20...0xD7FF, 0xE000...0xFFFD, 0x10000...0x10FFFF: return true
            default: return false
            }
        }
    }

    /// XML 1.0 `Name` without colons (namespace processing rejects unbound prefixes).
    private static func isXMLName(_ s: String) -> Bool {
        guard let first = s.unicodeScalars.first, isNameStart(first) else { return false }
        return s.unicodeScalars.dropFirst().allSatisfy(isNameChar)
    }

    private static func isNameStart(_ c: Unicode.Scalar) -> Bool {
        switch c.value {
        case 0x41...0x5A, 0x61...0x7A, 0x5F,
             0xC0...0xD6, 0xD8...0xF6, 0xF8...0x2FF, 0x370...0x37D, 0x37F...0x1FFF,
             0x200C...0x200D, 0x2070...0x218F, 0x2C00...0x2FEF, 0x3001...0xD7FF,
             0xF900...0xFDCF, 0xFDF0...0xFFFD, 0x10000...0xEFFFF:
            return true
        default:
            return false
        }
    }

    private static func isNameChar(_ c: Unicode.Scalar) -> Bool {
        if isNameStart(c) { return true }
        switch c.value {
        case 0x2D, 0x2E, 0x30...0x39, 0xB7, 0x300...0x36F, 0x203F...0x2040: return true
        default: return false
        }
    }
}
