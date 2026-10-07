// Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
// SPDX-License-Identifier: GPL-3.0-or-later

/// Step parameters in source order, like the Python `dict` they port.
///
/// Positional parameters are keyed "0", "1", … and named ones by their label
/// (e.g. "Value", "With dialog"). Assigning an existing key keeps its position.
public struct StepParams: Sendable, Hashable, Codable {
    public private(set) var keys: [String] = []
    private var storage: [String: String] = [:]

    public init() {}

    public init(_ pairs: KeyValuePairs<String, String>) {
        for (k, v) in pairs { self[k] = v }
    }

    public subscript(key: String) -> String? {
        get { storage[key] }
        set {
            if let newValue {
                if storage.updateValue(newValue, forKey: key) == nil { keys.append(key) }
            } else if storage.removeValue(forKey: key) != nil {
                keys.removeAll { $0 == key }
            }
        }
    }

    /// Python `params.get(key, default)`.
    public func get(_ key: String, _ defaultValue: String = "") -> String {
        storage[key] ?? defaultValue
    }

    public func has(_ key: String) -> Bool { storage[key] != nil }

    public var isEmpty: Bool { keys.isEmpty }
    public var count: Int { keys.count }
    public var values: [String] { keys.map { storage[$0]! } }
    public var items: [(key: String, value: String)] { keys.map { ($0, storage[$0]!) } }
}

/// A parsed FileMaker script step: the normalized output of the plain-text
/// parser, before XML generation.
///
/// Example: `Set Variable [ $var ; Value: 1 ]` parses to name "Set Variable",
/// params `["0": "$var", "Value": "1"]`.
public struct ParsedStep: Sendable, Hashable {
    /// Step name as written; selects the handler (e.g. "Go to Layout").
    public var name: String
    /// Positional params keyed "0", "1", …; named params keyed by label.
    public var params: StepParams
    /// The step's source text: the first line stripped (and HTML-unescaped),
    /// plus any continuation lines joined with "\n". Comment steps keep the
    /// original line.
    public var rawText: String
    /// 1-based source lines this step was read from (D8). Multi-line steps
    /// span several lines.
    public var lines: ClosedRange<Int>
    /// True for `# comment` lines.
    public var isComment: Bool
    /// Comment body without the leading `#`, indentation kept.
    public var commentText: String
    /// True for steps prefixed with `//` (emitted with enable="False").
    public var isDisabled: Bool
    /// Named labels that appeared more than once; the last value wins.
    public var duplicateKeys: [String]

    /// First source line (Python's `line_number`).
    public var lineNumber: Int { lines.lowerBound }

    public init(
        name: String,
        params: StepParams = StepParams(),
        rawText: String = "",
        lines: ClosedRange<Int> = 0...0,
        isComment: Bool = false,
        commentText: String = "",
        isDisabled: Bool = false,
        duplicateKeys: [String] = []
    ) {
        self.name = name
        self.params = params
        self.rawText = rawText
        self.lines = lines
        self.isComment = isComment
        self.commentText = commentText
        self.isDisabled = isDisabled
        self.duplicateKeys = duplicateKeys
    }
}
