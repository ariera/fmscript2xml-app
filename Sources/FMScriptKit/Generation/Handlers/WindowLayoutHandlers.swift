// Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
// SPDX-License-Identifier: GPL-3.0-or-later

// Windows (New Window, Close Window, Enter Preview Mode) and navigation
// (Go to Layout, Go to Record/Request/Page, Go to Related Record)

struct NewWindowHandler: StepHandler {
    var knownLabels: Set<String> { ["Name", "Height", "Width", "Top", "Left", "Style"] }

    // Style → (Style attr, Close, Minimize, Maximize, Resize, Styles bitmask)
    private static let styles: [String: [String]] = [
        "Document": ["Document", "Yes", "Yes", "Yes", "Yes", "0"],
        "Floating Document": ["Floating", "Yes", "No", "No", "Yes", "2147549952"],
        "Dialog": ["Dialog", "Yes", "No", "Yes", "Yes", "0"],
        "Card": ["Card", "Yes", "No", "No", "No", "0"],
    ]

    func generate(_ step: ParsedStep, _ def: StepDefinition) -> [XElement] {
        var e = XMLBuilder.step(def, step)
        e.append(XElement("LayoutDestination", ["value": "CurrentLayout"]))
        for (label, element) in [("Name", "Name"), ("Height", "Height"), ("Width", "Width"),
                                 ("Top", "DistanceFromTop"), ("Left", "DistanceFromLeft")] {
            let value = step.params.get(label, "")
            if !value.isEmpty { e.append(XMLBuilder.wrappedCalculation(element, value)) }
        }
        let s = Self.styles[step.params.get("Style", "Document")] ?? Self.styles["Document"]!
        e.append(XElement("NewWndStyles", [
            "Style": s[0], "Close": s[1], "Minimize": s[2], "Maximize": s[3], "Resize": s[4], "Styles": s[5],
        ]))
        return [e]
    }
}

struct CloseWindowHandler: StepHandler {
    var knownLabels: Set<String> { ["Name"] }

    func generate(_ step: ParsedStep, _ def: StepDefinition) -> [XElement] {
        var e = XMLBuilder.step(def, step)
        // The window name is "Name: <calc>" or a bare positional value.
        // "Current Window"/"Current file" are options, not window names.
        var windowName = step.params.get("Name", "")
        if windowName.isEmpty {
            let positional = step.params.get("0", "")
            if !["current window", "current", "current file"].contains(positional.pyLower()) {
                windowName = positional
            }
        }
        // True for the current window or with the "Current file" option
        let hasCurrentFile = step.rawText.pyLower().pyContains("current file")
        e.append(XMLBuilder.state("LimitToWindowsOfCurrentFile", !(!windowName.isEmpty && !hasCurrentFile)))
        if !windowName.isEmpty {
            e.append(XElement("Window", ["value": "ByName"]))
            e.append(XMLBuilder.wrappedCalculation("Name", windowName))
        } else {
            e.append(XElement("Window", ["value": "Current"]))
        }
        return [e]
    }
}

struct EnterPreviewModeHandler: StepHandler {
    var knownLabels: Set<String> { ["Pause"] }

    func generate(_ step: ParsedStep, _ def: StepDefinition) -> [XElement] {
        var e = XMLBuilder.step(def, step)
        e.append(XMLBuilder.state("Pause", step.params.get("Pause", "Off").pyLower() == "on"))
        return [e]
    }
}

struct GoToLayoutHandler: StepHandler {
    var knownLabels: Set<String> { ["Layout", "Animation"] }

    func generate(_ step: ParsedStep, _ def: StepDefinition) -> [XElement] {
        // Named layouts need IDs: keep the original text at hand
        let comment = XMLBuilder.helperCommentStep(step.rawText)
        var e = XMLBuilder.step(def, step)

        var layoutName = step.params.get("Layout", step.params.get("0", ""))
        if isCalculatedReference(layoutName) {
            e.append(XElement("LayoutDestination", ["value": "LayoutNameByCalc"]))
            e.append(XMLBuilder.wrappedCalculation("Layout", layoutName))
        } else {
            e.append(XElement("LayoutDestination", ["value": "SelectedLayout"]))
            if layoutName.pyStartsWith("\"") && layoutName.pyEndsWith("\"") {
                layoutName = layoutName.pyDropFirstAndLast()
            }
            e.append(XMLBuilder.layout(layoutName))
        }

        let animation = step.params.get("Animation", "")
        if !animation.isEmpty && animation != "None" {
            e.append(XElement("Animation", ["value": animation]))
        }
        return [comment, e]
    }
}

struct GoToRecordRequestPageHandler: StepHandler {
    var knownLabels: Set<String> { ["With dialog", "Exit after last"] }

    func generate(_ step: ParsedStep, _ def: StepDefinition) -> [XElement] {
        var e = XMLBuilder.step(def, step)
        e.append(noInteract(step))
        if let exitAfterLast = step.params["Exit after last"] {
            e.append(XMLBuilder.state("Exit", exitAfterLast.pyLower() == "on"))
        }

        var location = step.params.get("0", "")
        var calcValue = ""
        if step.params.has("With dialog") {
            calcValue = location
            location = "ByCalculation"
        } else if !location.isEmpty && !["First", "Last", "Next", "Previous"].contains(location) {
            calcValue = location
            location = "ByCalculation"
        }
        if location.isEmpty { location = "First" }

        e.append(XElement("RowPageLocation", ["value": location]))
        if location == "ByCalculation" && !calcValue.isEmpty {
            e.append(XMLBuilder.calculation(calcValue))
        }
        return [e]
    }
}

struct GoToRelatedRecordHandler: StepHandler {
    var knownLabels: Set<String> { ["Using layout", "Layout", "From table", "Table"] }

    func generate(_ step: ParsedStep, _ def: StepDefinition) -> [XElement] {
        var e = XMLBuilder.step(def, step)

        var matchAll = false
        var showInNewWindow = false
        let optionText = step.params.get("0", "")
        if !optionText.isEmpty {
            let lowered = optionText.pyLower()
            if lowered.pyContains("show all") { matchAll = true }
            if lowered.pyContains("show in new window") { showInNewWindow = true }
        }
        e.append(XMLBuilder.state("Option", false))
        e.append(XMLBuilder.state("MatchAllRecords", matchAll))
        e.append(XMLBuilder.state("ShowInNewWindow", showInNewWindow))
        e.append(XMLBuilder.state("Restore", true))

        // LayoutDestination now; the Layout itself goes after Table
        let layoutValue = step.params.get("Using layout", step.params.get("Layout", ""))
        var layout: XElement?
        if !layoutValue.isEmpty {
            let calculated = isCalculatedReference(layoutValue)
            e.append(XElement("LayoutDestination", ["value": calculated ? "LayoutNameByCalc" : "SelectedLayout"]))
            layout = calculated
                ? XMLBuilder.wrappedCalculation("Layout", layoutValue)
                : XMLBuilder.layout(layoutValue.pyDropFirstAndLast())
        }

        if !optionText.isEmpty {
            e.append(XMLBuilder.wrappedCalculation("Name", "/*\(optionText)*/"))
        }

        e.append(XElement("NewWndStyles", [
            "Style": "Document", "Close": "Yes", "Minimize": "Yes", "Maximize": "Yes", "Resize": "Yes",
        ]))

        var table = step.params.get("From table", step.params.get("Table", ""))
        if !table.isEmpty {
            if (table.pyStartsWith("\"") && table.pyEndsWith("\""))
                || (table.pyStartsWith("“") && table.pyEndsWith("”")) {
                table = table.pyDropFirstAndLast()
            }
            e.append(XMLBuilder.table(table))
        }

        if let layout { e.append(layout) }
        return [e]
    }
}
