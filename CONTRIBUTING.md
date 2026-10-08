# Contributing to FM Script Paste

Thank you for helping. This file explains how the project is organised, how to
test changes, and the rules every contribution follows.

## The one rule: no production scripts

**Never commit production FileMaker scripts**, or any part of them: no real
table, field, layout or script names. This repository is public. (PLAN.md D14.)

- Public test fixtures live in `Tests/Fixtures/public/` and must be synthetic.
- To reproduce a bug from a real script, write a small synthetic script that
  shows the same problem, and add it as a fixture (see below).
- Real scripts can be used for local testing only, from a directory outside
  the repository: `FMSCRIPT_PRIVATE_FIXTURES=/path/to/fixtures swift test`.

Enable the git hooks after cloning:

```sh
git config core.hooksPath .githooks
```

The pre-commit hook rejects files under `Tests/Fixtures/` outside `public/`.
If `FMSCRIPT_PRIVATE_FIXTURES` is set, it also rejects exact copies of private
fixtures. You can list names that must never be committed, one per line, in
`.git/info/fmscript-denylist` (not tracked). CI runs the location check too.

## Layout

| Path | What |
|---|---|
| `Sources/FMScriptKit` | The converter: parser, step handlers, XML output, diagnostics. No AppKit or SwiftUI. |
| `Sources/FMClipboard` | Reading and writing FileMaker objects on the pasteboard. |
| `Sources/FMHistory` | Conversion history (pure Foundation). |
| `Sources/fmscript2xml` | Command-line tool. |
| `App/` | The menu bar app (SwiftUI). `App/project.yml` is the XcodeGen spec; the `.xcodeproj` is generated, not committed. |
| `Tests/` | Unit tests, fixture conformance tests and the fixtures. |
| `tools/` | Fixture, differential-test, icon, build and release scripts. |

## Testing

```sh
swift test                          # all package tests, public fixtures
tools/build-app.sh Debug            # the app compiles
```

Every fixture is a folder with `input.txt` and `expected.xml`. To add one:

```sh
tools/new-fixture.sh MyCase path/to/input.txt --reference swift
```

Check the generated `expected.xml` by hand: it records the current behaviour,
so it must be correct before you commit it. Fixtures copied from FileMaker
itself are compared semantically; generated ones byte for byte (see
`Tests/Fixtures/public/README.md`).

The Swift converter reproduces the original Python implementation byte for
byte. While both exist, `tools/diff-against-python.sh` compares them on every
fixture. The Python implementation is frozen (PLAN.md D13): fixes land here,
each with a fixture.

## Code

- Swift 6 language mode with strict concurrency; Swift Testing for tests.
- Match the style of the surrounding code. Comments explain why, not what.
- Every source file starts with the copyright and licence header:

  ```swift
  // Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
  // SPDX-License-Identifier: GPL-3.0-or-later
  ```

- Every parsed step keeps its source line range; the inspector depends on it.
- Small, focused commits with clear messages.

## Releases

Releases are built, signed with EMBO's Developer ID, notarised and published
from the maintainer's Mac with `tools/release.sh <version>`. No signing
secrets are stored in GitHub. See the comments at the top of the script.

## Licence

By contributing, you agree that your contributions are licensed under
GPL-3.0-or-later, the licence of this project.
