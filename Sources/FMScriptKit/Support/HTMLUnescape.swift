// Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Port of Python's `html.unescape` (3.12), including the HTML5 named
/// character references and the longest-prefix rule for names without `;`.
///
/// The parser applies it to the first line of every step so that sanitized
/// inputs such as `&lt;Table Missing&gt;` don't split on entity semicolons.
enum HTMLUnescape {
    private struct Tables: Decodable {
        let html5: [String: String]
        let invalidCharrefs: [String: String]
        let invalidCodepoints: [UInt32]
    }

    private static let tables: (html5: [String: String], invalidCharrefs: [UInt32: String], invalidCodepoints: Set<UInt32>) = {
        guard let url = Bundle.module.url(forResource: "html-entities", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let t = try? JSONDecoder().decode(Tables.self, from: data)
        else { fatalError("FMScriptKit: missing html-entities.json resource") }
        var refs: [UInt32: String] = [:]
        for (k, v) in t.invalidCharrefs { refs[UInt32(k)!] = v }
        return (t.html5, refs, Set(t.invalidCodepoints))
    }()

    private static func isNameChar(_ c: Unicode.Scalar) -> Bool {
        !["\t", "\n", "\u{0C}", " ", "<", "&", "#", ";"].contains(c)
    }

    private static func isASCIIDigit(_ c: Unicode.Scalar) -> Bool { ("0"..."9").contains(c) }

    private static func isASCIIHex(_ c: Unicode.Scalar) -> Bool {
        isASCIIDigit(c) || ("a"..."f").contains(c) || ("A"..."F").contains(c)
    }

    static func unescape(_ s: Scalars) -> Scalars {
        guard s.contains("&") else { return s }
        var out = Scalars()
        out.reserveCapacity(s.count)
        var i = 0
        while i < s.count {
            guard s[i] == "&", let (end, replacement) = match(s, at: i) else {
                out.append(s[i])
                i += 1
                continue
            }
            out.append(contentsOf: replacement)
            i = end
        }
        return out
    }

    /// Matches `&(#[0-9]+;?|#[xX][0-9a-fA-F]+;?|[^\t\n\f <&#;]{1,32};?)` at `amp`.
    /// Returns the end index and the replacement.
    private static func match(_ s: Scalars, at amp: Int) -> (Int, Scalars)? {
        var j = amp + 1
        guard j < s.count else { return nil }
        if s[j] == "#" {
            // Decimal
            var k = j + 1
            while k < s.count, isASCIIDigit(s[k]) { k += 1 }
            if k > j + 1 {
                let digits = Array(s[(j + 1)..<k])
                if k < s.count, s[k] == ";" { k += 1 }
                return (k, numeric(digits, radix: 10))
            }
            // Hexadecimal
            if j + 1 < s.count, s[j + 1] == "x" || s[j + 1] == "X" {
                k = j + 2
                while k < s.count, isASCIIHex(s[k]) { k += 1 }
                if k > j + 2 {
                    let digits = Array(s[(j + 2)..<k])
                    if k < s.count, s[k] == ";" { k += 1 }
                    return (k, numeric(digits, radix: 16))
                }
            }
            return nil
        }
        // Named
        while j < s.count, j - (amp + 1) < 32, isNameChar(s[j]) { j += 1 }
        guard j > amp + 1 else { return nil }
        if j < s.count, s[j] == ";" { j += 1 }
        let name = Array(s[(amp + 1)..<j])
        return (j, named(name))
    }

    private static func numeric(_ digits: Scalars, radix: UInt32) -> Scalars {
        var num: UInt32 = 0
        var overflow = false
        for d in digits {
            let v: UInt32 = isASCIIDigit(d) ? d.value - 0x30 : (d.value | 0x20) - 0x61 + 10
            let (m, o1) = num.multipliedReportingOverflow(by: radix)
            let (a, o2) = m.addingReportingOverflow(v)
            if o1 || o2 { overflow = true; break }
            num = a
        }
        if !overflow, let r = tables.invalidCharrefs[num] { return r.scalars }
        if overflow || (0xD800...0xDFFF).contains(num) || num > 0x10FFFF { return ["\u{FFFD}"] }
        if tables.invalidCodepoints.contains(num) { return [] }
        return [Unicode.Scalar(num)!]
    }

    private static func named(_ name: Scalars) -> Scalars {
        if let v = tables.html5[name.string] { return v.scalars }
        // Longest matching prefix (as defined by the standard)
        var x = name.count - 1
        while x > 1 {
            if let v = tables.html5[Array(name[..<x]).string] {
                return v.scalars + Array(name[x...])
            }
            x -= 1
        }
        return ["&"] + name
    }
}
