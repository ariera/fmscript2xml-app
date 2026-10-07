// Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
// SPDX-License-Identifier: GPL-3.0-or-later

/// FMScriptKit converts plain-text FileMaker script steps into `fmxmlsnippet`
/// XML. It has no UI dependencies, so the app, the CLI and the tests share it.
///
/// Entry point: `Converter`.
public enum FMScriptKit {
    public static var version: String { Converter.version }
}
