// Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Minimal metadata for one FileMaker script step.
public struct StepDefinition: Sendable, Hashable, Decodable {
    public let id: Int
    public let name: String
    public let xmlStepName: String
    public let enableDefault: Bool

    enum CodingKeys: String, CodingKey {
        case id, name
        case xmlStepName = "xml_step_name"
        case enableDefault = "enable_default"
    }

    public init(id: Int, name: String, xmlStepName: String? = nil, enableDefault: Bool = true) {
        self.id = id
        self.name = name
        self.xmlStepName = xmlStepName ?? name
        self.enableDefault = enableDefault
    }
}

/// Registry of FileMaker script step definitions, loaded from the bundled
/// `steps.json` (the same file the Python implementation ships).
public struct StepRegistry: Sendable {
    public static let shared = StepRegistry()

    private let definitions: [String: StepDefinition]
    /// Step names in file order.
    public let stepNames: [String]

    public init() {
        guard let url = Bundle.module.url(forResource: "steps", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { fatalError("FMScriptKit: missing steps.json resource") }
        self.init(json: data)
    }

    init(json data: Data) {
        guard let defs = try? JSONDecoder().decode([String: StepDefinition].self, from: data)
        else { fatalError("FMScriptKit: invalid steps.json") }
        definitions = defs
        stepNames = defs.keys.sorted()
    }

    /// Looks up a step by name, tolerating a trailing space on either side
    /// (one registry name, "Open Manage Layouts ", has one).
    public func get(_ stepName: String) -> StepDefinition? {
        if let d = definitions[stepName] { return d }
        if !stepName.pyEndsWith(" "), let d = definitions[stepName + " "] { return d }
        let stripped = stepName.pyRStrip()
        if !stripped.pyEquals(stepName), let d = definitions[stripped] { return d }
        return nil
    }

    public func get(id: Int) -> StepDefinition? {
        allSteps.first { $0.id == id }
    }

    public var allSteps: [StepDefinition] { stepNames.map { definitions[$0]! } }
}
