// Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
// SPDX-License-Identifier: GPL-3.0-or-later

/// Generates the XML for one kind of script step.
protocol StepHandler: Sendable {
    /// Named parameter labels the handler understands. Other labels produce
    /// an `unknownParameter` warning.
    var knownLabels: Set<String> { get }

    /// Valid FileMaker labels the handler doesn't convert (no warning).
    var ignoredLabels: Set<String> { get }

    /// The emitted elements: usually one `<Step>`, preceded by a helper
    /// comment when the step references database objects by name only.
    func generate(_ step: ParsedStep, _ def: StepDefinition) throws(HandlerError) -> [XElement]

    /// True when repeated labels are expected (and re-parsed by the handler).
    var allowsDuplicateLabels: Bool { get }
}

extension StepHandler {
    var ignoredLabels: Set<String> { [] }
    var allowsDuplicateLabels: Bool { false }
    var typeName: String { String(describing: type(of: self)) }
}

/// A handler failure. The step is skipped (continue-on-error) or the
/// conversion fails (strict).
public enum HandlerError: Error, Sendable, Hashable {
    /// Perform Script on Server with Callback without a script name for the
    /// main or callback script, and not "By name".
    case missingScriptName

    /// The message the Python implementation reports for the same failure.
    var pythonMessage: String {
        switch self {
        case .missingScriptName: return "'NoneType' object has no attribute 'strip'"
        }
    }

    public var message: String {
        switch self {
        case .missingScriptName: return "a script name is missing (main or callback script)"
        }
    }
}

enum StepHandlers {
    /// Handlers by step name, as in the Python `HANDLERS` registry.
    static let all: [String: any StepHandler] = [
        "Comment": CommentHandler(),
        "Set Variable": SetVariableHandler(),
        "Set Error Capture": SetErrorCaptureHandler(),
        "New Window": NewWindowHandler(),
        "Close Window": CloseWindowHandler(),
        "Enter Preview Mode": EnterPreviewModeHandler(),
        "Print": PrintHandler(),
        "Print Setup": PrintSetupHandler(),
        "If": IfHandler(),
        "Else If": IfHandler(),
        "Else": PlainStepHandler(),
        "End If": PlainStepHandler(),
        "Exit Script": ExitScriptHandler(),
        "Pause/Resume Script": PauseResumeScriptHandler(),
        "Perform Script": PerformScriptHandler(),
        "Go to Layout": GoToLayoutHandler(),
        "Go to Record/Request/Page": GoToRecordRequestPageHandler(),
        "Go to Related Record": GoToRelatedRecordHandler(),
        "Set Field": SetFieldHandler(),
        "Perform Find": PerformFindHandler(),
        "Show Custom Dialog": ShowCustomDialogHandler(),
        "Open URL": OpenURLHandler(),
        "Send Mail": SendMailHandler(),
        "Set Field By Name": SetFieldByNameHandler(),
        "Install OnTimer Script": InstallOnTimerScriptHandler(),
        "Commit Records/Requests": CommitRecordsRequestsHandler(),
        "Save Records as PDF": SaveRecordsAsPDFHandler(),
        "Sort Records by Field": SortRecordsByFieldHandler(),
        "Perform Script on Server": PerformScriptOnServerHandler(),
        "Perform Script on Server with Callback": PerformScriptOnServerWithCallbackHandler(),
    ]

    /// The handler used for `step`, and its type name (for the inspector).
    static func handler(for step: ParsedStep, _ def: StepDefinition) -> any StepHandler {
        if let h = all[step.name], step.name == def.name { return h }
        return GenericHandler()
    }

}

/// Default handler: positional params become `<Calculation>`s and named
/// params become elements named after the label (spaces removed).
struct GenericHandler: StepHandler {
    var knownLabels: Set<String> { [] }

    func generate(_ step: ParsedStep, _ def: StepDefinition) -> [XElement] {
        var e = XMLBuilder.step(def, step)
        for (key, value) in step.params.items {
            if key.pyIsDigit {
                e.append(XMLBuilder.calculation(value))
            } else {
                var name = key.pyReplace(" ", "")
                if name.isEmpty { name = "Parameter" }
                e.append(XElement(name, text: value))
            }
        }
        return [e]
    }
}

/// A step with no parameters (Else, End If).
struct PlainStepHandler: StepHandler {
    var knownLabels: Set<String> { [] }

    func generate(_ step: ParsedStep, _ def: StepDefinition) -> [XElement] {
        [XMLBuilder.step(def, step)]
    }
}

// MARK: - Shared helpers

/// "With dialog: Off" → NoInteract state="True".
func noInteract(_ step: ParsedStep, default defaultValue: String = "On") -> XElement {
    let withDialog = step.params.get("With dialog", defaultValue)
    return XMLBuilder.state("NoInteract", withDialog.pyLower() == "off")
}

/// True when a layout reference is a calculation rather than a quoted name.
func isCalculatedReference(_ value: String) -> Bool {
    value.pyStartsWith("$") || value.pyContains("(") || value.pyContains("&") || value.pyContains("=")
        || !(value.pyStartsWith("\"") && value.pyEndsWith("\""))
}

/// Splits `Table::Field[rep]` into field, table and repetition.
func parseFieldReference(_ ref: String) -> (field: String, table: String?, repetition: String?) {
    var s = ref.scalars
    var repetition: String?
    // \[(\d+)\]$
    if s.last == "]", let open = s.lastIndex(of: "["), open < s.count - 2,
       s[(open + 1)..<(s.count - 1)].allSatisfy(\.regexDigit) {
        repetition = Array(s[(open + 1)..<(s.count - 1)]).string
        s = Array(s[..<open])
    }
    if let sep = s.pyFind([":", ":"]) {
        return (s.pySlice(sep + 2).string, s.pySlice(0, sep).string, repetition)
    }
    return (s.string, nil, repetition)
}
