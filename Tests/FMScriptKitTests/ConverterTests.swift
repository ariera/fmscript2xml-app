// Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
// SPDX-License-Identifier: GPL-3.0-or-later

// Ported from the Python test_converter.py, test_generator.py,
// test_registry.py and test_edge_cases*.py, plus XML output details.

@testable import FMScriptKit
import Testing

@Suite struct ConverterTests {
    let converter = Converter()

    func xml(_ text: String) throws -> String {
        try converter.convertToXML(text)
    }

    @Test func simpleScript() throws {
        let out = try xml("# Comment\nSet Variable [ $var ; Value: 1 ]")
        #expect(out == """
        <?xml version="1.0" ?>
        <fmxmlsnippet type="FMObjectList">
          <Step enable="True" id="89" name="Comment">
            <Text> Comment</Text>
          </Step>
          <Step enable="True" id="141" name="Set Variable">
            <Name>$var</Name>
            <Value>
              <Calculation><![CDATA[1]]></Calculation>
            </Value>
            <Repetition>
              <Calculation><![CDATA[1]]></Calculation>
            </Repetition>
          </Step>
        </fmxmlsnippet>

        """)
    }

    @Test func emptyInputGivesAnEmptySnippet() throws {
        #expect(try xml("") == "<?xml version=\"1.0\" ?>\n<fmxmlsnippet type=\"FMObjectList\"/>\n")
        #expect(try xml("   \n\n   ") == "<?xml version=\"1.0\" ?>\n<fmxmlsnippet type=\"FMObjectList\"/>\n")
        let result = converter.convert("  \n")
        #expect(result.status == .failed)
        #expect(result.errors.map(\.code) == [.emptyInput])
    }

    @Test func unknownStepFailsInStrictMode() {
        #expect(throws: ConversionError.self) { try converter.convertToXML("Unknown Step [ param: value ]") }
        do {
            _ = try converter.convertToXML("Beep\nUnknown Step [ param: value ]")
        } catch {
            #expect(error.description == "Unknown script step: Unknown Step (line 2)")
        }
    }

    @Test func unknownStepIsSkippedSilentlyWhenContinuing() throws {
        let out = try converter.convertToXML("Set Variable [ $v ; Value: 1 ]\nUnknown Step [ x: y ]\nExit Script", stopOnError: false)
        #expect(out.contains("Set Variable"))
        #expect(out.contains("Exit Script"))
        #expect(!out.contains("ERROR"))
    }

    @Test func handlerFailureBecomesAnErrorComment() throws {
        let text = "Perform Script on Server with Callback [ Specified: From list ; “Job” ; State: Continue ]\nBeep"
        let out = try converter.convertToXML(text, stopOnError: false)
        #expect(out.contains("<!-- ERROR: Error converting step 'Perform Script on Server with Callback': 'NoneType' object has no attribute 'strip' -->"))
        let result = converter.convert(text)
        #expect(result.status == .failed)
        #expect(result.errors.map(\.code) == [.handlerFailed])
    }

    @Test func validate() {
        #expect(converter.validate("Set Variable [ $var ; Value: 1 ]").isValid)
        let (valid, errors) = converter.validate("Unknown Step [ param: value ]")
        #expect(!valid)
        #expect(errors == ["Unknown step 'Unknown Step' at line 1"])
    }

    @Test func calculationsArePreservedInCDATA() throws {
        let out = try xml(#"""
        Set Variable [ $msg ; Value: "text" & $var & "<more>" ]
        Set Variable [ $empty ; Value: "" ]
        Set Variable [ $count ; Value: ValueCount ( JSONListKeys ( $m ; "" ) ) ]
        """#)
        #expect(out.contains(#"<Calculation><![CDATA["text" & $var & "<more>"]]></Calculation>"#))
        #expect(out.contains(#"<Calculation><![CDATA[""]]></Calculation>"#))
        #expect(out.contains(#"<![CDATA[ValueCount ( JSONListKeys ( $m ; "" ) )]]>"#))
    }

    @Test func goToLayout() throws {
        let calc = try xml("Go to Layout [ $returnLayout ]")
        #expect(calc.contains(#"<LayoutDestination value="LayoutNameByCalc"/>"#))
        #expect(calc.contains("<Calculation><![CDATA[$returnLayout]]></Calculation>"))
        #expect(calc.contains("<Text>Original: Go to Layout [ $returnLayout ]</Text>"))
        let named = try xml(#"Go to Layout [ "MyLayout" ]"#)
        #expect(named.contains(#"<LayoutDestination value="SelectedLayout"/>"#))
        #expect(named.contains(#"<Layout name="MyLayout"/>"#))
    }

    @Test func disabledStepsAreNotEnabled() throws {
        #expect(try xml("// Beep").contains(#"<Step enable="False" id="93" name="Beep"/>"#))
    }

    @Test func crlfAndCRInputIsNormalized() throws {
        #expect(try xml("# a\r\nBeep\r\n") == xml("# a\nBeep\n"))
        #expect(try xml("# a\rBeep\r") == xml("# a\nBeep\n"))
    }

    @Test func textIsEscapedAndAttributesKeepRawWhitespace() throws {
        let out = try xml("# Comment with \"quotes\" & <brackets>")
        #expect(out.contains("<Text> Comment with &quot;quotes&quot; &amp; &lt;brackets&gt;</Text>"))
    }

    @Test func invalidElementNameFallsBackToCompactXML() throws {
        let out = try xml("Set Web Viewer [ Object Name: \"v\" ; Action (custom): Reset ]")
        #expect(out == #"<fmxmlsnippet type="FMObjectList"><Step enable="True" id="146" name="Set Web Viewer"><ObjectName>"v"</ObjectName><Action(custom)>Reset</Action(custom)></Step></fmxmlsnippet>"#)
    }

    @Test func cdataTerminatorFallsBackToCompactXML() throws {
        let out = try xml(#"Set Variable [ $x ; Value: "a]]>b" ]"#)
        #expect(out.hasPrefix("<fmxmlsnippet"))
        #expect(out.contains(#"<![CDATA["a]]>b"]]>"#))
    }

    @Test func registry() {
        let r = StepRegistry.shared
        #expect(r.allSteps.count >= 166)
        #expect(r.get("Set Variable")?.id == 141)
        #expect(r.get(id: 141)?.name == "Set Variable")
        #expect(r.get("Unknown Step That Does Not Exist") == nil)
        #expect(r.get("Open Manage Layouts")?.name == "Open Manage Layouts ")
        #expect(r.stepNames.contains("If"))
    }

    @Test func exitScriptTextResultRegex() {
        #expect(ExitScriptHandler.textResult(in: "Exit Script [ Text Result: ]") == "]")
        #expect(ExitScriptHandler.textResult(in: "Exit Script [ Text Result: $x ]") == "$x")
        #expect(ExitScriptHandler.textResult(in: "Exit Script [ Text Result:\n]") == "]")
        #expect(ExitScriptHandler.textResult(in: "Exit Script [ Text Result:\n\n") == nil)
        #expect(ExitScriptHandler.textResult(in: "x Text Result: a\nb ]") == nil)
    }

    @Test func htmlUnescapeMatchesPython() {
        func u(_ s: String) -> String { HTMLUnescape.unescape(s.scalars).string }
        #expect(u("&lt;b&gt; &amp; &quot;") == "<b> & \"")
        #expect(u("&ltfoo") == "<foo")
        #expect(u("&notit;") == "¬it;")
        #expect(u("Tom &Jerry") == "Tom &Jerry")
        #expect(u("&#65;&#x42;&#X43") == "ABC")
        #expect(u("&#0;&#128;&#xD800;&#1114112;") == "\u{FFFD}€\u{FFFD}\u{FFFD}")
        #expect(u("&#11;x") == "x")
        #expect(u("& ; &# &#x;") == "& ; &# &#x;")
    }
}
