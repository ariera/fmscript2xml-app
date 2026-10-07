// Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
// SPDX-License-Identifier: GPL-3.0-or-later

// Python `str` semantics on Unicode scalars.
//
// The Python reference indexes strings by code point, while Swift's `String`
// works on grapheme clusters ("\r\n" is one Character, and a combining mark
// merges with the quote before it). Parsing therefore works on arrays of
// Unicode scalars, with helpers that mirror the Python methods it ports.

typealias Scalars = [Unicode.Scalar]

extension Unicode.Scalar {
    /// Python `str.isspace()` for one code point.
    var pyIsSpace: Bool {
        properties.isWhitespace || (0x1C...0x1F).contains(value)
    }

    /// Python `str.isalpha()` for one code point (general category L*).
    var pyIsAlpha: Bool {
        switch properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter:
            return true
        default:
            return false
        }
    }

    /// Python `str.isupper()` for one code point.
    var pyIsUpper: Bool { properties.isUppercase }

    /// Python regex `\d`: general category Nd.
    var regexDigit: Bool { properties.generalCategory == .decimalNumber }

    /// Python `str.isdigit()` for one code point.
    var pyIsDigit: Bool {
        properties.numericType == .decimal || properties.numericType == .digit
    }
}

extension Array where Element == Unicode.Scalar {
    var string: String {
        var s = String.UnicodeScalarView()
        s.append(contentsOf: self)
        return String(s)
    }

    func pyStrip() -> Scalars {
        guard let first = firstIndex(where: { !$0.pyIsSpace }) else { return [] }
        let last = lastIndex(where: { !$0.pyIsSpace })!
        return Array(self[first...last])
    }

    func pyLStrip() -> Scalars {
        guard let first = firstIndex(where: { !$0.pyIsSpace }) else { return [] }
        return Array(self[first...])
    }

    func pyRStrip() -> Scalars {
        guard let last = lastIndex(where: { !$0.pyIsSpace }) else { return [] }
        return Array(self[...last])
    }

    /// Python `str.rstrip(chars)`.
    func pyRStrip(_ chars: Set<Unicode.Scalar>) -> Scalars {
        guard let last = lastIndex(where: { !chars.contains($0) }) else { return [] }
        return Array(self[...last])
    }

    /// Python `str.find(sub, start)`.
    func pyFind(_ sub: Scalars, from start: Int = 0) -> Int? {
        if sub.isEmpty { return start <= count ? start : nil }
        guard count >= sub.count else { return nil }
        var i = start
        while i <= count - sub.count {
            if self[i] == sub[0] {
                var j = 1
                while j < sub.count, self[i + j] == sub[j] { j += 1 }
                if j == sub.count { return i }
            }
            i += 1
        }
        return nil
    }

    func pyFind(_ scalar: Unicode.Scalar) -> Int? { firstIndex(of: scalar) }

    func pyContains(_ sub: Scalars) -> Bool { pyFind(sub) != nil }

    func pyStartsWith(_ prefix: Scalars) -> Bool {
        count >= prefix.count && self[..<prefix.count].elementsEqual(prefix)
    }

    func pyEndsWith(_ suffix: Scalars) -> Bool {
        count >= suffix.count && self[(count - suffix.count)...].elementsEqual(suffix)
    }

    /// Python slice `s[from:to]` with clamping, no negative indices.
    func pySlice(_ from: Int, _ to: Int? = nil) -> Scalars {
        let lo = Swift.min(Swift.max(from, 0), count)
        let hi = Swift.min(Swift.max(to ?? count, lo), count)
        return Array(self[lo..<hi])
    }
}

extension String {
    var scalars: Scalars { Array(unicodeScalars) }

    init(scalars: Scalars) { self = scalars.string }

    func pyStrip() -> String { scalars.pyStrip().string }
    func pyRStrip() -> String { scalars.pyRStrip().string }
    func pyLower() -> String { lowercased() }
    func pyStartsWith(_ prefix: String) -> Bool { unicodeScalars.starts(with: prefix.unicodeScalars) }
    func pyEndsWith(_ suffix: String) -> Bool { scalars.pyEndsWith(suffix.scalars) }
    func pyContains(_ sub: String) -> Bool { scalars.pyContains(sub.scalars) }
    func pyFind(_ sub: String) -> Int? { scalars.pyFind(sub.scalars) }

    /// Python `s[1:-1]`.
    func pyDropFirstAndLast() -> String {
        let s = scalars
        guard s.count >= 2 else { return "" }
        return Array(s[1..<(s.count - 1)]).string
    }

    /// Python `str.isdigit()`: non-empty and every code point a digit.
    var pyIsDigit: Bool {
        !unicodeScalars.isEmpty && unicodeScalars.allSatisfy(\.pyIsDigit)
    }

    /// Exact code point equality (Swift's `==` uses canonical equivalence).
    func pyEquals(_ other: String) -> Bool {
        unicodeScalars.elementsEqual(other.unicodeScalars)
    }

    /// Python `str.split(sep)` for a single-scalar separator.
    func pySplit(_ sep: Unicode.Scalar) -> [Scalars] {
        var parts: [Scalars] = [[]]
        for s in unicodeScalars {
            if s == sep { parts.append([]) } else { parts[parts.count - 1].append(s) }
        }
        return parts
    }

    /// Python `str.replace(old, new)` on code points.
    func pyReplace(_ old: String, _ new: String) -> String {
        let s = scalars, o = old.scalars, n = new.scalars
        guard !o.isEmpty else { return self }
        var out = Scalars()
        out.reserveCapacity(s.count)
        var i = 0
        while i < s.count {
            if i + o.count <= s.count, s[i] == o[0], s[i..<(i + o.count)].elementsEqual(o) {
                out.append(contentsOf: n)
                i += o.count
            } else {
                out.append(s[i])
                i += 1
            }
        }
        return out.string
    }
}

/// Python truthiness for optional strings: `value or fallback`.
func pyOr(_ values: String?...) -> String {
    for v in values.dropLast() { if let v, !v.isEmpty { return v } }
    return values.last.flatMap { $0 } ?? ""
}
