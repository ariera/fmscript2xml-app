// Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
// SPDX-License-Identifier: GPL-3.0-or-later

/// A minimal XML element: name, ordered attributes, optional text, children.
/// Elements named `Calculation` are written with their text in CDATA.
public struct XElement: Sendable, Hashable {
    public var name: String
    public var attributes: [(name: String, value: String)]
    public var text: String?
    public var children: [XElement]

    public init(_ name: String, _ attributes: KeyValuePairs<String, String> = [:], text: String? = nil, children: [XElement] = []) {
        self.name = name
        self.attributes = attributes.map { ($0.key, $0.value) }
        self.text = text
        self.children = children
    }

    public subscript(attribute name: String) -> String? {
        get { attributes.first { $0.name == name }?.value }
        set {
            if let i = attributes.firstIndex(where: { $0.name == name }) {
                if let newValue { attributes[i].value = newValue } else { attributes.remove(at: i) }
            } else if let newValue {
                attributes.append((name, newValue))
            }
        }
    }

    public mutating func append(_ child: XElement) { children.append(child) }

    public static func == (a: XElement, b: XElement) -> Bool {
        a.name == b.name && a.text == b.text && a.children == b.children
            && a.attributes.count == b.attributes.count
            && zip(a.attributes, b.attributes).allSatisfy { $0.name == $1.name && $0.value == $1.value }
    }

    public func hash(into h: inout Hasher) {
        h.combine(name)
        h.combine(text)
        h.combine(children)
        for a in attributes { h.combine(a.name); h.combine(a.value) }
    }
}

// MARK: - Builders (port of xml_builder.py)

enum XMLBuilder {
    static func step(_ id: Int, _ name: String, enabled: Bool = true) -> XElement {
        XElement("Step", ["enable": enabled ? "True" : "False", "id": String(id), "name": name])
    }

    static func step(_ def: StepDefinition, _ parsed: ParsedStep) -> XElement {
        step(def.id, def.xmlStepName, enabled: def.enableDefault && !parsed.isDisabled)
    }

    static func calculation(_ text: String) -> XElement {
        XElement("Calculation", text: text)
    }

    static func text(_ name: String, _ text: String) -> XElement {
        XElement(name, text: text)
    }

    /// `<name><Calculation>text</Calculation></name>`
    static func wrappedCalculation(_ name: String, _ text: String) -> XElement {
        XElement(name, children: [calculation(text)])
    }

    /// A Field reference. IDs are never set (ID policy).
    static func field(_ name: String, table: String? = nil, repetition: String? = nil) -> XElement {
        var e = XElement("Field", ["name": name])
        if let table, !table.isEmpty { e[attribute: "table"] = table }
        if let repetition, !repetition.isEmpty { e[attribute: "repetition"] = repetition }
        return e
    }

    static func layout(_ name: String) -> XElement { XElement("Layout", ["name": name]) }

    static func table(_ name: String) -> XElement { XElement("Table", ["name": name]) }

    static func commentStep(_ text: String) -> XElement {
        var s = step(89, "Comment")
        s.append(XMLBuilder.text("Text", text))
        return s
    }

    /// Helper comment emitted before steps whose database IDs can't be
    /// resolved, so the original text is at hand after pasting.
    static func helperCommentStep(_ originalText: String) -> XElement {
        commentStep("Original: \(originalText)")
    }

    static func state(_ name: String, _ value: Bool) -> XElement {
        XElement(name, ["state": value ? "True" : "False"])
    }
}
