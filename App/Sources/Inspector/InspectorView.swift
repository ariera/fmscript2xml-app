// Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
// SPDX-License-Identifier: GPL-3.0-or-later

import FMClipboard
import FMScriptKit
import SwiftUI

/// Read-only view of the last conversion: input with marked lines, output
/// XML and diagnostics. A first cut of the inspector (PLAN §6, Phase 5).
struct InspectorView: View {
    private var model = AppModel.shared

    var body: some View {
        if let record = model.lastRecord {
            RecordView(record: record)
        } else {
            ContentUnavailableView(
                "No conversions yet",
                systemImage: "list.bullet.clipboard",
                description: Text("Copy script steps as text and press the shortcut.")
            )
            .frame(minWidth: 600, minHeight: 400)
        }
    }
}

private struct RecordView: View {
    let record: ConversionRecord
    @State private var selectedLine: Int?

    private var result: ConversionResult { record.result }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                pane("Input") { InputLinesView(result: result, selectedLine: $selectedLine) }
                pane("Output XML") { OutputView(result: result, selectedLine: selectedLine) }
            }
            Divider()
            if result.diagnostics.isEmpty {
                Label("No problems found.", systemImage: "checkmark.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            } else {
                DiagnosticsList(diagnostics: result.diagnostics, selectedLine: $selectedLine)
                    .frame(minHeight: 90, idealHeight: 140, maxHeight: 220)
            }
        }
        .frame(minWidth: 760, minHeight: 480)
    }

    private var header: some View {
        HStack(spacing: 12) {
            StatusBadge(status: result.status)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.date.formatted(date: .abbreviated, time: .standard))
                    .font(.headline)
                Text([
                    record.sourceApp.map { "from \($0.name)" },
                    stepCountText(result.convertedStepCount) + " converted",
                    "\(result.duration.formatted(.units(allowed: [.milliseconds], fractionalPart: .show(length: 1))))",
                ].compactMap { $0 }.joined(separator: " · "))
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Copy as Steps") {
                if let xml = result.xml { FMClipboard.write(xml) }
            }
            .disabled(result.xml == nil)
            .help(result.xml == nil ? "The conversion failed; fix the errors first." : "Put the FileMaker steps on the clipboard")
            Button("Copy XML") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(result.previewXML, forType: .string)
            }
        }
        .padding(12)
    }

    private func pane(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.caption.bold()).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.vertical, 6)
            Divider()
            content()
        }
        .frame(minWidth: 300)
    }
}

private struct StatusBadge: View {
    let status: ConversionResult.Status

    var body: some View {
        switch status {
        case .ok: Label("Converted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .warnings: Label("Converted with warnings", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .failed: Label("Not converted", systemImage: "xmark.octagon.fill").foregroundStyle(.red)
        }
    }
}

private struct InputLinesView: View {
    let result: ConversionResult
    @Binding var selectedLine: Int?

    var body: some View {
        let lines = inputLines
        let marks = lineMarks()
        ScrollViewReader { proxy in
            TopLeadingScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        let number = index + 1
                        HStack(spacing: 0) {
                            Rectangle().fill(marks[number]?.color ?? .clear).frame(width: 3)
                            Text("\(number)")
                                .foregroundStyle(.tertiary)
                                .frame(width: 36, alignment: .trailing)
                                .padding(.trailing, 8)
                            Text(line.isEmpty ? " " : line)
                                .fixedSize()
                        }
                        .font(.system(.body, design: .monospaced))
                        .background(isSelected(number) ? Color.accentColor.opacity(0.15) : .clear)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedLine = number }
                        .id(number)
                    }
                }
                .padding(.vertical, 6)
            }
            .onChange(of: selectedLine) { _, line in
                if let line { withAnimation { proxy.scrollTo(line, anchor: .center) } }
            }
        }
    }

    private var inputLines: [String] {
        var lines = result.input.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        // A trailing newline doesn't start a visible line
        if lines.count > 1, lines.last == "" { lines.removeLast() }
        return lines
    }

    private func isSelected(_ line: Int) -> Bool {
        guard let selectedLine, let trace = result.trace(forLine: selectedLine) else { return line == selectedLine }
        return trace.sourceLines.contains(line)
    }

    private func lineMarks() -> [Int: Diagnostic.Severity] {
        var marks: [Int: Diagnostic.Severity] = [:]
        for d in result.diagnostics where d.severity <= .warning {
            for l in d.lines { marks[l] = min(marks[l] ?? .info, d.severity) }
        }
        return marks
    }
}

private struct OutputView: View {
    let result: ConversionResult
    let selectedLine: Int?

    var body: some View {
        TopLeadingScrollView {
            Text(attributed)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize()
                .padding(8)
        }
    }

    /// The XML, with the selected step's elements highlighted.
    private var attributed: AttributedString {
        var s = AttributedString(result.previewXML)
        if let selectedLine,
           let trace = result.trace(forLine: selectedLine),
           let range = result.xmlTextRange(for: trace),
           let lo = AttributedString.Index(range.lowerBound, within: s),
           let hi = AttributedString.Index(range.upperBound, within: s) {
            s[lo..<hi].backgroundColor = Color.accentColor.opacity(0.18)
        }
        return s
    }
}

/// Scrolls both ways and keeps content smaller than the pane at the top
/// left (a plain two-axis ScrollView centres it).
private struct TopLeadingScrollView<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { geometry in
            ScrollView([.vertical, .horizontal]) {
                content
                    .frame(minWidth: geometry.size.width, minHeight: geometry.size.height, alignment: .topLeading)
            }
        }
    }
}

private struct DiagnosticsList: View {
    let diagnostics: [Diagnostic]
    @Binding var selectedLine: Int?

    var body: some View {
        if diagnostics.isEmpty {
            Text("No problems found.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(Array(diagnostics.enumerated()), id: \.offset) { _, d in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: d.severity.symbol).foregroundStyle(d.severity.color)
                    Text(d.lines.count == 1 ? "Line \(d.lines.lowerBound)" : "Lines \(d.lines.lowerBound)–\(d.lines.upperBound)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 90, alignment: .leading)
                    Text(d.message)
                    if !d.alternatives.isEmpty {
                        Text("Also: " + d.alternatives.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { selectedLine = d.lines.lowerBound }
            }
            .listStyle(.inset)
        }
    }
}

extension Diagnostic.Severity {
    var color: Color {
        switch self {
        case .error: return .red
        case .warning: return .orange
        case .info: return .secondary
        }
    }

    var symbol: String {
        switch self {
        case .error: return "xmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle"
        }
    }
}
