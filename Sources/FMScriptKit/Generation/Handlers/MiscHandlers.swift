// Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
// SPDX-License-Identifier: GPL-3.0-or-later

// Perform Find, Show Custom Dialog, Open URL, Send Mail, Print, Print Setup,
// Commit Records/Requests, Save Records as PDF, Sort Records by Field

struct PerformFindHandler: StepHandler {
    var knownLabels: Set<String> { ["Restore", "Table"] }

    func generate(_ step: ParsedStep, _ def: StepDefinition) -> [XElement] {
        // Find requests reference fields, which need IDs
        let comment = XMLBuilder.helperCommentStep(step.rawText)
        var e = XMLBuilder.step(def, step)

        // Restore only when specified or when there are other params
        let restore = step.params.get("Restore", "")
        if !restore.isEmpty {
            e.append(XMLBuilder.state("Restore", restore.pyLower() != "false"))
        } else if !step.params.isEmpty {
            e.append(XMLBuilder.state("Restore", true))
        }
        // Simplified query structure; the find criteria aren't converted
        if !step.params.isEmpty {
            e.append(XElement("Query", ["table": step.params.get("Table", "")], children: [
                XElement("RequestRow", ["operation": "Include"]),
            ]))
        }
        return [comment, e]
    }
}

struct ShowCustomDialogHandler: StepHandler {
    var knownLabels: Set<String> { ["Title", "Message", "Default Button", "Button 2", "Button 3", "InputFields"] }

    func generate(_ step: ParsedStep, _ def: StepDefinition) -> [XElement] {
        var elements: [XElement] = []
        // Input fields need IDs (Python checks for "Field" in the params' repr)
        if step.params.items.contains(where: { $0.key.pyContains("Field") || $0.value.pyContains("Field") }) {
            elements.append(XMLBuilder.helperCommentStep(step.rawText))
        }
        // Note: the Python handler ignores the // (disabled) prefix here
        var e = XMLBuilder.step(def.id, def.xmlStepName, enabled: def.enableDefault)

        let title = step.params.get("Title", step.params.get("0", ""))
        if !title.isEmpty { e.append(XMLBuilder.wrappedCalculation("Title", title)) }
        let message = step.params.get("Message", step.params.get("1", ""))
        if !message.isEmpty { e.append(XMLBuilder.wrappedCalculation("Message", message)) }

        // Always three buttons; only the first commits. Defaults match
        // FileMaker: "OK", "Cancel" and an empty third button.
        var buttons = XElement("Buttons")
        for (text, commit) in [
            (step.params.get("Default Button", "\"OK\""), true),
            (step.params.get("Button 2", "\"Cancel\""), false),
            (step.params.get("Button 3", ""), false),
        ] {
            var button = XElement("Button", ["CommitState": commit ? "True" : "False"])
            if !text.isEmpty { button.append(XMLBuilder.calculation(text)) }
            buttons.append(button)
        }
        e.append(buttons)

        let inputFields = step.params.get("InputFields", "")
        if !inputFields.isEmpty {
            var fields = XElement("InputFields")
            for name in inputFields.pySplit(",") {
                fields.append(XElement("InputField", children: [XMLBuilder.field(name.pyStrip().string)]))
            }
            e.append(fields)
        }
        elements.append(e)
        return elements
    }
}

struct OpenURLHandler: StepHandler {
    var knownLabels: Set<String> { ["With dialog"] }

    func generate(_ step: ParsedStep, _ def: StepDefinition) -> [XElement] {
        var e = XMLBuilder.step(def, step)
        e.append(noInteract(step))
        let url = step.params.get("0", "")
        if !url.isEmpty { e.append(XMLBuilder.calculation(url)) }
        return [e]
    }
}

struct SendMailHandler: StepHandler {
    var knownLabels: Set<String> { ["With dialog", "To", "CC", "Cc", "BCC", "Bcc", "Subject", "Message"] }

    func generate(_ step: ParsedStep, _ def: StepDefinition) -> [XElement] {
        var e = XMLBuilder.step(def, step)
        e.append(noInteract(step))

        for (element, value) in [
            ("To", step.params.get("To", "")),
            ("Cc", step.params.get("CC", step.params.get("Cc", ""))),
            ("Bcc", step.params.get("BCC", step.params.get("Bcc", ""))),
        ] where !value.isEmpty {
            e.append(XElement(element, ["UseFoundSet": "False"], children: [XMLBuilder.calculation(value)]))
        }
        for label in ["Subject", "Message"] {
            let value = step.params.get(label, "")
            if !value.isEmpty { e.append(XMLBuilder.wrappedCalculation(label, value)) }
        }

        e.append(XMLBuilder.state("MultipleEmails", false))
        // The first positional param is usually the send method
        e.append(XMLBuilder.state("SendViaSMTP", step.params.get("0", "").pyLower().pyContains("smtp")))
        e.append(XElement("SMTPEncryptionType", ["type": "SMTPEncryptionNone"]))
        e.append(XElement("SMTPAuthenticationType", ["type": "SMTPAuthenticationNone"]))
        return [e]
    }
}

struct PrintHandler: StepHandler {
    var knownLabels: Set<String> { ["With dialog", "Restore"] }

    func generate(_ step: ParsedStep, _ def: StepDefinition) -> [XElement] {
        var e = XMLBuilder.step(def, step)
        e.append(noInteract(step))
        e.append(XMLBuilder.state("Restore", !step.params.get("Restore", "").isEmpty))
        // PrintSettings/PlatformData can't be generated from text; FileMaker
        // uses its default print settings
        return [e]
    }
}

struct PrintSetupHandler: StepHandler {
    var knownLabels: Set<String> { ["With dialog"] }

    func generate(_ step: ParsedStep, _ def: StepDefinition) -> [XElement] {
        var e = XMLBuilder.step(def, step)
        e.append(noInteract(step))
        e.append(XMLBuilder.state("Restore", false))
        return [e]
    }
}

struct CommitRecordsRequestsHandler: StepHandler {
    var knownLabels: Set<String> { ["With dialog"] }

    func generate(_ step: ParsedStep, _ def: StepDefinition) -> [XElement] {
        var e = XMLBuilder.step(def, step)
        let withDialog = step.params.get("With dialog", "")
        let option = step.params.get("0", "")

        let noInteract: Bool
        if option.pyLower().pyContains("no dialog") {
            noInteract = true
        } else if !withDialog.isEmpty {
            noInteract = withDialog.pyLower() == "off"
        } else {
            noInteract = false
        }
        let forceCommit = !option.isEmpty && option.pyLower().pyContains("force")

        e.append(XMLBuilder.state("NoInteract", noInteract))
        e.append(XMLBuilder.state("Option", forceCommit))
        e.append(XMLBuilder.state("ESSForceCommit", forceCommit))
        return [e]
    }
}

struct SaveRecordsAsPDFHandler: StepHandler {
    var knownLabels: Set<String> { ["With dialog", "Create folders"] }

    func generate(_ step: ParsedStep, _ def: StepDefinition) -> [XElement] {
        var e = XMLBuilder.step(def, step)
        let raw = step.rawText.pyLower()

        let withDialog = step.params.get("With dialog", "")
        let noInteract: Bool
        if raw.pyContains("no dialog") {
            noInteract = true
        } else if !withDialog.isEmpty {
            noInteract = withDialog.pyLower() == "off"
        } else {
            noInteract = false
        }

        e.append(XMLBuilder.state("NoInteract", noInteract))
        e.append(XMLBuilder.state("Option", raw.pyContains("append")))
        e.append(XMLBuilder.state("CreateDirectories", step.params.get("Create folders", "Off").pyLower() == "on"))
        e.append(XMLBuilder.state("Restore", raw.pyContains("restore")))
        e.append(XMLBuilder.state("AutoOpen", raw.pyContains("automatically open")))
        e.append(XMLBuilder.state("CreateEmail", raw.pyContains("create email")))

        // Optional output path
        if var path = step.params.values.first(where: { $0.pyContains("$filepath") }) {
            if (path.pyStartsWith("\"") && path.pyEndsWith("\"")) || (path.pyStartsWith("“") && path.pyEndsWith("”")) {
                path = path.pyDropFirstAndLast()
            }
            e.append(XMLBuilder.text("UniversalPathList", path))
        }

        let source = raw.pyContains("current record") ? "CurrentRecord"
            : raw.pyContains("blank record") ? "BlankRecord" : "RecordsBeingBrowsed"
        var appearance: String?
        if raw.pyContains("blank record") {
            if raw.pyContains("as formatted") { appearance = "AsFormatted" }
            else if raw.pyContains("with boxes") { appearance = "WithBoxes" }
            else if raw.pyContains("with underlines") { appearance = "WithUnderlines" }
            else if raw.pyContains("with placeholder text") { appearance = "WithPlaceholderText" }
        }
        e.append(Self.pdfOptions(source: source, appearance: appearance))
        return [e]
    }

    static func pdfOptions(source: String, appearance: String?) -> XElement {
        var options = XElement("PDFOptions", ["source": source])
        if let appearance { options[attribute: "appearance"] = appearance }
        options.append(XElement("Document", children: [
            XElement("Pages", ["AllPages": "True"], children: [
                XMLBuilder.wrappedCalculation("NumberFrom", "1"),
                XElement("PageRange", children: [
                    XMLBuilder.wrappedCalculation("From", "1"),
                    XMLBuilder.wrappedCalculation("To", "1"),
                ]),
            ]),
        ]))
        options.append(XElement("Security", [
            "allowScreenReader": "True",
            "enableCopying": "True",
            "controlEditing": "AnyExceptExtractingPages",
            "controlPrinting": "HighResolution",
            "requireControlEditPassword": "False",
            "requireOpenPassword": "False",
        ]))
        options.append(XElement("View", ["magnification": "100", "pageLayout": "SinglePage", "show": "PagesPanelAndPage"]))
        return options
    }
}

struct SortRecordsByFieldHandler: StepHandler {
    var knownLabels: Set<String> { [] }

    private static let orders = [
        "descending": "SortDescending",
        "ascending": "SortAscending",
        "associated value list": "SortValueList",
    ]

    func generate(_ step: ParsedStep, _ def: StepDefinition) -> [XElement] {
        var elements: [XElement] = []
        var e = XMLBuilder.step(def, step)

        let order = step.params.get("0", "").pyStrip().pyLower()
        e.append(XElement("SortRecordsByField", ["value": Self.orders[order] ?? "SortAscending"]))

        let fieldRef = step.params.get("1", "").pyStrip()
        if !fieldRef.isEmpty {
            // The sort field needs IDs we can't resolve
            elements.append(XMLBuilder.helperCommentStep(step.rawText))
            let ref = parseFieldReference(fieldRef)
            e.append(XMLBuilder.field(ref.field, table: ref.table, repetition: ref.repetition))
        }
        elements.append(e)
        return elements
    }
}
