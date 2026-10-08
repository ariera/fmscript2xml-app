// Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
// SPDX-License-Identifier: GPL-3.0-or-later

import FMHistory
import FMScriptKit
import Foundation
import Testing

@MainActor
@Suite struct HistoryStoreTests {
    let converter = Converter()

    func entry(_ text: String, date: Date = .now) -> HistoryEntry {
        HistoryEntry(date: date, sourceApp: SourceApp(name: "TextEdit", bundleIdentifier: "com.apple.TextEdit"),
                     origin: .hotkey, result: converter.convert(text))
    }

    func tempFile() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "fmhistory-\(UUID().uuidString)/history.json")
    }

    @Test func newestFirstAndBounded() {
        let store = HistoryStore(fileURL: nil, capacity: 3)
        for i in 1...5 { store.record(entry("# step \(i)")) }
        #expect(store.entries.map(\.title) == ["# step 5", "# step 4", "# step 3"])
    }

    @Test func failedRunsCountTowardTheLimit() {
        let store = HistoryStore(fileURL: nil, capacity: 2)
        store.record(entry("Beep"))
        store.record(entry("Go to Layuot"))
        store.record(entry("Bep"))
        #expect(store.entries.map(\.status) == [.failed, .failed])
    }

    @Test func identicalInputRefreshesTheNewestEntry() {
        let store = HistoryStore(fileURL: nil)
        let first = store.record(entry("Beep", date: Date(timeIntervalSince1970: 0)))!
        store.record(entry("Beep", date: Date(timeIntervalSince1970: 100)))
        #expect(store.entries.count == 1)
        #expect(store.entries[0].id == first.id)
        #expect(store.entries[0].date == Date(timeIntervalSince1970: 100))
        store.record(entry("Halt Script"))
        store.record(entry("Beep"))
        #expect(store.entries.count == 3)  // only the newest is de-duplicated
    }

    @Test func zeroCapacityDisablesHistory() {
        let store = HistoryStore(fileURL: nil, capacity: 0)
        #expect(store.record(entry("Beep")) == nil)
        #expect(store.entries.isEmpty)
        let other = HistoryStore(fileURL: nil, capacity: 5)
        for i in 1...4 { other.record(entry("# \(i)")) }
        other.setCapacity(2)
        #expect(other.entries.count == 2)
        other.setCapacity(500)
        #expect(other.capacity == 200)
    }

    @Test func persistsAcrossLaunches() throws {
        let url = tempFile()
        let store = HistoryStore(fileURL: url)
        store.record(entry("Set Variable [ $x ; Value: 1 ]"))
        store.record(entry("Go to Layuot"))
        let reloaded = HistoryStore(fileURL: url)
        #expect(reloaded.entries == store.entries)
        #expect(reloaded.entries[0].diagnostics.first?.code == .unknownStep)
        let perms = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(perms == 0o600)
    }

    @Test func notPersistingDeletesTheFile() {
        let url = tempFile()
        let store = HistoryStore(fileURL: url)
        store.record(entry("Beep"))
        #expect(FileManager.default.fileExists(atPath: url.path))
        store.setPersists(false)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        store.record(entry("Halt Script"))
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(store.entries.count == 2)
        #expect(HistoryStore(fileURL: url).entries.isEmpty)
    }

    @Test func unreadableFileIsSetAside() throws {
        let url = tempFile()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        let store = HistoryStore(fileURL: url)
        #expect(store.entries.isEmpty)
        #expect(store.lastError != nil)
        #expect(FileManager.default.fileExists(atPath: url.deletingPathExtension().appendingPathExtension("unreadable.json").path))
    }

    @Test func deleteClearAndReconvert() {
        let store = HistoryStore(fileURL: nil)
        let a = store.record(entry("Beep"))!
        let b = store.record(entry("Halt Script"))!
        store.delete(id: a.id)
        #expect(store.entries.map(\.id) == [b.id])
        let again = store.reconvert(id: b.id, policy: .strict)
        #expect(again?.status == .ok)
        store.clear()
        #expect(store.entries.isEmpty)
    }

    @Test func titles() {
        #expect(entry("\n\n   Set Variable [ $x ; Value: 1 ]\nBeep").title == "Set Variable [ $x ; Value: 1 ]")
        #expect(entry(String(repeating: "x", count: 80)).shortTitle(maxLength: 10).count == 10)
    }
}
