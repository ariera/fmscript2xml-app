<img src="docs/logo.png" width="128" alt="FM Script Paste logo" align="right">

# FM Script Paste

FileMaker can't paste script steps written as text. A step you see in an
editor, a code review, documentation or an AI assistant has to be retyped by
hand in the Script Workspace, line by line. For experienced developers this
is slow, error-prone and frustrating work.

FM Script Paste removes that work. Copy the steps as text, press **⌃⌥⌘F**,
and paste them into FileMaker as real script steps. The conversion takes a
fraction of a second.

## What it is

A macOS menu bar app that converts plain-text FileMaker script steps on the
clipboard into FileMaker script-step objects, ready to paste into the Script
Workspace.

Planned features:

- Global, configurable shortcut (default ⌃⌥⌘F)
- History of converted snippets (default 20), re-copy any of them from the menu bar
- Editable inspector showing how each input line became XML, with errors,
  warnings and "did you mean" fixes
- No dependency on Python, and FileMaker doesn't need to be installed for the
  conversion

Status: **in development** (Phases 0–3 of [PLAN.md](PLAN.md) done: converter,
diagnostics, menu bar app). History, the full inspector and signed releases
come next.

This is a native Swift port of [fmscript2xml](../fmscript2xml), the Python
converter and CLI.

## Building

Requires macOS 14+, Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`).

```sh
swift test                      # converter tests (public fixtures)
tools/build-app.sh Debug --open # build and run the menu bar app
swift run fmscript2xml script.txt --print --diagnostics   # CLI
```

## Development

After cloning, enable the repository's git hooks:

```sh
git config core.hooksPath .githooks
```

The pre-commit hook (and the same check in CI) rejects fixtures outside
`Tests/Fixtures/public/`. **Never commit production FileMaker scripts**; see
PLAN.md §9 for how to test against them locally.

## Licence

GPL-3.0-or-later. See [LICENSE](LICENSE).

Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
