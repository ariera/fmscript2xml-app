// Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
// SPDX-License-Identifier: GPL-3.0-or-later

/// A problem or note about the input, tied to source lines.
public struct Diagnostic: Sendable, Hashable, Codable {
    public enum Severity: String, Sendable, Hashable, Codable, Comparable {
        case error, warning, info

        private var rank: Int { self == .error ? 0 : self == .warning ? 1 : 2 }
        public static func < (a: Severity, b: Severity) -> Bool { a.rank < b.rank }
    }

    public enum Code: String, Sendable, Hashable, Codable {
        /// The step name isn't in the registry; the step is not converted.
        case unknownStep
        /// The step's handler failed; the step is not converted.
        case handlerFailed
        /// No script steps were found in the input.
        case emptyInput
        /// A `[` is never closed, so following lines were read into the step.
        case unbalancedBrackets
        /// A named parameter the step's handler doesn't read.
        case unknownParameter
        /// A named parameter given more than once; the last value is used.
        case duplicateParameter
        /// The step references a database object by name only; FileMaker
        /// can't resolve its ID, so a helper comment with the original text
        /// is emitted before it (ID policy).
        case idLeftBlank
        /// A line was skipped because it looks like a stray continuation line.
        case skippedLine
        /// The step was truncated at an ellipsis (`…`) and its brackets closed.
        case truncatedLine
    }

    public let severity: Severity
    public let code: Code
    /// 1-based input lines the diagnostic refers to.
    public let lines: ClosedRange<Int>
    /// 1-based column on the first line, when known.
    public let column: Int?
    public let message: String
    /// A fix that can be applied to the input (e.g. a did-you-mean name).
    public let suggestion: Suggestion?
    /// Further candidates after `suggestion`, best first.
    public let alternatives: [String]

    public init(
        _ severity: Severity,
        _ code: Code,
        lines: ClosedRange<Int>,
        column: Int? = nil,
        message: String,
        suggestion: Suggestion? = nil,
        alternatives: [String] = []
    ) {
        self.severity = severity
        self.code = code
        self.lines = lines
        self.column = column
        self.message = message
        self.suggestion = suggestion
        self.alternatives = alternatives
    }
}

/// Replace `original` with `replacement` on one input line.
public struct Suggestion: Sendable, Hashable, Codable {
    public let line: Int
    public let original: String
    public let replacement: String

    public init(line: Int, original: String, replacement: String) {
        self.line = line
        self.original = original
        self.replacement = replacement
    }

    /// Applies the fix to the first occurrence of `original` on `line`.
    /// Returns nil when the line no longer contains it.
    public func apply(to text: String) -> String? {
        var lines = text.pySplit("\n")
        guard line >= 1, line <= lines.count,
              let at = lines[line - 1].pyFind(original.scalars)
        else { return nil }
        let old = lines[line - 1]
        lines[line - 1] = Array(old[..<at]) + replacement.scalars + Array(old[(at + original.unicodeScalars.count)...])
        return lines.map(\.string).joined(separator: "\n")
    }
}
