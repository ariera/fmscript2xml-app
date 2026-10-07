// Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
// SPDX-License-Identifier: GPL-3.0-or-later

/// Finds the characters of FileMaker script text that are syntax.
///
/// Brackets, semicolons and colons are ignored when they are inside:
/// - string literals: `"..."` with backslash escapes (e.g. `"a \" quote"`)
/// - quoted object names: `“...”` (e.g. layout and script names)
/// - calculation comments: `/* ... */` and `//` to the end of the line
///
/// String literals and `/* */` comments may span lines, so the state carries
/// over between calls when text is fed one line at a time.
struct CalcScanner {
    enum State { case code, string, name, blockComment, lineComment }

    private(set) var state: State = .code

    /// The syntax characters of `text` from `start`, as (index, scalar).
    ///
    /// A `//` comment ends at a `;` or at a `]` it doesn't open itself, which
    /// are returned: FileMaker writes the rest of the step after a trailing
    /// comment on the same line, e.g. `Set Field By Name [ $f // note ; $id ]`.
    mutating func codeChars(_ text: Scalars, start: Int = 0) -> [(index: Int, char: Unicode.Scalar)] {
        if state == .lineComment { state = .code }  // Each call starts on a new line
        var result: [(Int, Unicode.Scalar)] = []
        var commentDepth = 0
        var i = start
        while i < text.count {
            let char = text[i]
            let next: Unicode.Scalar? = i + 1 < text.count ? text[i + 1] : nil
            switch state {
            case .string:
                if char == "\\" {
                    i += 1  // Skip escaped character
                } else if char == "\"" {
                    state = .code
                }
            case .name:
                if char == "”" { state = .code }
            case .blockComment:
                if char == "*" && next == "/" {
                    state = .code
                    i += 1
                }
            case .lineComment:
                if char == "\n" {
                    state = .code
                } else if char == "[" {
                    commentDepth += 1
                } else if char == "]" && commentDepth > 0 {
                    commentDepth -= 1
                } else if char == ";" || char == "]" {
                    state = .code
                    result.append((i, char))
                }
            case .code:
                if char == "\"" {
                    state = .string
                } else if char == "“" {
                    state = .name
                } else if char == "/" && next == "*" {
                    state = .blockComment
                    i += 1
                } else if char == "/" && next == "/" {
                    state = .lineComment
                    commentDepth = 0
                    i += 1
                } else {
                    result.append((i, char))
                }
            }
            i += 1
        }
        return result
    }

    /// The number of syntax `[` minus syntax `]` in `text`.
    mutating func bracketBalance(_ text: Scalars) -> Int {
        var balance = 0
        for (_, char) in codeChars(text) {
            if char == "[" { balance += 1 } else if char == "]" { balance -= 1 }
        }
        return balance
    }
}
