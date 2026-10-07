// Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
// SPDX-License-Identifier: GPL-3.0-or-later

// Comment, Set Variable, control flow (If/Else If/Exit Script/Pause/Resume Script)

struct CommentHandler: StepHandler {
    var knownLabels: Set<String> { ["Text"] }

    func generate(_ step: ParsedStep, _ def: StepDefinition) -> [XElement] {
        var e = XMLBuilder.step(def, step)
        let text = step.isComment ? step.commentText : step.params.get("Text", step.params.get("0", ""))
        e.append(XMLBuilder.text("Text", text))
        return [e]
    }
}

struct SetVariableHandler: StepHandler {
    var knownLabels: Set<String> { ["Name", "Value", "Repetition"] }

    func generate(_ step: ParsedStep, _ def: StepDefinition) -> [XElement] {
        var e = XMLBuilder.step(def, step)

        // Variable name, keeping the $ prefix
        var varName = step.params.get("Name", "")
        if varName.isEmpty { varName = step.params.get("0", "") }
        // Not found, or no $: look for a $variable in the raw text
        if varName.isEmpty || (!varName.pyStartsWith("$") && !step.rawText.isEmpty) {
            if let match = Self.firstVariable(in: step.rawText) { varName = match }
        }
        if !varName.isEmpty && !varName.pyStartsWith("$") { varName = "$" + varName }
        e.append(XMLBuilder.text("Name", varName))

        // Value, exactly as written; an empty value is the empty string ""
        var value = step.params.get("Value", step.params.get("1", ""))
        if value.isEmpty { value = "\"\"" }
        e.append(XMLBuilder.wrappedCalculation("Value", value))

        e.append(XMLBuilder.wrappedCalculation("Repetition", step.params.get("Repetition", "1")))
        return [e]
    }

    /// `re.search(r'\$[a-zA-Z0-9_]+', text)`
    static func firstVariable(in text: String) -> String? {
        let s = text.scalars
        func isWordASCII(_ c: Unicode.Scalar) -> Bool {
            ("a"..."z").contains(c) || ("A"..."Z").contains(c) || ("0"..."9").contains(c) || c == "_"
        }
        var i = 0
        while i < s.count {
            if s[i] == "$", i + 1 < s.count, isWordASCII(s[i + 1]) {
                var j = i + 1
                while j < s.count, isWordASCII(s[j]) { j += 1 }
                return s.pySlice(i, j).string
            }
            i += 1
        }
        return nil
    }
}

/// If and Else If.
struct IfHandler: StepHandler {
    var knownLabels: Set<String> { ["Calculation"] }

    func generate(_ step: ParsedStep, _ def: StepDefinition) -> [XElement] {
        var e = XMLBuilder.step(def, step)
        var calc = step.params.get("Calculation", step.params.get("0", ""))
        if calc.isEmpty, let first = step.params.values.first { calc = first }
        e.append(XMLBuilder.calculation(calc))
        return [e]
    }
}

struct ExitScriptHandler: StepHandler {
    var knownLabels: Set<String> { ["Text Result", "TextResult", "Result"] }

    func generate(_ step: ParsedStep, _ def: StepDefinition) -> [XElement] {
        var e = XMLBuilder.step(def, step)
        var textResult = pyOr(
            step.params["Text Result"], step.params["TextResult"], step.params["Result"], step.params.get("0", "")
        )
        if textResult.isEmpty && !step.rawText.isEmpty, let match = Self.textResult(in: step.rawText) {
            textResult = match.pyStrip()
        }
        if !textResult.isEmpty {
            e.append(XMLBuilder.calculation(textResult))
        }
        return [e]
    }

    /// `re.search(r'Text Result:\s*(.+?)(?:\s*\]|$)', text).group(1)`
    static func textResult(in text: String) -> String? {
        let s = text.scalars
        let literal = "Text Result:".scalars
        var from = 0
        while let p = s.pyFind(literal, from: from) {
            let afterLiteral = p + literal.count
            var maxSpace = afterLiteral
            while maxSpace < s.count, s[maxSpace].pyIsSpace { maxSpace += 1 }
            // \s* is greedy: try the longest whitespace run first
            var groupStart = maxSpace
            while groupStart >= afterLiteral {
                // (.+?) is lazy: shortest run of non-newline characters first
                var end = groupStart + 1
                while end <= s.count, s[end - 1] != "\n" {
                    if Self.tailMatches(s, at: end) { return s.pySlice(groupStart, end).string }
                    end += 1
                }
                groupStart -= 1
            }
            from = p + 1
        }
        return nil
    }

    /// `(?:\s*\]|$)` at `q`.
    private static func tailMatches(_ s: Scalars, at q: Int) -> Bool {
        var k = q
        while k < s.count, s[k].pyIsSpace { k += 1 }
        if k < s.count, s[k] == "]" { return true }
        return q == s.count || (q == s.count - 1 && s[q] == "\n")
    }
}

struct PauseResumeScriptHandler: StepHandler {
    var knownLabels: Set<String> { ["Duration (seconds)"] }

    func generate(_ step: ParsedStep, _ def: StepDefinition) -> [XElement] {
        var e = XMLBuilder.step(def, step)
        // "Duration (seconds): <calc>" pauses for a duration; anything else
        // (e.g. "Indefinitely" or no option) pauses indefinitely.
        let duration = step.params.get("Duration (seconds)", "")
        e.append(XElement("PauseTime", ["value": duration.isEmpty ? "Indefinitely" : "ForDuration"]))
        if !duration.isEmpty { e.append(XMLBuilder.calculation(duration)) }
        return [e]
    }
}

struct SetErrorCaptureHandler: StepHandler {
    var knownLabels: Set<String> { [] }

    func generate(_ step: ParsedStep, _ def: StepDefinition) -> [XElement] {
        var e = XMLBuilder.step(def, step)
        var stateValue = step.params.get("0", "On")
        if stateValue.isEmpty { stateValue = "On" }
        e.append(XMLBuilder.state("Set", stateValue.pyLower() == "on"))
        return [e]
    }
}
