// Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
// SPDX-License-Identifier: GPL-3.0-or-later

/// What happens when the input has errors.
public enum ConversionPolicy: String, Sendable, Codable, CaseIterable {
    /// Any error diagnostic fails the conversion (`xml` is nil).
    case strict
    /// Skip what can't be converted and keep the rest, with `<!-- ERROR -->`
    /// comments (Python's `--continue-on-error`).
    case continueOnError
}

/// How one input step was converted. Links input lines to emitted XML (D8).
public struct StepTrace: Sendable, Hashable, Codable {
    /// 1-based input lines the step was read from.
    public let sourceLines: ClosedRange<Int>
    /// Step name as written.
    public let stepName: String
    /// Registry match, nil for unknown steps.
    public let resolvedName: String?
    public let resolvedID: Int?
    /// Handler type used (e.g. "SetVariableHandler"); nil when not converted.
    public let handler: String?
    /// The parameters the parser saw, in order.
    public let params: StepParams
    public let isComment: Bool
    public let isDisabled: Bool
    /// Index range into the emitted `<Step>` elements. Empty when the step
    /// wasn't converted; more than one when a helper comment precedes it.
    public let xmlSteps: Range<Int>
    /// UTF-8 offsets of the emitted elements in `ConversionResult.previewXML`.
    public let xmlUTF8Range: Range<Int>?
}

public struct ConversionResult: Sendable {
    public enum Status: String, Sendable, Codable {
        case ok, warnings, failed
    }

    public let input: String
    public let policy: ConversionPolicy
    /// The XML to put on the clipboard; nil when the conversion failed.
    public let xml: String?
    /// The continue-on-error XML, always available (for the inspector).
    public let previewXML: String
    /// One trace per parsed input step.
    public let steps: [StepTrace]
    /// UTF-8 offsets of every emitted `<Step>` in `previewXML`.
    public let xmlStepRanges: [Range<Int>]
    public let diagnostics: [Diagnostic]
    public let duration: Duration
    /// The exception message Python raises in strict mode, if any.
    let strictFailureMessage: String?

    public var status: Status {
        if xml == nil { return .failed }
        return diagnostics.contains { $0.severity <= .warning } ? .warnings : .ok
    }

    public var errors: [Diagnostic] { diagnostics.filter { $0.severity == .error } }
    public var warnings: [Diagnostic] { diagnostics.filter { $0.severity == .warning } }

    /// Input steps that produced XML.
    public var convertedStepCount: Int { steps.filter { !$0.xmlSteps.isEmpty }.count }

    /// The span of `trace`'s elements in `previewXML`.
    public func xmlTextRange(for trace: StepTrace) -> Range<String.Index>? {
        trace.xmlUTF8Range.map { previewXML.utf8Range($0) }
    }

    /// The span of the `index`-th emitted `<Step>` in `previewXML`.
    public func xmlTextRange(forStep index: Int) -> Range<String.Index> {
        previewXML.utf8Range(xmlStepRanges[index])
    }

    /// The trace whose source lines include `line`.
    public func trace(forLine line: Int) -> StepTrace? {
        steps.first { $0.sourceLines.contains(line) }
    }
}

extension String {
    func utf8Range(_ r: Range<Int>) -> Range<String.Index> {
        let lo = utf8.index(utf8.startIndex, offsetBy: r.lowerBound)
        let hi = utf8.index(lo, offsetBy: r.count)
        return lo..<hi
    }
}

/// An error from `Converter.convertToXML`, worded as the Python CLI reports it.
public struct ConversionError: Error, Sendable, CustomStringConvertible {
    public let description: String
    public let diagnostic: Diagnostic?
}

/// Converts plain-text FileMaker script steps to an `fmxmlsnippet`.
///
/// Usage:
///
///     let result = Converter().convert("Set Variable [ $var ; Value: 1 ]")
///     result.xml  // <?xml version="1.0" ?>\n<fmxmlsnippet …
public struct Converter: Sendable {
    public static let version = "0.6.0"

    public let registry: StepRegistry
    private let suggester: StepNameSuggester

    public init(registry: StepRegistry = .shared) {
        self.registry = registry
        self.suggester = StepNameSuggester(names: registry.stepNames)
    }

    public func convert(_ text: String, policy: ConversionPolicy = .strict) -> ConversionResult {
        let clock = ContinuousClock()
        let start = clock.now

        // Universal newlines, as Python reads files and pbpaste output:
        // "\r\n" and "\r" become "\n"
        let parsed = Parser().parseWithDiagnostics(Self.normalizeNewlines(text))
        var diagnostics = parsed.diagnostics
        var elements: [XElement] = []
        var spans: [(Range<Int>, ParsedStep, StepDefinition?, String?)] = []
        var errorComments: [String] = []
        var strictFailureMessage: String?

        for step in parsed.steps {
            let first = elements.count
            guard let def = registry.get(step.name) else {
                // Python skips unknown steps silently in continue-on-error mode
                strictFailureMessage = strictFailureMessage ?? Self.unknownStepMessage(step)
                diagnostics.append(unknownStepDiagnostic(step))
                spans.append((first..<first, step, nil, nil))
                continue
            }
            let handler = StepHandlers.handler(for: step, def)
            do {
                let out = try handler.generate(step, def)
                elements.append(contentsOf: out)
                spans.append((first..<elements.count, step, def, handler.typeName))
                diagnostics.append(contentsOf: stepDiagnostics(step, def, handler, out))
            } catch {
                errorComments.append("Error converting step '\(step.name)': \(error.pythonMessage)")
                strictFailureMessage = strictFailureMessage ?? error.pythonMessage
                diagnostics.append(Diagnostic(
                    .error, .handlerFailed, lines: step.lines,
                    message: "“\(step.name)” could not be converted: \(error.message)."
                ))
                spans.append((first..<first, step, def, handler.typeName))
            }
        }

        if parsed.steps.isEmpty {
            diagnostics.append(Diagnostic(
                .error, .emptyInput, lines: 1...max(1, Self.normalizeNewlines(text).pySplit("\n").count),
                message: "No script steps found."
            ))
        }

        let output = XMLSerializer.serialize(elements, errorComments: errorComments)
        let traces = spans.map { range, step, def, handler in
            StepTrace(
                sourceLines: step.lines,
                stepName: step.name,
                resolvedName: def?.name,
                resolvedID: def?.id,
                handler: handler,
                params: step.params,
                isComment: step.isComment,
                isDisabled: step.isDisabled,
                xmlSteps: range,
                xmlUTF8Range: range.isEmpty
                    ? nil
                    : output.stepRanges[range.lowerBound].lowerBound..<output.stepRanges[range.upperBound - 1].upperBound
            )
        }

        diagnostics.sort { ($0.lines.lowerBound, $0.severity) < ($1.lines.lowerBound, $1.severity) }
        let failed = policy == .strict && diagnostics.contains { $0.severity == .error }
        return ConversionResult(
            input: text,
            policy: policy,
            xml: failed ? nil : output.xml,
            previewXML: output.xml,
            steps: traces,
            xmlStepRanges: output.stepRanges,
            diagnostics: diagnostics,
            duration: clock.now - start,
            strictFailureMessage: strictFailureMessage
        )
    }

    /// Python-compatible conversion: in strict mode, throws the first unknown
    /// step or handler failure (an empty input is not an error); otherwise
    /// returns the continue-on-error XML.
    public func convertToXML(_ text: String, stopOnError: Bool = true) throws(ConversionError) -> String {
        let result = convert(text, policy: .continueOnError)
        if stopOnError, let message = result.strictFailureMessage {
            throw ConversionError(
                description: message,
                diagnostic: result.diagnostics.first { $0.code == .unknownStep || $0.code == .handlerFailed }
            )
        }
        return result.previewXML
    }

    static func normalizeNewlines(_ text: String) -> String {
        guard text.unicodeScalars.contains("\r") else { return text }
        return text.pyReplace("\r\n", "\n").pyReplace("\r", "\n")
    }

    /// Validates without converting: unknown step names (comments skipped).
    public func validate(_ text: String) -> (isValid: Bool, errors: [String]) {
        let errors = Parser().parse(Self.normalizeNewlines(text))
            .filter { !$0.isComment && registry.get($0.name) == nil }
            .map { "Unknown step '\($0.name)' at line \($0.lineNumber)" }
        return (errors.isEmpty, errors)
    }

    // MARK: Diagnostics

    static func unknownStepMessage(_ step: ParsedStep) -> String {
        "Unknown script step: \(step.name)" + (step.lineNumber != 0 ? " (line \(step.lineNumber))" : "")
    }

    private func unknownStepDiagnostic(_ step: ParsedStep) -> Diagnostic {
        let candidates = suggester.suggestions(for: step.name)
        var message = "Unknown step “\(step.name)”."
        var suggestion: Suggestion?
        if let best = candidates.first {
            message += " Did you mean “\(best)”?"
            suggestion = Suggestion(line: step.lineNumber, original: step.name, replacement: best)
        }
        return Diagnostic(
            .error, .unknownStep, lines: step.lines, message: message,
            suggestion: suggestion, alternatives: Array(candidates.dropFirst())
        )
    }

    private func stepDiagnostics(_ step: ParsedStep, _ def: StepDefinition, _ handler: any StepHandler, _ out: [XElement]) -> [Diagnostic] {
        var result: [Diagnostic] = []

        if !(handler is GenericHandler) {
            let ignored = handler.ignoredLabels.union(commonIgnoredLabels)
            let labels = handler.knownLabels.union(ignored)
            for key in step.params.keys where !key.pyIsDigit && !labels.contains(key) {
                let candidates = StepNameSuggester(names: handler.knownLabels.sorted(), aliases: [:]).suggestions(for: key)
                var message = "“\(key)” isn’t a parameter of \(def.name); it was ignored."
                var suggestion: Suggestion?
                if let best = candidates.first {
                    message += " Did you mean “\(best)”?"
                    suggestion = Suggestion(line: step.lineNumber, original: key + ":", replacement: best + ":")
                }
                result.append(Diagnostic(
                    .warning, .unknownParameter, lines: step.lines, message: message,
                    suggestion: suggestion, alternatives: Array(candidates.dropFirst())
                ))
            }
            if !handler.allowsDuplicateLabels {
                for key in Set(step.duplicateKeys).sorted() where !ignored.contains(key) {
                    result.append(Diagnostic(
                        .info, .duplicateParameter, lines: step.lines,
                        message: "“\(key)” is given more than once; only the last value is used."
                    ))
                }
            }
        }

        if !step.isComment, out.count > 1, out.first.map(Self.isHelperComment) == true {
            result.append(Diagnostic(
                .info, .idLeftBlank, lines: step.lines,
                message: "\(def.name) refers to objects by name; FileMaker resolves them when you paste. "
                    + "A comment with the original step was added above it so you can check."
            ))
        }
        return result
    }

    static func isHelperComment(_ e: XElement) -> Bool {
        e.name == "Step" && e[attribute: "name"] == "Comment"
            && e.children.first?.text?.pyStartsWith("Original: ") == true
    }
}
