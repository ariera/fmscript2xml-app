// Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
// SPDX-License-Identifier: GPL-3.0-or-later

// Fields (Set Field, Set Field By Name) and scripts (Perform Script,
// Install OnTimer Script, Perform Script on Server [with Callback])

struct SetFieldHandler: StepHandler {
    var knownLabels: Set<String> { ["Field", "Value"] }

    func generate(_ step: ParsedStep, _ def: StepDefinition) -> [XElement] {
        var e = XMLBuilder.step(def, step)

        // The field may be omitted ("active field" usage)
        var fieldName = step.params.get("Field", "")
        var value = step.params.get("Value", "")
        if fieldName.isEmpty {
            // A single positional param with no explicit Field is the value
            if step.params.has("0") && !step.params.has("1") && value.isEmpty {
                value = step.params.get("0", "")
            } else {
                fieldName = step.params.get("0", "")
                value = step.params.get("1", value)
            }
        } else {
            value = step.params.get("1", value)
        }
        if fieldName.pyStartsWith("\"") && fieldName.pyEndsWith("\"") {
            fieldName = fieldName.pyDropFirstAndLast()
        }

        // The value comes first, then the target field
        e.append(XMLBuilder.calculation(value))
        if !fieldName.isEmpty {
            let ref = parseFieldReference(fieldName)
            e.append(XMLBuilder.field(ref.field, table: ref.table, repetition: ref.repetition))
        }
        return [e]
    }
}

struct SetFieldByNameHandler: StepHandler {
    var knownLabels: Set<String> { [] }

    func generate(_ step: ParsedStep, _ def: StepDefinition) -> [XElement] {
        var e = XMLBuilder.step(def, step)
        let target = step.params.get("0", "")
        if !target.isEmpty { e.append(XMLBuilder.wrappedCalculation("TargetName", target)) }
        let result = step.params.get("1", "")
        if !result.isEmpty { e.append(XMLBuilder.wrappedCalculation("Result", result)) }
        return [e]
    }
}

/// Strips surrounding straight or curly quotes (after stripping whitespace).
func stripQuotes(_ value: String) -> String {
    let v = value.pyStrip()
    if v.unicodeScalars.count >= 2,
       (v.pyStartsWith("\"") && v.pyEndsWith("\"")) || (v.pyStartsWith("“") && v.pyEndsWith("”")) {
        return v.pyDropFirstAndLast()
    }
    return v
}

/// Whether a script reference is calculated (vs. picked from the list).
/// Python's version crashes on a missing name unless "By name" is specified;
/// that surfaces as `HandlerError.missingScriptName`.
func isCalculatedScript(specified: String?, name: String?) throws(HandlerError) -> Bool {
    if let specified, !specified.isEmpty, specified.pyLower().pyContains("by name") { return true }
    guard let name else { throw .missingScriptName }
    return name.pyStrip().pyStartsWith("$")
}

struct PerformScriptHandler: StepHandler {
    var knownLabels: Set<String> { ["Parameter", "Script", "Specified"] }

    func generate(_ step: ParsedStep, _ def: StepDefinition) -> [XElement] {
        var elements: [XElement] = []
        if step.rawText.pyContains("Specified: From list") {
            elements.append(XMLBuilder.helperCommentStep(step.rawText))
        }
        var e = XMLBuilder.step(def, step)

        let param = step.params.get("Parameter", "")
        if !param.isEmpty {
            e.append(XMLBuilder.calculation(param))
            e.append(XMLBuilder.wrappedCalculation("DisplayCalculation", param))
        }

        var scriptName = step.params.get("Script", step.params.get("0", ""))
        if scriptName.pyStartsWith("\"") && scriptName.pyEndsWith("\"") {
            scriptName = scriptName.pyDropFirstAndLast()
        }
        if step.rawText.pyContains("Calculated:") || scriptName.pyStartsWith("\"") {
            e.append(XMLBuilder.wrappedCalculation("Calculated", scriptName))
        } else {
            // FileMaker corrects the ID on paste
            e.append(XElement("Script", ["name": scriptName, "id": "1"]))
        }
        elements.append(e)
        return elements
    }
}

struct InstallOnTimerScriptHandler: StepHandler {
    var knownLabels: Set<String> { ["Script", "Interval"] }

    func generate(_ step: ParsedStep, _ def: StepDefinition) -> [XElement] {
        var e = XMLBuilder.step(def, step)
        var scriptName = step.params.get("Script", step.params.get("0", ""))
        if scriptName.pyStartsWith("\"") && scriptName.pyEndsWith("\"") {
            scriptName = scriptName.pyDropFirstAndLast()
        }
        if !scriptName.isEmpty { e.append(XElement("Script", ["name": scriptName])) }
        let interval = step.params.get("Interval", step.params.get("1", ""))
        if !interval.isEmpty { e.append(XMLBuilder.wrappedCalculation("Interval", interval)) }
        return [e]
    }
}

struct PerformScriptOnServerHandler: StepHandler {
    var knownLabels: Set<String> { ["Wait for completion", "Parameter", "Specified", "Script"] }

    func generate(_ step: ParsedStep, _ def: StepDefinition) throws(HandlerError) -> [XElement] {
        var elements: [XElement] = []
        // Scripts from the list need IDs we can't resolve
        if step.rawText.pyLower().pyContains("from list") {
            elements.append(XMLBuilder.helperCommentStep(step.rawText))
        }
        var e = XMLBuilder.step(def, step)

        let wait = step.params.get("Wait for completion", "Off")
        e.append(XMLBuilder.state("WaitForCompletion", wait.pyStrip().pyLower() == "on"))

        let param = step.params.get("Parameter", "")
        if !param.isEmpty { e.append(XMLBuilder.calculation(param)) }

        let specified = step.params.get("Specified", "")
        let scriptName = step.params.get("Script", step.params.get("0", ""))
        if try isCalculatedScript(specified: specified, name: scriptName) {
            e.append(XMLBuilder.wrappedCalculation("Calculated", scriptName.pyStrip()))
        } else if !scriptName.isEmpty {
            e.append(XElement("Script", ["name": stripQuotes(scriptName)]))
        }
        elements.append(e)
        return elements
    }
}

struct PerformScriptOnServerWithCallbackHandler: StepHandler {
    var knownLabels: Set<String> { ["Specified", "Parameter", "Callback script specified", "State"] }
    var allowsDuplicateLabels: Bool { true }

    func generate(_ step: ParsedStep, _ def: StepDefinition) throws(HandlerError) -> [XElement] {
        var elements: [XElement] = []
        if step.rawText.pyLower().pyContains("from list") {
            elements.append(XMLBuilder.helperCommentStep(step.rawText))
        }
        var e = XMLBuilder.step(def, step)

        // The two "Parameter:" labels collide in the params, so re-parse the
        // bracketed content in order and split it at the callback boundary.
        let (mainParts, callbackParts) = Self.splitSections(step.rawText)
        let main = Self.parseSection(mainParts)
        let callback = Self.parseSection(callbackParts)

        let mainCalculated = try isCalculatedScript(specified: main.specified, name: main.name)
        let callbackCalculated = try isCalculatedScript(specified: callback.specified, name: callback.name)

        // 1. A calculated main script name comes first
        if mainCalculated, let name = main.name, !name.isEmpty {
            e.append(XMLBuilder.wrappedCalculation("Calculated", name.pyStrip()))
        }
        // 2. CallbackScriptState
        if let state = callback.state, !state.isEmpty {
            e.append(XElement("CallbackScriptState", ["value": state.pyStrip()]))
        }
        // 3. Main script parameter
        if let param = main.parameter, !param.isEmpty {
            e.append(XMLBuilder.calculation(param))
        }
        // 4. A main script from the list comes after the parameter
        if !mainCalculated, let name = main.name, !name.isEmpty {
            e.append(XElement("Script", ["name": stripQuotes(name)]))
        }
        // 5. The callback script
        var cb = XElement("CallbackScript")
        if callbackCalculated, let name = callback.name, !name.isEmpty {
            cb.append(XMLBuilder.wrappedCalculation("Calculated", name.pyStrip()))
        } else if let name = callback.name, !name.isEmpty {
            cb.append(XElement("ScriptName", ["name": stripQuotes(name)]))
        }
        if let param = callback.parameter, !param.isEmpty {
            cb.append(XMLBuilder.wrappedCalculation("ScriptParameter", param))
        }
        e.append(cb)

        elements.append(e)
        return elements
    }

    struct Section {
        var specified: String?
        var name: String?
        var parameter: String?
        var state: String?
    }

    static func splitSections(_ rawText: String) -> ([String], [String]) {
        let s = rawText.scalars
        guard let start = s.pyFind("["), let end = s.lastIndex(of: "]"), end > start else { return ([], []) }
        let content = Array(s[(start + 1)..<end])
        var main: [String] = []
        var callback: [String] = []
        var inCallback = false
        for part in splitTopLevel(content) {
            if let key = splitKeyValue(part).key, key.pyStrip().pyLower() == "callback script specified" {
                inCallback = true
            }
            if inCallback { callback.append(part) } else { main.append(part) }
        }
        return (main, callback)
    }

    static func parseSection(_ parts: [String]) -> Section {
        var section = Section()
        for part in parts {
            let (key, value) = splitKeyValue(part)
            guard let key else {
                section.name = value
                continue
            }
            switch key.pyStrip().pyLower() {
            case "specified", "callback script specified": section.specified = value
            case "parameter": section.parameter = value
            case "state": section.state = value
            default: break
            }
        }
        return section
    }

    /// Splits on `;` outside brackets/parens/braces and quotes.
    static func splitTopLevel(_ text: Scalars) -> [String] {
        var parts: [Scalars] = []
        var current: Scalars = []
        var depth = 0
        var inString = false
        var stringChar: Unicode.Scalar?
        for (i, char) in text.enumerated() {
            if (char == "\"" || char == "'") && (i == 0 || text[i - 1] != "\\") {
                if !inString {
                    inString = true
                    stringChar = char
                } else if char == stringChar {
                    inString = false
                    stringChar = nil
                }
                current.append(char)
                continue
            }
            if inString {
                current.append(char)
                continue
            }
            if "([{".unicodeScalars.contains(char) {
                depth += 1
                current.append(char)
            } else if ")]}".unicodeScalars.contains(char) {
                depth -= 1
                current.append(char)
            } else if char == ";" && depth == 0 {
                parts.append(current)
                current = []
            } else {
                current.append(char)
            }
        }
        if !current.isEmpty { parts.append(current) }
        return parts.map { $0.pyStrip() }.filter { !$0.isEmpty }.map(\.string)
    }

    /// "Key: Value" → (key, value); positional values have no key.
    static func splitKeyValue(_ part: String) -> (key: String?, value: String) {
        let s = part.scalars
        var i = 0
        var inString = false
        var stringChar: Unicode.Scalar?
        while i < s.count {
            let char = s[i]
            if char == "\"" || char == "'" {
                if !inString {
                    inString = true
                    stringChar = char
                } else if char == stringChar {
                    inString = false
                    stringChar = nil
                }
                i += 1
                continue
            }
            if !inString && char == ":" {
                if i + 1 < s.count && s[i + 1] == ":" {
                    i += 2
                    continue
                }
                return (s.pySlice(0, i).pyStrip().string, s.pySlice(i + 1).pyStrip().string)
            }
            i += 1
        }
        return (nil, part.pyStrip())
    }
}
