// Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
// SPDX-License-Identifier: GPL-3.0-or-later

// Swift CLI with the same flags and messages as the Python `fmscript2xml` CLI,
// plus a few developer flags (--print, --diagnostics, --explain).

import FMClipboard
import FMScriptKit
import Foundation

struct Options {
    var input: String?
    var output: String?
    var validate = false
    var continueOnError = false
    var fromClipboard = false
    var clipboard = false
    var noFile = false
    var print = false
    var diagnostics = false
    var explain = false
}

let prog = "fmscript2xml"

func eprint(_ s: String) {
    FileHandle.standardError.write(Data((s + "\n").utf8))
}

func printHelp() {
    print("""
    usage: \(prog) [-h] [--version] [-o OUTPUT] [--validate] [--continue-on-error]
                        [--from-clipboard] [-c] [--no-file] [--print] [--diagnostics]
                        [--explain] [input]

    Convert FileMaker script to XML (version \(FMScriptKit.version))

    positional arguments:
      input                 Input file (plain text). Required unless --from-clipboard is used.

    options:
      -h, --help            show this help message and exit
      --version             show program's version number and exit
      -o, --output OUTPUT   Output file (XML). If not specified, creates input.xml next to input file.
      --validate            Only validate, do not convert
      --continue-on-error   Continue processing on errors
      --from-clipboard      Read input script from clipboard (macOS only). Requires --output or --no-file.
      -c, --clipboard       Copy result to clipboard as FileMaker objects (macOS only). Can be pasted
                            directly into FileMaker Pro.
      --no-file             Do not write output file (use with --clipboard)

    developer options (Swift CLI only):
      --print               Write the XML to stdout instead of a file
      --diagnostics         Print diagnostics (errors, warnings, notes) to stderr
      --explain             Print how each step was parsed and converted

    Examples:
      \(prog) script.txt              # Creates script.txt.xml
      \(prog) script.txt -o output.xml # Creates output.xml
      \(prog) script.txt --validate    # Only validates, no output
      \(prog) script.txt --clipboard   # Converts and copies to clipboard (macOS only)
      \(prog) --from-clipboard --output clipboard.xml  # Converts clipboard text
      \(prog) --from-clipboard --no-file --clipboard   # Clipboard in, FM objects out
    """)
}

func parseArguments(_ args: [String]) -> Options {
    var o = Options()
    var i = 0
    func usageError(_ message: String) -> Never {
        eprint("usage: \(prog) [-h] [--version] [-o OUTPUT] [--validate] [--continue-on-error] [--from-clipboard] [-c] [--no-file] [input]")
        eprint("\(prog): error: \(message)")
        exit(2)
    }
    while i < args.count {
        let a = args[i]
        switch a {
        case "-h", "--help": printHelp(); exit(0)
        case "--version": print("\(prog) \(FMScriptKit.version)"); exit(0)
        case "-o", "--output":
            guard i + 1 < args.count else { usageError("argument -o/--output: expected one argument") }
            o.output = args[i + 1]
            i += 1
        case "--validate": o.validate = true
        case "--continue-on-error": o.continueOnError = true
        case "--from-clipboard": o.fromClipboard = true
        case "-c", "--clipboard": o.clipboard = true
        case "--no-file": o.noFile = true
        case "--print": o.print = true; o.noFile = true
        case "--diagnostics": o.diagnostics = true
        case "--explain": o.explain = true
        default:
            if a.hasPrefix("--output=") {
                o.output = String(a.dropFirst("--output=".count))
            } else if a.hasPrefix("-") && a != "-" {
                usageError("unrecognized arguments: \(a)")
            } else if o.input == nil {
                o.input = a
            } else {
                usageError("unrecognized arguments: \(a)")
            }
        }
        i += 1
    }
    return o
}

func explain(_ result: ConversionResult) {
    for t in result.steps {
        let lines = t.sourceLines.count == 1 ? "line \(t.sourceLines.lowerBound)"
            : "lines \(t.sourceLines.lowerBound)–\(t.sourceLines.upperBound)"
        print("\(lines): \(t.stepName)\(t.isDisabled ? " (disabled)" : "")")
        print("  resolved: \(t.resolvedName.map { "\($0) (id \(t.resolvedID!))" } ?? "—")")
        print("  handler:  \(t.handler ?? "—")")
        for (k, v) in t.params.items {
            print("  param \(k.allSatisfy(\.isNumber) ? "#\(k)" : "“\(k)”"): \(v.replacingOccurrences(of: "\n", with: "⏎"))")
        }
        print("  xml steps: \(t.xmlSteps.isEmpty ? "none" : "\(t.xmlSteps.lowerBound)..<\(t.xmlSteps.upperBound)")")
    }
}

func run() -> Int32 {
    let o = parseArguments(Array(CommandLine.arguments.dropFirst()))

    if o.fromClipboard {
        if o.output == nil && !o.noFile {
            eprint("Error: --from-clipboard requires --output or --no-file.")
            return 1
        }
    } else {
        guard let input = o.input else {
            eprint("Error: Input file is required unless --from-clipboard is used.")
            return 1
        }
        if !FileManager.default.fileExists(atPath: input) {
            eprint("Error: Input file not found: \(input)")
            return 1
        }
    }

    let outputPath: String? = o.output ?? (o.noFile ? nil : o.input.map { $0 + ".xml" })

    let text: String
    if o.fromClipboard {
        text = FMClipboard.text() ?? ""
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            eprint("Error: Clipboard is empty.")
            return 1
        }
    } else {
        do {
            text = try String(contentsOfFile: o.input!, encoding: .utf8)
        } catch {
            eprint("Error reading input file: \(error.localizedDescription)")
            return 1
        }
    }

    let converter = Converter()

    if o.validate {
        let (valid, errors) = converter.validate(text)
        if valid {
            print("Script is valid.")
            return 0
        }
        print("Script has errors:")
        for e in errors { print("  - \(e)") }
        return 1
    }

    if o.diagnostics || o.explain {
        let result = converter.convert(text, policy: o.continueOnError ? .continueOnError : .strict)
        if o.explain { explain(result) }
        if o.diagnostics {
            for d in result.diagnostics {
                eprint("\(d.severity.rawValue): line \(d.lines.lowerBound): \(d.message)")
            }
        }
    }

    let xml: String
    do {
        xml = try converter.convertToXML(text, stopOnError: !o.continueOnError)
    } catch {
        eprint("Error: \(error)")
        return 1
    }

    if o.print { print(xml, terminator: "") }

    if !o.noFile, let outputPath {
        do {
            try xml.write(toFile: outputPath, atomically: false, encoding: .utf8)
            print("Successfully converted to: \(outputPath)")
        } catch {
            eprint("Error writing output file: \(error.localizedDescription)")
            return 1
        }
    }

    if o.clipboard {
        do {
            try FMClipboard.writeValidated(xml)
            print("✓ Copied to clipboard as FileMaker objects. Ready to paste into FileMaker Pro.")
        } catch {
            eprint("Error: Invalid XML for FileMaker: \(error)")
            return 1
        }
    }
    return 0
}

exit(run())
