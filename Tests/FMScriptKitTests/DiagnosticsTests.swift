// Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
// SPDX-License-Identifier: GPL-3.0-or-later

@testable import FMScriptKit
import Testing

@Suite struct SuggesterTests {
    let suggester = StepNameSuggester(names: StepRegistry.shared.stepNames)

    @Test(arguments: [
        ("Go to Layuot", "Go to Layout"),       // transposition
        ("Set Varible", "Set Variable"),        // deletion
        ("set variable", "Set Variable"),       // case
        ("Set  Variable", "Set Variable"),      // whitespace
        ("Exit Scrpt", "Exit Script"),
        ("Commit Records", "Commit Records/Requests"),  // alias
        ("Go to Record", "Go to Record/Request/Page"),  // alias
        ("Perfom Find", "Perform Find"),
        ("End if", "End If"),
        ("Show Custom Dialog…", "Show Custom Dialog"),  // trailing ellipsis
        ("Set Feild", "Set Field"),
        ("Insert From URL", "Insert from URL"),
    ])
    func suggests(_ typo: String, _ expected: String) {
        #expect(suggester.suggestions(for: typo).first == expected)
    }

    @Test func noSuggestionForUnrelatedNames() {
        #expect(suggester.suggestions(for: "Perform JavaScript in Web Viewer").isEmpty)
        #expect(suggester.suggestions(for: "Lorem ipsum dolor sit amet").isEmpty)
    }

    @Test func upToThreeAlternatives() {
        let s = suggester.suggestions(for: "Go to Fiel")
        #expect(s.first == "Go to Field")
        #expect(s.count <= 3)
    }

    @Test func damerauLevenshtein() {
        func d(_ a: String, _ b: String) -> Int { StepNameSuggester.distance(a.scalars, b.scalars) }
        #expect(d("layout", "layuot") == 1)
        #expect(d("abc", "abc") == 0)
        #expect(d("", "abc") == 3)
        #expect(d("kitten", "sitting") == 3)
    }
}

@Suite struct DiagnosticsTests {
    let converter = Converter()

    @Test func unknownStepWithSuggestionAndFix() throws {
        let text = "Beep\n  Go to Layuot [ \"Invoices\" ]"
        let result = converter.convert(text)
        #expect(result.status == .failed)
        #expect(result.xml == nil)
        let d = try #require(result.errors.first)
        #expect(d.code == .unknownStep)
        #expect(d.lines == 2...2)
        #expect(d.message == "Unknown step “Go to Layuot”. Did you mean “Go to Layout”?")
        let fixed = try #require(d.suggestion?.apply(to: text))
        #expect(fixed == "Beep\n  Go to Layout [ \"Invoices\" ]")
        #expect(converter.convert(fixed).status != .failed)
    }

    @Test func continueOnErrorKeepsTheRest() {
        let result = converter.convert("Beep\nGo to Layuot\nBeep", policy: .continueOnError)
        #expect(result.xml != nil)
        #expect(result.status == .warnings)
        #expect(result.convertedStepCount == 2)
    }

    @Test func unknownParameterWithSuggestion() throws {
        let text = "Set Variable [ $x ; Valeu: 1 ]"
        let result = converter.convert(text)
        #expect(result.status == .warnings)
        let d = try #require(result.warnings.first)
        #expect(d.code == .unknownParameter)
        #expect(d.suggestion?.replacement == "Value:")
        #expect(d.suggestion?.apply(to: text) == "Set Variable [ $x ; Value: 1 ]")
    }

    @Test func validButUnconvertedLabelsAreSilent() {
        #expect(converter.convert("If [ $x ; Collapsed: ON ]\nElse [ Collapsed: OFF ; Collapsed: OFF ]\nEnd If").diagnostics.isEmpty)
        #expect(converter.convert("New Window [ Style: Document ; Name: \"w\" ; Toolbar: No ; Menu: No ]").diagnostics.isEmpty)
    }

    @Test func layoutnameOnGoToLayoutIsFlagged() {
        let d = converter.convert("Go to Layout [ Layoutname: $l ]").warnings
        #expect(d.map(\.code) == [.unknownParameter])
        #expect(d.first?.suggestion?.replacement == "Layout:")
    }

    @Test func genericStepsAcceptAnyLabel() {
        #expect(converter.convert("Insert from URL [ Select ; With dialog: Off ; Target: $r ; \"https://x\" ]").status == .ok)
    }

    @Test func duplicateParameter() {
        let result = converter.convert("Show Custom Dialog [ Title: \"a\" ; Title: \"b\" ]")
        #expect(result.diagnostics.map(\.code) == [.duplicateParameter])
        #expect(result.status == .ok)
        #expect(converter.convert(
            "Perform Script on Server with Callback [ Specified: From list ; “A” ; Parameter: 1 ; Callback script specified: From list ; “B” ; Parameter: 2 ; State: Continue ]"
        ).warnings.isEmpty)
    }

    @Test func idLeftBlankIsInfo() {
        let result = converter.convert("Go to Layout [ \"Invoices\" ]")
        #expect(result.status == .ok)
        #expect(result.diagnostics.map(\.code) == [.idLeftBlank])
        #expect(result.diagnostics[0].severity == .info)
    }

    @Test func diagnosticsAreSortedByLine() {
        let result = converter.convert("Bep\n]\nGo to Layuot", policy: .continueOnError)
        #expect(result.diagnostics.map(\.lines.lowerBound) == [1, 2, 3])
    }
}

@Suite struct SourceMapTests {
    let converter = Converter()

    @Test func helperCommentMapsToTheSameStep() throws {
        let result = converter.convert("Beep\nGo to Layout [ \"Invoices\" ]\n# done")
        #expect(result.steps.map(\.xmlSteps) == [0..<1, 1..<3, 3..<4])
        let layout = result.steps[1]
        #expect(layout.handler == "GoToLayoutHandler")
        let span = try #require(result.xmlTextRange(for: layout))
        let text = result.previewXML[span]
        #expect(text.hasPrefix("<Step enable=\"True\" id=\"89\" name=\"Comment\">"))
        #expect(text.hasSuffix("</Step>"))
        #expect(text.contains("<Layout name=\"Invoices\"/>"))
        #expect(result.trace(forLine: 2)?.stepName == "Go to Layout")
    }

    @Test func multiLineStepsCoverAllTheirLines() {
        let result = converter.convert("Set Variable [ $x ; Value: Let ( [\n a = 1\n] ; a ) ]\nBeep")
        #expect(result.steps.map(\.sourceLines) == [1...3, 4...4])
        #expect(result.trace(forLine: 2)?.stepName == "Set Variable")
    }

    @Test func compactFallbackHasRangesToo() {
        let result = converter.convert("Set Web Viewer [ Action (custom): Reset ]\nBeep")
        #expect(result.xmlStepRanges.count == 2)
        #expect(result.previewXML[result.xmlTextRange(forStep: 1)] == "<Step enable=\"True\" id=\"93\" name=\"Beep\" />")
    }
}
