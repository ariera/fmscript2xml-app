// Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
// SPDX-License-Identifier: GPL-3.0-or-later

// Ported from the Python tests/test_parser.py, plus source-range checks (D8).

@testable import FMScriptKit
import Testing

@Suite struct ParserTests {
    let parser = Parser()

    @Test func simpleStep() {
        let steps = parser.parse("Comment")
        #expect(steps.count == 1)
        #expect(steps[0].name == "Comment")
        #expect(steps[0].params.isEmpty)
    }

    @Test func stepWithParams() {
        let steps = parser.parse("Set Variable [ $var ; Value: 1 ]")
        #expect(steps.count == 1)
        #expect(steps[0].name == "Set Variable")
        #expect(steps[0].params.items.map { "\($0.key)=\($0.value)" } == ["0=$var", "Value=1"])
    }

    @Test func comment() {
        let steps = parser.parse("# This is a comment")
        #expect(steps.count == 1)
        #expect(steps[0].isComment)
        #expect(steps[0].name == "Comment")
        #expect(steps[0].commentText == " This is a comment")
    }

    @Test func commentKeepsIndentationAfterHash() {
        let steps = parser.parse("\t#   indented")
        #expect(steps[0].commentText == "   indented")
        #expect(steps[0].rawText == "\t#   indented")
    }

    @Test func multipleSteps() {
        let steps = parser.parse("""
        Set Variable [ $var ; Value: 1 ]
        If [ $var > 0 ]
            Exit Script
        End If
        """)
        #expect(steps.map(\.name) == ["Set Variable", "If", "Exit Script", "End If"])
        #expect(steps.map(\.lines) == [1...1, 2...2, 3...3, 4...4])
    }

    @Test func nestedBrackets() {
        let steps = parser.parse("Set Variable [ $result ; Value: Get ( ScriptParameter ) ]")
        #expect(steps[0].params["Value"] == "Get ( ScriptParameter )")
    }

    @Test func semicolonsInsideFunctionCallsDontSplit() {
        let steps = parser.parse(#"Set Variable [ $id ; Value: JSONGetElement ( $r ; "[" & $i & "].id" ) ]"#)
        #expect(steps[0].params["Value"] == #"JSONGetElement ( $r ; "[" & $i & "].id" )"#)
    }

    @Test func multilineStringKeepsLineBreaks() {
        let steps = parser.parse("Set Variable [ $sql ; Value: \"SELECT a\n    FROM b\" ]\nBeep")
        #expect(steps.map(\.name) == ["Set Variable", "Beep"])
        #expect(steps[0].params["Value"] == "\"SELECT a\n    FROM b\"")
        #expect(steps[0].lines == 1...2)
        #expect(steps[1].lines == 3...3)
    }

    @Test func multilineCalcKeepsLineBreaksAfterLineComment() {
        let steps = parser.parse("Set Variable [ $x ; Value: 1 & // first [ part\n    2 ]\nBeep")
        #expect(steps.map(\.name) == ["Set Variable", "Beep"])
        #expect(steps[0].params["Value"] == "1 & // first [ part\n    2")
    }

    @Test func commentsHideBracketsAndSeparators() {
        let steps = parser.parse("""
        Set Variable [ $a ; Value: 1 /* see [ ; x: y */ ]
        Set Variable [ $b ; Value: 2 // note: b [c] ]
        Beep
        """)
        #expect(steps.map(\.name) == ["Set Variable", "Set Variable", "Beep"])
        #expect(steps[0].params == StepParams(["0": "$a", "Value": "1 /* see [ ; x: y */"]))
        #expect(steps[1].params == StepParams(["0": "$b", "Value": "2 // note: b [c]"]))
    }

    @Test func trailingLineCommentBeforeStepClose() {
        let steps = parser.parse("If [ Get ( WindowMode ) = 1  // in FIND mode ]\nEnd If")
        #expect(steps.map(\.name) == ["If", "End If"])
        #expect(steps[0].params == StepParams(["0": "Get ( WindowMode ) = 1  // in FIND mode"]))
    }

    @Test func trailingLineCommentBeforeNextParam() {
        let steps = parser.parse("Set Field By Name [ Specify target field: ON ; $f // the target ; $id ]")
        #expect(steps[0].params == StepParams(["Specify target field": "ON", "0": "$f // the target", "1": "$id"]))
    }

    @Test func tableReferenceColonsAreNotKeySeparators() {
        let steps = parser.parse("Set Field [ Customers::Name ; \"Ada\" ]")
        #expect(steps[0].params == StepParams(["0": "Customers::Name", "1": "\"Ada\""]))
    }

    @Test func bracketsInStringLiteralsAndNames() {
        let steps = parser.parse("""
        If [ Left ( $j ; 1 ) ≠ "[" ]
        Go to Layout [ “Odd ] name” ]
        End If
        """)
        #expect(steps.map(\.name) == ["If", "Go to Layout", "End If"])
        #expect(steps[1].params["0"] == "“Odd ] name”")
    }

    @Test func disabledSteps() {
        let steps = parser.parse("// Set Variable [ $x ; Value: 1 ]\n//\nBeep")
        #expect(steps.count == 2)
        #expect(steps[0].isDisabled)
        #expect(steps[0].name == "Set Variable")
        #expect(!steps[1].isDisabled)
    }

    @Test func htmlEntitiesOnTheFirstLine() {
        let steps = parser.parse("Set Field [ &lt;Table Missing&gt;::Name ; 1 ]")
        #expect(steps[0].params == StepParams(["0": "<Table Missing>::Name", "1": "1"]))
    }

    @Test func duplicateLabelsAreRecorded() {
        let steps = parser.parse("Show Custom Dialog [ Title: \"a\" ; Title: \"b\" ]")
        #expect(steps[0].params["Title"] == "\"b\"")
        #expect(steps[0].duplicateKeys == ["Title"])
    }

    @Test func strayContinuationLinesAreSkippedWithAWarning() {
        let out = parser.parseWithDiagnostics("Beep\n) ]\n   123\nBeep")
        #expect(out.steps.map(\.lines) == [1...1, 4...4])
        #expect(out.diagnostics.map(\.code) == [.skippedLine, .skippedLine])
        #expect(out.diagnostics.map(\.lines) == [2...2, 3...3])
    }

    @Test func ellipsisTruncationClosesBrackets() {
        let out = parser.parseWithDiagnostics("If [ Let ( [ x = 1 ; y = 2 ] ; x…\nEnd If")
        #expect(out.steps.map(\.name) == ["If", "End If"])
        #expect(out.steps[0].rawText == "If [ Let ( [ x = 1 ; y = 2 ] ; x…]")
        #expect(out.diagnostics.map(\.code) == [.truncatedLine])
    }

    @Test func unclosedBracketSwallowsTheRest() {
        let out = parser.parseWithDiagnostics("Set Variable [ $x ; Value: Let ( [ a = 1 ; a )\nBeep\nBeep")
        #expect(out.steps.count == 1)
        #expect(out.steps[0].lines == 1...3)
        #expect(out.diagnostics.map(\.code) == [.unbalancedBrackets])
        #expect(out.diagnostics[0].lines == 1...3)
    }

    @Test func positionalKeysCountDigitKeys() {
        let (params, _) = Parser.parseParams("a ; Label: b ; c".scalars)
        #expect(params.items.map(\.key) == ["0", "Label", "1"])
    }
}

@Suite struct CalcScannerTests {
    @Test func stateCarriesAcrossLines() {
        var s = CalcScanner()
        #expect(s.bracketBalance("Set Variable [ $x ; Value: \"open [".scalars) == 1)
        #expect(s.state == .string)
        #expect(s.bracketBalance("still ] in string\" ]".scalars) == -1)
        #expect(s.state == .code)
    }

    @Test func lineCommentEndsAtSemicolonOrUnopenedBracket() {
        var s = CalcScanner()
        let chars = s.codeChars("a // x [y] ; b ]".scalars).map(\.char)
        #expect(String(String.UnicodeScalarView(chars)) == "a ; b ]")
    }
}
