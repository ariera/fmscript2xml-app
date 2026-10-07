// Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
// SPDX-License-Identifier: GPL-3.0-or-later

/// Parses plain-text FileMaker script steps into `ParsedStep`s.
///
/// Port of the Python `Parser`: step names, bracketed parameters split on
/// top-level semicolons, `Key: value` pairs, `#` comments, `//` disabled
/// steps, multi-line steps (joined until brackets balance) and `…` truncation.
public struct Parser: Sendable {
    public struct Output: Sendable {
        public var steps: [ParsedStep]
        public var diagnostics: [Diagnostic]
    }

    public init() {}

    public func parse(_ text: String) -> [ParsedStep] { parseWithDiagnostics(text).steps }

    public func parseWithDiagnostics(_ text: String) -> Output {
        let lines = text.pySplit("\n")
        var steps: [ParsedStep] = []
        var diagnostics: [Diagnostic] = []

        var i = 0
        while i < lines.count {
            let lineNum = i + 1
            // Normalize HTML entities in sanitized inputs (e.g. &lt;Table Missing&gt;)
            // so parsing doesn't split on entity semicolons.
            var line = HTMLUnescape.unescape(lines[i].pyStrip())

            if line.isEmpty {
                i += 1
                continue
            }

            // Comments: keep everything after the #, including indentation
            if line.first == "#" {
                let original = lines[i]
                let hashPos = original.pyFind("#") ?? 0
                steps.append(ParsedStep(
                    name: "Comment",
                    rawText: original.string,
                    lines: lineNum...lineNum,
                    isComment: true,
                    commentText: original.pySlice(hashPos + 1).string
                ))
                i += 1
                continue
            }

            // Disabled steps (// prefix)
            var isDisabled = false
            if line.pyStartsWith(["/", "/"]) {
                isDisabled = true
                line = line.pySlice(2).pyStrip()
                if line.isEmpty {
                    i += 1
                    continue
                }
            }

            // Skip what looks like a stray continuation line (starts with a
            // closing bracket/paren, or has no letters early on)
            if line.first == "]" || line.first == ")"
                || (!line.pySlice(0, 20).contains(where: \.pyIsAlpha) && !line.contains("[") && !line[0].pyIsUpper) {
                diagnostics.append(Diagnostic(
                    .warning, .skippedLine, lines: lineNum...lineNum,
                    message: "Line \(lineNum) was skipped: it looks like the continuation of a step, not a step."
                ))
                i += 1
                continue
            }

            // Truncated with an ellipsis: keep it, and close any open brackets
            if let ellipsisPos = line.pyFind("…") {
                var truncated = line.pySlice(0, ellipsisPos + 1).pyStrip()
                var scanner = CalcScanner()
                let open = scanner.bracketBalance(line.pySlice(0, ellipsisPos))
                if open > 0 { truncated += Array(repeating: "]", count: open) }
                line = truncated
                diagnostics.append(Diagnostic(
                    .info, .truncatedLine, lines: lineNum...lineNum,
                    message: "Line \(lineNum) is truncated at “…”; the text after it was dropped."
                ))
            }

            // Collect continuation lines until brackets balance. Brackets in
            // string literals, quoted names and comments don't count.
            var fullLine = line
            var lastLine = lineNum
            if line.contains("[") {
                var scanner = CalcScanner()
                var bracketCount = scanner.bracketBalance(line)
                var j = i + 1
                while bracketCount > 0 && j < lines.count {
                    // Keep continuation lines verbatim and joined by line breaks:
                    // they can be part of a string literal, and a // comment
                    // ends at the line break
                    var nextLine = lines[j].pyRStrip(["\r"])
                    j += 1
                    // Truncated with ellipsis: keep the text before it and close the step
                    if let pos = nextLine.pyFind("…") {
                        nextLine = nextLine.pySlice(0, pos).pyStrip()
                        fullLine += ["\n"] + nextLine
                        bracketCount += scanner.bracketBalance(nextLine)
                        fullLine += Array(repeating: "]", count: max(bracketCount, 0))
                        diagnostics.append(Diagnostic(
                            .info, .truncatedLine, lines: j...j,
                            message: "Line \(j) is truncated at “…”; the text after it was dropped."
                        ))
                        bracketCount = 0
                        break
                    }
                    fullLine += ["\n"] + nextLine
                    bracketCount += scanner.bracketBalance(nextLine)
                }
                if bracketCount > 0 {
                    diagnostics.append(Diagnostic(
                        .warning, .unbalancedBrackets, lines: lineNum...max(lineNum, j),
                        message: j > i + 1
                            ? "The “[” on line \(lineNum) is never closed, so lines \(lineNum + 1)–\(j) were read as part of this step."
                            : "The “[” on line \(lineNum) is never closed."
                    ))
                }
                lastLine = max(lineNum, j)
                i = j
            } else {
                i += 1
            }

            var step = parseStep(fullLine, lines: lineNum...lastLine)
            step.isDisabled = isDisabled
            if !step.name.scalars.pyStrip().isEmpty {
                steps.append(step)
            } else {
                diagnostics.append(Diagnostic(
                    .warning, .skippedLine, lines: lineNum...lastLine,
                    message: "Line \(lineNum) was skipped: it has parameters but no step name."
                ))
            }
        }

        return Output(steps: steps, diagnostics: diagnostics)
    }

    /// Parses one (possibly multi-line) step.
    func parseStep(_ line: Scalars, lines: ClosedRange<Int>) -> ParsedStep {
        guard let bracketPos = line.pyFind("[") else {
            return ParsedStep(name: line.pyStrip().string, rawText: line.string, lines: lines)
        }
        let name = line.pySlice(0, bracketPos).pyStrip().string
        let paramsText = Self.extractBracketedContent(line, from: bracketPos)
        let (params, duplicates) = Self.parseParams(paramsText)
        return ParsedStep(name: name, params: params, rawText: line.string, lines: lines, duplicateKeys: duplicates)
    }

    /// Content between the `[` at `start` and its matching `]` (stripped),
    /// or everything after `[` if it's never closed.
    static func extractBracketedContent(_ text: Scalars, from start: Int) -> Scalars {
        guard start < text.count, text[start] == "[" else { return [] }
        var depth = 0
        var scanner = CalcScanner()
        for (pos, char) in scanner.codeChars(text, start: start) {
            if char == "[" {
                depth += 1
            } else if char == "]" {
                depth -= 1
                if depth == 0 { return text.pySlice(start + 1, pos).pyStrip() }
            }
        }
        return text.pySlice(start + 1).pyStrip()
    }

    /// Splits parameter text into positional and `Key: value` parameters.
    /// Returns the params and the named keys that were given more than once.
    static func parseParams(_ paramsText: Scalars) -> (StepParams, [String]) {
        var params = StepParams()
        var duplicates: [String] = []
        guard !paramsText.isEmpty else { return (params, duplicates) }

        for rawPart in smartSplit(paramsText, ";") {
            let part = rawPart.pyStrip()
            if part.isEmpty { continue }

            // Key-value pair: a single colon outside strings, names and
            // comments (:: is a table reference)
            var colonPos: Int?
            var scanner = CalcScanner()
            let codeChars = scanner.codeChars(part)
            var k = 0
            while k < codeChars.count {
                let (idx, char) = codeChars[k]
                if char == ":" {
                    if idx + 1 < part.count && part[idx + 1] == ":" {
                        k += 2  // Skip ::
                        continue
                    }
                    colonPos = idx
                    break
                }
                k += 1
            }

            if let colonPos {
                let key = part.pySlice(0, colonPos).pyStrip().string
                let value = part.pySlice(colonPos + 1).pyStrip().string
                if params.has(key) { duplicates.append(key) }
                params[key] = value
            } else {
                // Positional: keyed by the number of digit keys so far
                let index = params.keys.filter(\.pyIsDigit).count
                params[String(index)] = part.string
            }
        }
        return (params, duplicates)
    }

    /// Splits on `delimiter` outside brackets, parentheses, strings, names
    /// and comments.
    static func smartSplit(_ text: Scalars, _ delimiter: Unicode.Scalar) -> [Scalars] {
        var parts: [Scalars] = []
        var partStart = 0
        var bracketDepth = 0
        var parenDepth = 0
        var scanner = CalcScanner()
        for (i, char) in scanner.codeChars(text) {
            switch char {
            case "[": bracketDepth += 1
            case "]": bracketDepth -= 1
            case "(": parenDepth += 1
            case ")": parenDepth -= 1
            case delimiter where bracketDepth == 0 && parenDepth == 0:
                parts.append(text.pySlice(partStart, i))
                partStart = i + 1
            default: break
            }
        }
        if partStart < text.count { parts.append(text.pySlice(partStart)) }
        return parts
    }
}
