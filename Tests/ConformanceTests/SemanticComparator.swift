// Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
// SPDX-License-Identifier: GPL-3.0-or-later

// Port of the Python test suite's semantic XML comparator
// (tests/utils/semantic_comparator.py and xml_normalizer.py).
//
// It ignores formatting, helper comments, PlatformData, and database IDs for
// steps that don't require them, and compares FileMaker's Script/ObjectList
// export format against fmxmlsnippet output by the fields that matter.

import Foundation

/// An ElementTree-like node: tag, attributes, text before the first child.
final class Node {
    var tag: String
    var attrib: [String: String]
    var text: String?
    var children: [Node]

    init(tag: String, attrib: [String: String] = [:], text: String? = nil, children: [Node] = []) {
        self.tag = tag
        self.attrib = attrib
        self.text = text
        self.children = children
    }

    static func parse(_ xml: String) throws -> Node {
        let doc = try XMLDocument(xmlString: xml, options: [])
        guard let root = doc.rootElement() else { throw CocoaError(.fileReadCorruptFile) }
        return Node(root)
    }

    private convenience init(_ e: XMLElement) {
        var attrib: [String: String] = [:]
        for a in e.attributes ?? [] { attrib[a.name ?? ""] = a.stringValue ?? "" }
        var text: String?
        var children: [Node] = []
        for child in e.children ?? [] {
            switch child.kind {
            case .element:
                children.append(Node(child as! XMLElement))
            case .text where children.isEmpty:
                text = (text ?? "") + (child.stringValue ?? "")
            default:
                break  // Comments and processing instructions are dropped, as in ElementTree
            }
        }
        self.init(tag: e.name ?? "", attrib: attrib, text: text, children: children)
    }

    func copy() -> Node {
        Node(tag: tag, attrib: attrib, text: text, children: children.map { $0.copy() })
    }

    /// All nodes in document order, self first.
    var iter: [Node] { [self] + children.flatMap(\.iter) }

    var descendants: [Node] { children.flatMap(\.iter) }

    func child(_ tag: String) -> Node? { children.first { $0.tag == tag } }

    /// `.//Parameter[@type='<type>']//<tag>`
    func findInParameter(type: String, tag: String) -> Node? {
        for p in descendants where p.tag == "Parameter" && p.attrib["type"] == type {
            if let found = p.descendants.first(where: { $0.tag == tag }) { return found }
        }
        return nil
    }
}

struct ComparisonResult {
    var missingSteps: [String] = []
    var extraSteps: [String] = []
    var stepDifferences: [(index: Int, expected: String, generated: String, differences: [String])] = []

    var isEqual: Bool { missingSteps.isEmpty && extraSteps.isEmpty && stepDifferences.isEmpty }

    var formatted: String {
        var lines: [String] = []
        if !missingSteps.isEmpty { lines.append("Missing steps:"); lines += missingSteps.map { "  - \($0)" } }
        if !extraSteps.isEmpty { lines.append("Extra steps:"); lines += extraSteps.map { "  - \($0)" } }
        for d in stepDifferences {
            lines.append("Step \(d.index): expected='\(d.expected)' generated='\(d.generated)'")
            lines += d.differences.map { "  - \($0)" }
        }
        return lines.joined(separator: "\n")
    }
}

enum SemanticComparator {
    /// Step id → whether the step needs database IDs (from the DDR IR docs).
    static let requiresDBIDs: [Int: Bool] = {
        guard let url = Bundle.module.url(forResource: "requires-db-ids", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let map = try? JSONDecoder().decode([String: Bool].self, from: data)
        else { return [:] }
        return Dictionary(uniqueKeysWithValues: map.map { (Int($0.key)!, $0.value) })
    }()

    static func compare(expected expectedXML: String, generated generatedXML: String) throws -> ComparisonResult {
        let expectedRoot = try Node.parse(expectedXML)
        let generatedRoot = try Node.parse(generatedXML)

        for root in [expectedRoot, generatedRoot] {
            removeHelperComments(root)
            removePlatformData(root)
            normalizeWhitespace(root)
        }

        var expectedSteps = extractSteps(expectedRoot)
        var generatedSteps = extractSteps(generatedRoot)

        // Comment steps differ between the Script/ObjectList export and the
        // sanitized text input
        if expectedRoot.tag == "Script" && generatedRoot.tag == "fmxmlsnippet" {
            expectedSteps = expectedSteps.filter { normalizeStepName($0.attrib["name"] ?? "") != "Comment" }
            generatedSteps = generatedSteps.filter { normalizeStepName($0.attrib["name"] ?? "") != "Comment" }
        }

        var result = ComparisonResult()
        if expectedSteps.count < generatedSteps.count {
            for i in expectedSteps.count..<generatedSteps.count { result.extraSteps.append(label(generatedSteps[i], i)) }
        } else if expectedSteps.count > generatedSteps.count {
            for i in generatedSteps.count..<expectedSteps.count { result.missingSteps.append(label(expectedSteps[i], i)) }
        }

        for i in 0..<min(expectedSteps.count, generatedSteps.count) {
            let requires = Int(expectedSteps[i].attrib["id"] ?? "").flatMap { requiresDBIDs[$0] } ?? true
            let (en, gn, diffs) = compareSteps(expectedSteps[i], generatedSteps[i], requiresDBIDs: requires)
            if !diffs.isEmpty { result.stepDifferences.append((i, en, gn, diffs)) }
        }
        return result
    }

    static func compareSteps(_ expectedStep: Node, _ generatedStep: Node, requiresDBIDs: Bool) -> (String, String, [String]) {
        let expected = expectedStep.copy()
        let generated = generatedStep.copy()
        expected.attrib["hash"] = nil
        generated.attrib["hash"] = nil
        if !requiresDBIDs {
            for n in expected.iter + generated.iter where n.tag != "Step" { n.attrib["id"] = nil }
        }
        normalizeWhitespace(expected)
        normalizeWhitespace(generated)

        let expectedName = normalizeStepName(expected.attrib["name"] ?? "")
        let generatedName = normalizeStepName(generated.attrib["name"] ?? "")
        var diffs: [String] = []

        if expected.child("ParameterValues") != nil || expected.child("Options") != nil {
            diffs += compareScriptStep(expected, generated)
        } else {
            for attr in ["name", "id", "enable"] {
                let e = attr == "name" ? expectedName : expected.attrib[attr]
                let g = attr == "name" ? generatedName : generated.attrib[attr]
                if e != g { diffs.append("Attribute mismatch '\(attr)': expected='\(e ?? "None")' generated='\(g ?? "None")'") }
            }
            compareElements(expected, generated, &diffs, path: "Step")
        }
        return (expectedName, generatedName, diffs)
    }

    private static func compareElements(_ e: Node, _ g: Node, _ diffs: inout [String], path: String) {
        if e.tag != g.tag {
            diffs.append("\(path): tag mismatch expected='\(e.tag)' generated='\(g.tag)'")
            return
        }
        if (e.text ?? "") != (g.text ?? "") {
            diffs.append("\(path): text mismatch expected='\(shorten(e.text))' generated='\(shorten(g.text))'")
        }
        if e.attrib != g.attrib {
            diffs.append("\(path): attributes mismatch expected=\(e.attrib) generated=\(g.attrib)")
        }
        if e.children.count != g.children.count {
            diffs.append("\(path): child count mismatch expected=\(e.children.count) generated=\(g.children.count)")
        }
        for i in 0..<min(e.children.count, g.children.count) {
            compareElements(e.children[i], g.children[i], &diffs, path: "\(path)/\(e.children[i].tag)[\(i)]")
        }
    }

    /// Script/ObjectList step vs fmxmlsnippet step.
    private static func compareScriptStep(_ expected: Node, _ generated: Node) -> [String] {
        var diffs: [String] = []
        for attr in ["name", "id", "enable"] {
            var e = expected.attrib[attr]
            var g = generated.attrib[attr]
            if attr == "name" {
                e = normalizeStepName(e ?? "")
                g = normalizeStepName(g ?? "")
            }
            if e != g { diffs.append("Attribute mismatch '\(attr)': expected='\(e ?? "None")' generated='\(g ?? "None")'") }
        }

        // FieldReference vs Field
        if let ef = expected.findInParameter(type: "FieldReference", tag: "FieldReference"),
           let gf = generated.child("Field") {
            var expectedName = ef.attrib["name"]
            let expectedTable = ef.child("TableOccurrenceReference")
            if let table = expectedTable?.attrib["name"], !table.isEmpty, let n = expectedName, !n.isEmpty {
                expectedName = "\(table)::\(n)"
            }
            var generatedName = gf.attrib["name"]
            if let table = gf.attrib["table"], !table.isEmpty, let n = generatedName, !n.isEmpty {
                generatedName = "\(table)::\(n)"
            }
            // Tolerate broken-reference placeholders
            if (expectedName ?? "").isEmpty, let expectedTable {
                let tableName = expectedTable.attrib["name"] ?? ""
                if tableName.contains("Table Missing") || (generatedName ?? "").contains("Table Missing")
                    || (generatedName ?? "").contains("BROKEN REFERENCE") {
                    expectedName = generatedName
                }
            }
            if expectedName != generatedName {
                diffs.append("Field name mismatch expected='\(expectedName ?? "None")' generated='\(generatedName ?? "None")'")
            }
        }

        // Calculation text
        if let ec = expected.findInParameter(type: "Calculation", tag: "Text") {
            let gc = generated.descendants.first { $0.tag == "Interval" }.flatMap { $0.child("Calculation") }
                ?? generated.descendants.first { $0.tag == "Calculation" }
            if let gc {
                let e = (ec.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let g = (gc.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if e != g { diffs.append("Calculation mismatch expected='\(shorten(e))' generated='\(shorten(g))'") }
            }
        }

        // ScriptReference vs Script
        if let es = expected.findInParameter(type: "ScriptReference", tag: "ScriptReference"),
           let gs = generated.child("Script"), es.attrib["name"] != gs.attrib["name"] {
            diffs.append("Script name mismatch expected='\(es.attrib["name"] ?? "None")' generated='\(gs.attrib["name"] ?? "None")'")
        }
        return diffs
    }

    // MARK: Normalization

    static func removeHelperComments(_ root: Node) {
        for parent in root.iter {
            parent.children.removeAll { step in
                step.tag == "Step" && step.attrib["name"] == "Comment"
                    && (step.child("Text")?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("Original:")
            }
        }
    }

    static func removePlatformData(_ root: Node) {
        for n in root.iter { n.children.removeAll { $0.tag == "PlatformData" } }
    }

    static func normalizeWhitespace(_ root: Node) {
        for n in root.iter {
            if let t = n.text {
                n.text = t.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            }
        }
    }

    static func extractSteps(_ root: Node) -> [Node] {
        if root.tag == "fmxmlsnippet" { return root.children.filter { $0.tag == "Step" } }
        if let list = root.child("ObjectList") { return list.children.filter { $0.tag == "Step" } }
        return root.descendants.filter { $0.tag == "Step" }
    }

    static func normalizeStepName(_ name: String) -> String { name == "# (comment)" ? "Comment" : name }

    private static func label(_ step: Node, _ index: Int) -> String {
        "\(index): \(normalizeStepName(step.attrib["name"] ?? "")) (id=\(step.attrib["id"] ?? ""))"
    }

    private static func shorten(_ text: String?, limit: Int = 160) -> String {
        guard let text else { return "" }
        return text.count <= limit ? text : String(text.prefix(limit)) + "…"
    }
}
