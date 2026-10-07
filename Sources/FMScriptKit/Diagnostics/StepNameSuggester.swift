// Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
// SPDX-License-Identifier: GPL-3.0-or-later

/// "Did you mean" suggestions for unknown names (PLAN §7).
///
/// Names are compared case-insensitively, with whitespace collapsed,
/// typographic quotes unified and a trailing "…" ignored, and ranked by
/// Damerau–Levenshtein distance (a transposition counts as one edit). A
/// candidate qualifies when the distance is at most max(2, 25% of the
/// length); ties go to the longer shared prefix. A name that extends another
/// by a suffix (at least six characters in common) also qualifies.
public struct StepNameSuggester: Sendable {
    /// Common shorthands and old names → registry names.
    public static let aliases: [String: String] = [
        "Go to Record": "Go to Record/Request/Page",
        "Go to Record/Request": "Go to Record/Request/Page",
        "Commit Records": "Commit Records/Requests",
        "Commit Record": "Commit Records/Requests",
        "New Record": "New Record/Request",
        "Delete Record": "Delete Record/Request",
        "Duplicate Record": "Duplicate Record/Request",
        "Revert Record": "Revert Record/Request",
        "Open Record": "Open Record/Request",
        "Copy Record": "Copy Record/Request",
        "Pause Script": "Pause/Resume Script",
        "Resume Script": "Pause/Resume Script",
        "Undo": "Undo/Redo",
        "Redo": "Undo/Redo",
        "Find Records": "Perform Find",
        "Find": "Perform Find",
        "Show Dialog": "Show Custom Dialog",
        "Custom Dialog": "Show Custom Dialog",
        "Exit Loop": "Exit Loop If",
        "Else if": "Else If",
        "Elseif": "Else If",
        "ElseIf": "Else If",
        "EndIf": "End If",
        "End Of If": "End If",
        "EndLoop": "End Loop",
        "Set Var": "Set Variable",
        "Let": "Set Variable",
        "Run Script": "Perform Script",
        "Call Script": "Perform Script",
        "Perform Script On Server": "Perform Script on Server",
        "Open Url": "Open URL",
        "Halt": "Halt Script",
        "Insert From URL": "Insert from URL",
        "Save Record as PDF": "Save Records as PDF",
        "Save as PDF": "Save Records as PDF",
        "Sort": "Sort Records",
        "Unsort": "Unsort Records",
        "Show All": "Show All Records",
        "Close": "Close Window",
        "#": "Comment",
    ]

    private struct Candidate: Sendable {
        let display: String
        let key: [Unicode.Scalar]
    }

    private let candidates: [Candidate]
    private let aliasKeys: [String: String]

    public init(names: [String], aliases: [String: String] = StepNameSuggester.aliases) {
        let valid = Set(names)
        candidates = names
            .filter { !$0.hasPrefix("#[OBSOLETE]") }
            .map { Candidate(display: $0.pyStrip(), key: Self.normalize($0)) }
        var keys: [String: String] = [:]
        for (alias, target) in aliases where valid.contains(target) || valid.contains(target + " ") {
            keys[Self.normalize(alias).string] = target
        }
        aliasKeys = keys
    }

    /// Up to `limit` names, best first.
    public func suggestions(for name: String, limit: Int = 3) -> [String] {
        let key = Self.normalize(name)
        guard !key.isEmpty else { return [] }
        var ranked: [(display: String, distance: Int, prefix: Int)] = []
        if let target = aliasKeys[key.string] {
            ranked.append((target.pyStrip(), 0, key.count))
        }
        let threshold = max(2, key.count / 4)
        for c in candidates {
            let prefix = Self.sharedPrefix(key, c.key)
            // One name extends the other (e.g. "Layoutname" → "Layout")
            if min(key.count, c.key.count) >= 6 && prefix == min(key.count, c.key.count) && key != c.key {
                ranked.append((c.display, threshold, prefix))
                continue
            }
            // Cheap bound: the distance is at least the length difference
            guard abs(c.key.count - key.count) <= threshold else { continue }
            let d = Self.distance(key, c.key)
            if d <= threshold {
                ranked.append((c.display, d, prefix))
            }
        }
        ranked.sort { ($0.distance, -$0.prefix, $0.display) < ($1.distance, -$1.prefix, $1.display) }
        var seen = Set<String>()
        return ranked.map(\.display).filter { seen.insert($0).inserted }.prefix(limit).map { $0 }
    }

    static func normalize(_ s: String) -> [Unicode.Scalar] {
        var out: [Unicode.Scalar] = []
        var pendingSpace = false
        for c in s.lowercased().unicodeScalars {
            if c.pyIsSpace {
                pendingSpace = !out.isEmpty
                continue
            }
            if pendingSpace { out.append(" ") }
            pendingSpace = false
            switch c {
            case "“", "”", "„", "″": out.append("\"")
            case "‘", "’", "‚", "′": out.append("'")
            default: out.append(c)
            }
        }
        while out.last == "…" || out.last == " " { out.removeLast() }
        while out.count >= 3, out.suffix(3) == [".", ".", "."] { out.removeLast(3) }
        return out
    }

    /// Damerau–Levenshtein distance (optimal string alignment).
    static func distance(_ a: [Unicode.Scalar], _ b: [Unicode.Scalar]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev2 = [Int](repeating: 0, count: b.count + 1)
        var prev = Array(0...b.count)
        var cur = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            cur[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    cur[j] = min(cur[j], prev2[j - 2] + 1)
                }
            }
            (prev2, prev, cur) = (prev, cur, prev2)
        }
        return prev[b.count]
    }

    static func sharedPrefix(_ a: [Unicode.Scalar], _ b: [Unicode.Scalar]) -> Int {
        zip(a, b).prefix { $0 == $1 }.count
    }
}
