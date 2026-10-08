// Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import FMHistory
import FMScriptKit
import SwiftUI

/// The inspector (PLAN §6): history on the left; an editable draft, its XML
/// and its diagnostics on the right, with input lines linked to XML steps.
struct InspectorView: View {
    @Bindable private var model = InspectorModel.shared

    var body: some View {
        NavigationSplitView {
            Sidebar(model: model)
                .navigationSplitViewColumnWidth(min: 220, ideal: 270, max: 400)
        } detail: {
            if let item = model.selection {
                DetailView(model: model, item: item)
                    .id(item)
            } else {
                ContentUnavailableView(
                    "Nothing selected",
                    systemImage: "list.bullet.clipboard",
                    description: Text("Convert something with the shortcut, pick a conversion on the left, or start a new draft.")
                )
            }
        }
        .frame(minWidth: 900, minHeight: 540)
    }
}

// MARK: - Sidebar

private struct Sidebar: View {
    @Bindable var model: InspectorModel
    @State private var confirmClear = false
    private var history: HistoryStore { AppModel.shared.history }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search", text: $model.search)
                    .textFieldStyle(.plain)
                Picker("Status", selection: $model.statusFilter) {
                    ForEach(InspectorModel.StatusFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                Button { model.newScratch() } label: { Image(systemName: "square.and.pencil") }
                    .buttonStyle(.borderless)
                    .help("New draft")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            Divider()

            List(selection: $model.selection) {
                if !model.scratches.isEmpty {
                    Section("Drafts") {
                        ForEach(model.scratches) { scratch in
                            let item = InspectorModel.Item.scratch(scratch.id)
                            Label(model.title(of: item), systemImage: "square.and.pencil")
                                .lineLimit(1)
                                .tag(item)
                                .contextMenu { Button("Delete Draft") { model.delete(item) } }
                        }
                    }
                }
                let pinned = model.filteredEntries.filter(\.isPinned)
                if !pinned.isEmpty {
                    Section("Pinned") {
                        ForEach(pinned) { entry in
                            EntryRow(entry: entry)
                                .tag(InspectorModel.Item.entry(entry.id))
                                .contextMenu { EntryActions(entry: entry, model: model) }
                        }
                    }
                }
                Section(history.capacity == 0 ? "History (off in Settings)" : "History") {
                    ForEach(model.filteredEntries.filter { !$0.isPinned }) { entry in
                        EntryRow(entry: entry)
                            .tag(InspectorModel.Item.entry(entry.id))
                            .contextMenu { EntryActions(entry: entry, model: model) }
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()
            HStack {
                Text("\(history.unpinnedEntries.count) of \(history.capacity)"
                     + (history.pinnedEntries.isEmpty ? "" : " · \(history.pinnedEntries.count) pinned"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear History…") { confirmClear = true }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .disabled(history.unpinnedEntries.isEmpty)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .confirmationDialog("Clear the conversion history?", isPresented: $confirmClear) {
            Button("Clear History", role: .destructive) { model.clearHistory() }
        } message: {
            Text(history.pinnedEntries.isEmpty
                 ? "This removes all \(history.unpinnedEntries.count) entries."
                 : "This removes \(history.unpinnedEntries.count) entries. Pinned entries are kept.")
        }
    }
}

private struct EntryRow: View {
    let entry: HistoryEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(entry.status.color)
                .frame(width: 8, height: 8)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(entry.shortTitle(maxLength: 60))
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                    if entry.isPinned {
                        Spacer(minLength: 0)
                        Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text([
                    entry.date.formatted(.relative(presentation: .named)),
                    entry.origin == .inspector ? "inspector" : entry.sourceApp?.name,
                    entry.status == .failed ? "failed" : stepCountText(entry.stepCount),
                ].compactMap { $0 }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Actions on a history entry (context menu).
private struct EntryActions: View {
    let entry: HistoryEntry
    let model: InspectorModel
    private var app: AppModel { .shared }

    var body: some View {
        Button("Copy as Steps") { app.copyAsSteps(entry) }.disabled(entry.xml == nil)
        Button("Copy XML") { if let xml = entry.xml { app.copyText(xml, feedback: "XML copied as text") } }
            .disabled(entry.xml == nil)
        Button("Copy Original Text") { app.copyText(entry.input, feedback: "Original text copied") }
        Divider()
        Button(entry.isPinned ? "Unpin" : "Pin") { model.setPinned(!entry.isPinned, id: entry.id) }
        Button("Reconvert") { model.reconvertEntry(entry.id) }
        Button("Delete", role: .destructive) { model.delete(.entry(entry.id)) }
    }
}

// MARK: - Detail

private struct DetailView: View {
    @Bindable var model: InspectorModel
    let item: InspectorModel.Item

    /// Input line the user is on or pointed at (cursor, diagnostics, steps).
    @State private var focusLine: Int?
    /// Input line under the mouse.
    @State private var hoverLine: Int?
    /// Emitted <Step> under the mouse in the XML.
    @State private var hoverStep: Int?
    @State private var revealToken = 0
    @State private var bottomTab = BottomTab.problems

    enum BottomTab: Hashable { case problems, steps }

    private var draft: InspectorModel.Draft { model.draft(for: item) }
    private var result: ConversionResult { draft.result }
    private var entry: HistoryEntry? {
        if case .entry(let id) = item { return AppModel.shared.history.entry(id: id) }
        return nil
    }

    /// The trace linked to what the user points at.
    private var linkedTrace: StepTrace? {
        if let hoverStep { return result.steps.first { $0.xmlSteps.contains(hoverStep) } }
        if let line = hoverLine ?? focusLine { return result.trace(forLine: line) }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            VSplitView {
                HSplitView {
                    pane("Input", trailing: draft.isEdited ? "edited" : nil) { inputEditor }
                    pane("Output XML", trailing: nil) { xmlView }
                }
                .frame(minHeight: 200)
                bottomPane
                    .frame(minHeight: 80, idealHeight: 170)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            StatusBadge(status: result.status)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.map { $0.date.formatted(date: .abbreviated, time: .standard) } ?? "Draft")
                    .font(.headline)
                Text(headerDetails).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Copy as Steps") { model.copyAsSteps(item) }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(result.xml == nil)
                .help(result.xml == nil ? "The conversion failed; fix the errors first."
                      : draft.isEdited ? "Copy the steps and save this version as a new history entry"
                      : "Put the FileMaker steps on the clipboard")
            Menu {
                Button("Copy XML") { AppModel.shared.copyText(result.previewXML, feedback: "XML copied as text") }
                Button("Copy Text") { AppModel.shared.copyText(draft.text, feedback: "Text copied") }
                Divider()
                if case .entry(let id) = item, let entry {
                    Button(entry.isPinned ? "Unpin" : "Pin") { model.setPinned(!entry.isPinned, id: id) }
                    Button("Reconvert with Converter \(FMScriptKit.version)") { model.reconvertEntry(id) }
                }
                if draft.isEdited, case .entry = item {
                    Button("Revert Edits") { model.revert(item) }
                }
                Divider()
                Button("Delete", role: .destructive) { model.delete(item) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var headerDetails: String {
        var parts: [String] = []
        if let entry {
            if entry.isPinned { parts.append("pinned") }
            if entry.origin == .inspector { parts.append("from the inspector") }
            else if let app = entry.sourceApp { parts.append("from \(app.name)") }
            if entry.converterVersion != FMScriptKit.version { parts.append("converter \(entry.converterVersion)") }
        }
        parts.append("\(stepCountText(result.convertedStepCount)) converted")
        parts.append(result.duration.formatted(.units(allowed: [.milliseconds], fractionalPart: .show(length: 1))))
        return parts.joined(separator: " · ")
    }

    private func pane(_ title: String, trailing: String?, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).font(.caption.bold()).foregroundStyle(.secondary)
                if let trailing {
                    Text(trailing)
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            Divider()
            content()
        }
        .frame(minWidth: 280)
    }

    // MARK: Input and XML

    private var inputEditor: some View {
        CodeTextView(
            text: draft.text,
            onTextChange: { [model, item] in model.setText($0, for: item) },
            isEditable: true,
            highlight: linkedTrace.flatMap { utf16Range(ofLines: $0.sourceLines, in: draft.text) },
            lineMarks: lineMarks,
            revealToken: revealToken,
            onCursorLine: { line in if focusLine != line { focusLine = line } },
            onHoverOffset: { offset in
                let line = offset.map { lineNumber(at: $0, in: draft.text) }
                if hoverLine != line { hoverLine = line }
            }
        )
    }

    private var xmlView: some View {
        let xml = result.previewXML
        let stepRanges = result.xmlStepRanges.indices.map { NSRange(result.xmlTextRange(forStep: $0), in: xml) }
        let highlight = linkedTrace.flatMap { result.xmlTextRange(for: $0) }.map { NSRange($0, in: xml) }
        return CodeTextView(
            text: xml,
            isEditable: false,
            colors: XMLSyntax.colors(for: xml),
            highlight: highlight,
            revealToken: revealToken,
            onHoverOffset: { offset in
                let step = offset.flatMap { o in stepRanges.firstIndex { NSLocationInRange(o, $0) } }
                if hoverStep != step { hoverStep = step }
            },
            onClickOffset: { offset in
                guard let step = stepRanges.firstIndex(where: { NSLocationInRange(offset, $0) }),
                      let trace = result.steps.first(where: { $0.xmlSteps.contains(step) })
                else { return }
                focus(trace.sourceLines.lowerBound)
            }
        )
    }

    private var lineMarks: [Int: NSColor] {
        var marks: [Int: NSColor] = [:]
        for d in result.diagnostics where d.severity <= .warning {
            for line in d.lines where marks[line] != .systemRed {
                marks[line] = d.severity == .error ? .systemRed : .systemOrange
            }
        }
        return marks
    }

    private func focus(_ line: Int) {
        focusLine = line
        revealToken += 1
    }

    // MARK: Bottom: problems and steps

    private var bottomPane: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $bottomTab) {
                    Text(problemsTitle).tag(BottomTab.problems)
                    Text("Steps (\(result.steps.count))").tag(BottomTab.steps)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            Divider()
            switch bottomTab {
            case .problems: problemsList
            case .steps: ExplainList(result: result, focusedLine: focusLine) { focus($0) }
            }
        }
    }

    private var problemsTitle: String {
        let n = result.diagnostics.filter { $0.severity <= .warning }.count
        return n == 0 ? "Problems" : "Problems (\(n))"
    }

    @ViewBuilder private var problemsList: some View {
        if result.diagnostics.isEmpty {
            Label("No problems found.", systemImage: "checkmark.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(10)
        } else {
            List(Array(result.diagnostics.enumerated()), id: \.offset) { _, d in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: d.severity.symbol).foregroundStyle(d.severity.color)
                    Text(d.lines.count == 1 ? "Line \(d.lines.lowerBound)" : "Lines \(d.lines.lowerBound)–\(d.lines.upperBound)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 84, alignment: .leading)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(d.message).textSelection(.enabled)
                        if let suggestion = d.suggestion, !d.alternatives.isEmpty {
                            HStack(spacing: 4) {
                                Text("Or:").font(.caption).foregroundStyle(.secondary)
                                ForEach(d.alternatives, id: \.self) { alt in
                                    Button(alt) {
                                        let replacement = suggestion.replacement.hasSuffix(":") ? alt + ":" : alt
                                        model.apply(Suggestion(line: suggestion.line, original: suggestion.original, replacement: replacement), to: item)
                                    }
                                    .buttonStyle(.link)
                                    .font(.caption)
                                }
                            }
                        }
                    }
                    Spacer()
                    if let suggestion = d.suggestion {
                        Button("Fix") { model.apply(suggestion, to: item) }
                            .controlSize(.small)
                            .help("Replace “\(suggestion.original)” with “\(suggestion.replacement)”")
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { focus(d.lines.lowerBound) }
            }
            .listStyle(.inset)
        }
    }
}

/// Explain mode: what the parser saw for each step.
private struct ExplainList: View {
    let result: ConversionResult
    let focusedLine: Int?
    let onSelect: (Int) -> Void

    var body: some View {
        List(Array(result.steps.enumerated()), id: \.offset) { _, trace in
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 3) {
                    detail("Registry", trace.resolvedName.map { "\($0) (id \(trace.resolvedID ?? 0))" } ?? "unknown step")
                    detail("Handler", trace.handler ?? "—")
                    detail("XML steps", trace.xmlSteps.isEmpty ? "none" : "\(trace.xmlSteps.count)")
                    if trace.isDisabled { detail("Disabled", "yes (// prefix)") }
                    ForEach(Array(trace.params.items.enumerated()), id: \.offset) { _, param in
                        detail(param.key.allSatisfy(\.isNumber) ? "Positional \(param.key)" : "“\(param.key)”",
                               param.value.replacingOccurrences(of: "\n", with: " ⏎ "))
                    }
                }
                .padding(.leading, 4)
                .textSelection(.enabled)
            } label: {
                HStack(spacing: 8) {
                    Text(trace.sourceLines.count == 1 ? "\(trace.sourceLines.lowerBound)"
                         : "\(trace.sourceLines.lowerBound)–\(trace.sourceLines.upperBound)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 54, alignment: .leading)
                    Text(trace.isComment ? "# comment" : trace.stepName)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(trace.resolvedName == nil ? Color.red : Color.primary)
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture { onSelect(trace.sourceLines.lowerBound) }
                .background(focusedLine.map { trace.sourceLines.contains($0) } == true ? Color.accentColor.opacity(0.12) : .clear)
            }
        }
        .listStyle(.inset)
    }

    private func detail(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label).font(.caption).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
            Text(value).font(.system(.caption, design: .monospaced))
        }
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

extension ConversionResult.Status {
    var color: Color {
        switch self {
        case .ok: return .green
        case .warnings: return .orange
        case .failed: return .red
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

/// Syntax colours for the output XML.
enum XMLSyntax {
    private static let tag = try! NSRegularExpression(pattern: #"</?([^\s>/!?]+)"#)
    private static let attribute = try! NSRegularExpression(pattern: #"\s([A-Za-z_:][\w.:-]*)="([^"]*)""#)
    private static let cdata = try! NSRegularExpression(pattern: #"<!\[CDATA\[(.*?)\]\]>"#, options: .dotMatchesLineSeparators)
    private static let comment = try! NSRegularExpression(pattern: #"<!--.*?-->"#, options: .dotMatchesLineSeparators)
    private static let declaration = try! NSRegularExpression(pattern: #"<\?.*?\?>"#)

    static func colors(for xml: String) -> [(NSRange, NSColor)] {
        let full = NSRange(location: 0, length: (xml as NSString).length)
        var out: [(NSRange, NSColor)] = []
        for m in tag.matches(in: xml, range: full) { out.append((m.range(at: 1), .systemBlue)) }
        for m in attribute.matches(in: xml, range: full) {
            out.append((m.range(at: 1), .systemPurple))
            out.append((m.range(at: 2), .systemBrown))
        }
        for m in declaration.matches(in: xml, range: full) { out.append((m.range, .secondaryLabelColor)) }
        for m in cdata.matches(in: xml, range: full) {
            out.append((m.range, .tertiaryLabelColor))
            out.append((m.range(at: 1), .labelColor))
        }
        for m in comment.matches(in: xml, range: full) { out.append((m.range, .systemRed)) }
        return out
    }
}
