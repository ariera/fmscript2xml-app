// Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import FMClipboard
import FMHistory
import FMScriptKit
import Observation

#if DEBUG
func debugLog(_ message: String) {
    FileHandle.standardError.write(Data("[debug] \(message)\n".utf8))
}
#endif

func stepCountText(_ n: Int) -> String { n == 1 ? "1 step" : "\(n) steps" }

/// The hotkey pipeline (PLAN §4) and the history it feeds (§5).
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    let history: HistoryStore
    /// The latest conversion, kept even when history is off.
    private(set) var lastEntry: HistoryEntry?
    let converter = Converter()

    /// The general pasteboard. Debug builds can use a named one instead
    /// (`-FMSPPasteboardName <name>`), so the pipeline can be exercised
    /// without touching the real clipboard; they then keep history in memory.
    let pasteboard: NSPasteboard

    private init() {
        var pasteboard = NSPasteboard.general
        var historyFile: URL? = HistoryStore.defaultFileURL
        #if DEBUG
        if let name = UserDefaults.standard.string(forKey: "FMSPPasteboardName") {
            pasteboard = NSPasteboard(name: NSPasteboard.Name(name))
            historyFile = nil
        }
        #endif
        self.pasteboard = pasteboard
        history = HistoryStore(fileURL: historyFile, capacity: AppSettings.historyLength, persists: AppSettings.keepHistory)
    }

    /// The newest conversion: from history, or the unsaved last one.
    var latest: HistoryEntry? { history.entries.first ?? lastEntry }

    func convertClipboard() {
        // 1. Who was frontmost (an LSUIElement app doesn't take focus)
        let front = NSWorkspace.shared.frontmostApplication
        var source = front.map { SourceApp(name: $0.localizedName ?? "Unknown", bundleIdentifier: $0.bundleIdentifier) }
        #if DEBUG
        if let name = UserDefaults.standard.string(forKey: "FMSPSourceApp") { source = SourceApp(name: name, bundleIdentifier: nil) }
        #endif

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

        // 4./5. Write the clipboard, or leave it alone and explain
        if let xml = result.xml {
            FMClipboard.write(xml, flavor: .scriptSteps, to: pasteboard)
            var message = "\(stepCountText(result.convertedStepCount)) ready to paste"
            let problems = result.diagnostics.filter { $0.severity <= .warning }.count
            if problems > 0 { message += " · \(problems) warning\(problems == 1 ? "" : "s")" }
            Feedback.shared.show(result.status == .ok ? .success(message) : .warning(message))
            if AppSettings.autoPaste { AutoPaste.pasteWhenKeysReleased() }
        } else {
            let summary = result.errors.first.map(\.lineSummary) ?? "The clipboard couldn't be converted."
            Feedback.shared.show(.failure("Not converted — clipboard unchanged"))
            Notifications.shared.postFailure(summary: summary, errorCount: result.errors.count)
        }

        // 6. History (both outcomes)
        record(HistoryEntry(sourceApp: source, origin: .hotkey, result: result))
        #if DEBUG
        debugLog("status=\(result.status.rawValue) steps=\(result.convertedStepCount) "
            + "diagnostics=\(result.diagnostics.map { "\($0.severity.rawValue):\($0.code.rawValue)@\($0.lines.lowerBound)" }) "
            + "source=\(source?.bundleIdentifier ?? "-") history=\(history.entries.count)")
        #endif
    }

    @discardableResult
    func record(_ entry: HistoryEntry) -> HistoryEntry {
        let stored = history.record(entry) ?? entry
        lastEntry = stored
        return stored
    }

    // MARK: Entry actions

    /// Puts an entry's steps on the clipboard. Returns false if it has none.
    @discardableResult
    func copyAsSteps(_ entry: HistoryEntry) -> Bool {
        guard let xml = entry.xml else { return false }
        FMClipboard.write(xml, flavor: .scriptSteps, to: pasteboard)
        Feedback.shared.show(.success("\(stepCountText(entry.stepCount)) copied"))
        return true
    }

    func copyText(_ text: String, feedback: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        Feedback.shared.show(.info(feedback))
    }

    /// The menu bar's click on a recent entry: re-copy, or explain a failure.
    func activate(_ entry: HistoryEntry) {
        if !copyAsSteps(entry) {
            WindowManager.shared.showInspector(selecting: entry.id)
        }
    }

    func setHistoryLength(_ value: Int) {
        history.setCapacity(value)
    }

    func setKeepHistory(_ value: Bool) {
        history.setPersists(value)
    }
}

extension Diagnostic {
    /// "Line 3: Unknown step “Go to Layuot”. Did you mean “Go to Layout”?"
    var lineSummary: String {
        let where_ = lines.count == 1 ? "Line \(lines.lowerBound)" : "Lines \(lines.lowerBound)–\(lines.upperBound)"
        return "\(where_): \(message)"
    }
}

extension ConversionResult.Status {
    var symbol: String {
        switch self {
        case .ok: return "checkmark.circle"
        case .warnings: return "exclamationmark.triangle"
        case .failed: return "xmark.octagon"
        }
    }
}
