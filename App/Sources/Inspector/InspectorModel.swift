// Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
// SPDX-License-Identifier: GPL-3.0-or-later

import FMClipboard
import FMHistory
import FMScriptKit
import Foundation
import Observation

/// State of the inspector window (PLAN §6): the selection, editable drafts
/// and their live conversions.
@MainActor
@Observable
final class InspectorModel {
    static let shared = InspectorModel()

    enum Item: Hashable {
        case entry(UUID)
        case scratch(UUID)
    }

    enum StatusFilter: String, CaseIterable, Identifiable {
        case all = "All", ok = "OK", warnings = "Warnings", failed = "Failed"
        var id: String { rawValue }

        func matches(_ status: ConversionResult.Status) -> Bool {
            switch self {
            case .all: return true
            case .ok: return status == .ok
            case .warnings: return status == .warnings
            case .failed: return status == .failed
            }
        }
    }

    /// A working copy of an entry's input (or a scratch), with its live
    /// conversion. Editing never changes the history entry.
    struct Draft {
        var text: String
        var result: ConversionResult
        /// Differs from the entry's input (always true for scratches with text).
        var isEdited: Bool
    }

    struct Scratch: Identifiable, Hashable {
        let id: UUID
        let created: Date
    }

    var selection: Item?
    var statusFilter: StatusFilter = .all
    var search = ""
    private(set) var scratches: [Scratch] = []
    /// Drafts that were edited (observed, so views update).
    private var drafts: [Item: Draft] = [:]
    /// Conversions of unedited entries, computed on first view. Not observed:
    /// filling it while SwiftUI renders must not trigger updates.
    @ObservationIgnored private var cache: [Item: Draft] = [:]
    private var pending: [Item: Task<Void, Never>] = [:]

    private var app: AppModel { .shared }
    private var history: HistoryStore { app.history }

    var filteredEntries: [HistoryEntry] {
        history.entries.filter { entry in
            statusFilter.matches(entry.status)
                && (search.isEmpty || entry.input.localizedCaseInsensitiveContains(search)
                    || (entry.sourceApp?.name.localizedCaseInsensitiveContains(search) ?? false))
        }
    }

    // MARK: Drafts

    func draft(for item: Item) -> Draft {
        if let d = drafts[item] ?? cache[item] { return d }
        let text: String
        switch item {
        case .entry(let id): text = history.entry(id: id)?.input ?? ""
        case .scratch: text = ""
        }
        let d = Draft(text: text, result: app.converter.convert(text, policy: AppSettings.policy), isEdited: false)
        cache[item] = d
        return d
    }

    private func forget(_ item: Item) {
        pending[item]?.cancel()
        drafts[item] = nil
        cache[item] = nil
    }

    /// Edits a draft; the conversion follows after a 150 ms pause.
    func setText(_ text: String, for item: Item) {
        var d = draft(for: item)
        guard d.text != text else { return }
        d.text = text
        d.isEdited = isEdited(text, item)
        drafts[item] = d
        pending[item]?.cancel()
        pending[item] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            self?.reconvertDraft(item)
        }
    }

    private func isEdited(_ text: String, _ item: Item) -> Bool {
        switch item {
        case .entry(let id): return text != history.entry(id: id)?.input
        case .scratch: return !text.isEmpty
        }
    }

    private func reconvertDraft(_ item: Item) {
        guard var d = drafts[item] else { return }
        d.result = app.converter.convert(d.text, policy: AppSettings.policy)
        drafts[item] = d
    }

    /// Applies a diagnostic's fix (e.g. a did-you-mean name) to the draft.
    func apply(_ suggestion: Suggestion, to item: Item) {
        guard let fixed = suggestion.apply(to: draft(for: item).text) else { return }
        setText(fixed, for: item)
        pending[item]?.cancel()
        reconvertDraft(item)
    }

    /// Discards edits.
    func revert(_ item: Item) { forget(item) }

    // MARK: Actions

    /// Copies the draft's steps. An edited draft or a scratch becomes a new
    /// history entry (origin: inspector), which is then selected.
    func copyAsSteps(_ item: Item) {
        pending[item]?.cancel()
        reconvertDraft(item)
        let d = draft(for: item)
        guard let xml = d.result.xml else {
            Feedback.shared.show(.failure("Not copied — fix the errors first"))
            return
        }
        FMClipboard.write(xml, flavor: .scriptSteps, to: app.pasteboard)
        Feedback.shared.show(.success("\(stepCountText(d.result.convertedStepCount)) copied"))

        guard d.isEdited else { return }
        let stored = app.record(HistoryEntry(sourceApp: nil, origin: .inspector, result: d.result))
        forget(item)
        if case .scratch(let id) = item { scratches.removeAll { $0.id == id } }
        if history.entry(id: stored.id) != nil { selection = .entry(stored.id) }
    }

    func setPinned(_ pinned: Bool, id: UUID) {
        history.setPinned(pinned, id: id)
    }

    func reconvertEntry(_ id: UUID) {
        history.reconvert(id: id, converter: app.converter, policy: AppSettings.policy)
        forget(.entry(id))
    }

    func delete(_ item: Item) {
        let ordered = sidebarItems
        let index = ordered.firstIndex(of: item)
        switch item {
        case .entry(let id): history.delete(id: id)
        case .scratch(let id): scratches.removeAll { $0.id == id }
        }
        forget(item)
        if selection == item {
            let remaining = sidebarItems
            selection = index.flatMap { remaining.indices.contains($0) ? remaining[$0] : remaining.last }
        }
    }

    /// Clears the history; pinned entries are kept.
    func clearHistory() {
        for entry in history.unpinnedEntries { forget(.entry(entry.id)) }
        history.clear()
        if case .entry(let id) = selection, history.entry(id: id) == nil { selection = nil }
    }

    /// A new empty draft, not tied to any entry (a playground).
    @discardableResult
    func newScratch(text: String = "") -> Item {
        let scratch = Scratch(id: UUID(), created: .now)
        scratches.insert(scratch, at: 0)
        let item = Item.scratch(scratch.id)
        if !text.isEmpty {
            drafts[item] = Draft(text: text, result: app.converter.convert(text, policy: AppSettings.policy), isEdited: true)
        }
        selection = item
        return item
    }

    /// Selects an entry, or the latest conversion (not a pinned one at the
    /// top of the list). With history off, the last conversion opens as a
    /// scratch.
    func show(entryID: UUID? = nil) {
        if let entryID, history.entry(id: entryID) != nil {
            selection = .entry(entryID)
        } else if let last = app.lastEntry, history.entry(id: last.id) != nil {
            selection = .entry(last.id)
        } else if let newest = history.entries.max(by: { $0.date < $1.date }) {
            selection = .entry(newest.id)
        } else if let last = app.lastEntry, history.capacity == 0 {
            newScratch(text: last.input)
        } else if selection == nil, let first = sidebarItems.first {
            selection = first
        }
    }

    #if DEBUG
    /// Script hooks for checking flows without clicking: "fix" applies the
    /// first suggestion of the selection, "copy" runs Copy as Steps.
    func debugCommand(_ command: String) {
        guard let item = selection else { return }
        switch command {
        case "fix":
            if let s = draft(for: item).result.diagnostics.compactMap(\.suggestion).first { apply(s, to: item) }
        case "copy":
            copyAsSteps(item)
        case "pin":
            if case .entry(let id) = item { setPinned(true, id: id) }
        default:
            break
        }
        debugLog("inspector \(command): edited=\(draft(for: selection ?? item).isEdited) status=\(draft(for: selection ?? item).result.status.rawValue) entries=\(history.entries.count)")
    }
    #endif

    var sidebarItems: [Item] {
        scratches.map { .scratch($0.id) } + filteredEntries.map { .entry($0.id) }
    }

    func title(of item: Item) -> String {
        switch item {
        case .entry(let id): return history.entry(id: id)?.shortTitle() ?? "Deleted"
        case .scratch: return draft(for: item).text.split(whereSeparator: \.isNewline).first.map(String.init) ?? "New draft"
        }
    }
}
