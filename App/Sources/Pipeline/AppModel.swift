// Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import FMClipboard
import FMScriptKit
import Observation

/// The app that was frontmost when the hotkey fired.
struct SourceApp: Sendable, Hashable {
    let name: String
    let bundleIdentifier: String?
}

/// One conversion and where it came from.
struct ConversionRecord: Sendable {
    let date: Date
    let sourceApp: SourceApp?
    let result: ConversionResult

    var menuSummary: String {
        let when = RelativeDateTimeFormatter().localizedString(for: date, relativeTo: .now)
        let what: String
        switch result.status {
        case .ok: what = "✓ \(stepCountText(result.convertedStepCount))"
        case .warnings: what = "⚠︎ \(stepCountText(result.convertedStepCount))"
        case .failed: what = "✗ Failed"
        }
        return "Last: \(what) · \(when)"
    }
}

#if DEBUG
func debugLog(_ message: String) {
    FileHandle.standardError.write(Data("[debug] \(message)\n".utf8))
}
#endif

func stepCountText(_ n: Int) -> String { n == 1 ? "1 step" : "\(n) steps" }

/// The hotkey pipeline (PLAN §4): read the clipboard, convert, write XMSS,
/// give feedback.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    private(set) var lastRecord: ConversionRecord?
    private let converter = Converter()

    /// The general pasteboard. Debug builds can use a named one instead
    /// (`-FMSPPasteboardName <name>`), so the pipeline can be exercised
    /// without touching the real clipboard.
    let pasteboard: NSPasteboard = {
        #if DEBUG
        if let name = UserDefaults.standard.string(forKey: "FMSPPasteboardName") {
            return NSPasteboard(name: NSPasteboard.Name(name))
        }
        #endif
        return .general
    }()

    func convertClipboard() {
        // 1. Who was frontmost (an LSUIElement app doesn't take focus)
        let front = NSWorkspace.shared.frontmostApplication
        let source = front.map { SourceApp(name: $0.localizedName ?? "Unknown", bundleIdentifier: $0.bundleIdentifier) }

        // 2. Read the clipboard
        if !FMClipboard.flavors(on: pasteboard).isEmpty {
            Feedback.shared.show(.info("Already FileMaker steps"))
            return
        }
        guard let text = FMClipboard.text(from: pasteboard),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            Feedback.shared.show(.info("Clipboard has no text"))
            return
        }

        // 3. Convert
        let result = converter.convert(text, policy: AppSettings.policy)
        let record = ConversionRecord(date: .now, sourceApp: source, result: result)
        lastRecord = record

        // 4./5. Write the clipboard, or leave it alone and explain
        if let xml = result.xml {
            FMClipboard.write(xml, flavor: .scriptSteps, to: pasteboard)
            var message = "\(stepCountText(result.convertedStepCount)) ready to paste"
            let problems = result.diagnostics.filter { $0.severity <= .warning }.count
            if problems > 0 { message += " · \(problems) warning\(problems == 1 ? "" : "s")" }
            Feedback.shared.show(result.status == .ok ? .success(message) : .warning(message))
        } else {
            let first = result.errors.first
            let summary = first.map(\.lineSummary) ?? "The clipboard couldn't be converted."
            Feedback.shared.show(.failure("Not converted — clipboard unchanged"))
            Notifications.shared.postFailure(summary: summary, errorCount: result.errors.count)
        }
        WindowManager.shared.refreshInspector()
        #if DEBUG
        debugLog("status=\(result.status.rawValue) steps=\(result.convertedStepCount) "
            + "diagnostics=\(result.diagnostics.map { "\($0.severity.rawValue):\($0.code.rawValue)@\($0.lines.lowerBound)" }) "
            + "source=\(source?.bundleIdentifier ?? "-")")
        #endif
    }
}

extension Diagnostic {
    /// "Line 3: Unknown step “Go to Layuot”. Did you mean “Go to Layout”?"
    var lineSummary: String {
        let where_ = lines.count == 1 ? "Line \(lines.lowerBound)" : "Lines \(lines.lowerBound)–\(lines.upperBound)"
        return "\(where_): \(message)"
    }
}
