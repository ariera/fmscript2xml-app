// Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
// SPDX-License-Identifier: GPL-3.0-or-later

import FMScriptKit
import Foundation

/// The app that was frontmost when a conversion ran.
public struct SourceApp: Sendable, Hashable, Codable {
    public let name: String
    public let bundleIdentifier: String?

    public init(name: String, bundleIdentifier: String?) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
    }
}

/// Where a conversion was started.
public enum ConversionOrigin: String, Sendable, Hashable, Codable {
    /// The global shortcut or the menu bar's Convert Clipboard.
    case hotkey
    /// Copy as Steps from an edited draft in the inspector.
    case inspector
}

/// One conversion in the history (PLAN §5).
public struct HistoryEntry: Sendable, Hashable, Codable, Identifiable {
    public let id: UUID
    public var date: Date
    public var sourceApp: SourceApp?
    public var origin: ConversionOrigin
    public var input: String
    /// The XML that was (or would be) copied; nil when the conversion failed.
    public var xml: String?
    public var status: ConversionResult.Status
    public var diagnostics: [Diagnostic]
    /// Input steps that produced XML.
    public var stepCount: Int
    public var duration: Duration
    public var converterVersion: String

    public init(
        id: UUID = UUID(),
        date: Date = .now,
        sourceApp: SourceApp?,
        origin: ConversionOrigin,
        result: ConversionResult
    ) {
        self.id = id
        self.date = date
        self.sourceApp = sourceApp
        self.origin = origin
        self.input = result.input
        self.xml = result.xml
        self.status = result.status
        self.diagnostics = result.diagnostics
        self.stepCount = result.convertedStepCount
        self.duration = result.duration
        self.converterVersion = Converter.version
    }

    /// Replaces the conversion fields with `result`, keeping id, input and source.
    public mutating func update(with result: ConversionResult) {
        xml = result.xml
        status = result.status
        diagnostics = result.diagnostics
        stepCount = result.convertedStepCount
        duration = result.duration
        converterVersion = Converter.version
    }

    /// First non-empty input line, for lists and menus.
    public var title: String {
        let line = input.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? "(empty)"
        return line
    }

    /// `title`, shortened to `maxLength` characters.
    public func shortTitle(maxLength: Int = 48) -> String {
        title.count <= maxLength ? title : String(title.prefix(maxLength - 1)) + "…"
    }
}
