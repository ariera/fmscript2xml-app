# FM Script Paste

A macOS menu bar app that converts plain-text FileMaker script steps on the
clipboard into FileMaker script-step objects, ready to paste into the Script
Workspace. Press **⌃⌥⌘F**, then paste in FileMaker.

Planned features:

- Global, configurable shortcut (default ⌃⌥⌘F)
- History of converted snippets (default 20), re-copy any of them from the menu bar
- Editable inspector showing how each input line became XML, with errors,
  warnings and "did you mean" fixes
- No dependency on Python, and FileMaker doesn't need to be installed for the
  conversion

Status: **planning**. See [PLAN.md](PLAN.md).

This is a native Swift port of [fmscript2xml](../fmscript2xml), the Python
converter and CLI.

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
