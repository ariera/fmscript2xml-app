// Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
// SPDX-License-Identifier: GPL-3.0-or-later

import FMScriptKit
import Foundation
import Observation

/// Conversion history (PLAN §5): newest first, bounded, failed runs
/// included, optionally persisted as JSON.
@MainActor
@Observable
public final class HistoryStore {
    public nonisolated static let defaultCapacity = 20
    public nonisolated static let capacityRange = 0...200

    /// Newest first.
    public private(set) var entries: [HistoryEntry] = []

    /// Maximum number of entries; 0 disables history.
    public private(set) var capacity: Int

    /// Keep history after quitting. When off, history lives in memory only
    /// and the file is deleted (scripts can contain credentials).
    public private(set) var persists: Bool

    /// The JSON file, or nil for an in-memory store.
    public let fileURL: URL?

    /// Last error while reading or writing the file, for the UI.
    public private(set) var lastError: String?

    /// `~/Library/Application Support/fmscript2xml-app/history.json`
    public nonisolated static var defaultFileURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "fmscript2xml-app", directoryHint: .isDirectory)
            .appending(path: "history.json")
    }

    public init(fileURL: URL? = HistoryStore.defaultFileURL, capacity: Int = HistoryStore.defaultCapacity, persists: Bool = true) {
        self.fileURL = fileURL
        self.capacity = min(max(capacity, Self.capacityRange.lowerBound), Self.capacityRange.upperBound)
        self.persists = persists
        if persists { load() } else { deleteFile() }
        trim()
    }

    // MARK: Settings

    /// Sets the capacity (clamped to 0–200); lowering it drops the oldest entries.
    public func setCapacity(_ value: Int) {
        capacity = min(max(value, Self.capacityRange.lowerBound), Self.capacityRange.upperBound)
        trim()
        save()
    }

    public func setPersists(_ value: Bool) {
        persists = value
        if persists { save() } else { deleteFile() }
    }

    // MARK: Changes

    /// Adds a conversion. If its input is identical to the newest entry's,
    /// that entry is refreshed (date, result, source) instead of adding a new
    /// one. Returns the stored entry, or nil when history is disabled.
    @discardableResult
    public func record(_ entry: HistoryEntry) -> HistoryEntry? {
        guard capacity > 0 else { return nil }
        if var newest = entries.first, newest.input == entry.input {
            newest.date = entry.date
            newest.sourceApp = entry.sourceApp
            newest.origin = entry.origin
            newest.xml = entry.xml
            newest.status = entry.status
            newest.diagnostics = entry.diagnostics
            newest.stepCount = entry.stepCount
            newest.duration = entry.duration
            newest.converterVersion = entry.converterVersion
            entries[0] = newest
        } else {
            entries.insert(entry, at: 0)
            trim()
        }
        save()
        return entries.first
    }

    public func entry(id: UUID) -> HistoryEntry? {
        entries.first { $0.id == id }
    }

    /// Re-runs the conversion of an entry with the current converter.
    @discardableResult
    public func reconvert(id: UUID, converter: Converter = Converter(), policy: ConversionPolicy) -> HistoryEntry? {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return nil }
        entries[i].update(with: converter.convert(entries[i].input, policy: policy))
        save()
        return entries[i]
    }

    public func delete(id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    public func clear() {
        entries.removeAll()
        save()
    }

    // MARK: Persistence

    private func trim() {
        if entries.count > capacity { entries.removeLast(entries.count - capacity) }
    }

    private struct File: Codable {
        var version = 1
        var entries: [HistoryEntry]
    }

    private func load() {
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            entries = try decoder.decode(File.self, from: data).entries
            lastError = nil
        } catch {
            // Keep the unreadable file for inspection rather than overwrite it
            let backup = fileURL.deletingPathExtension().appendingPathExtension("unreadable.json")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            lastError = "The history file couldn't be read and was moved to \(backup.lastPathComponent)."
        }
    }

    private func save() {
        guard persists, let fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(File(entries: entries)).write(to: fileURL, options: [.atomic])
            // Scripts can contain credentials: owner-only access
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            lastError = nil
        } catch {
            lastError = "The history couldn't be saved: \(error.localizedDescription)"
        }
    }

    private func deleteFile() {
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }
}
