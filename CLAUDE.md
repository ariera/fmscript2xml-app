# CLAUDE.md

fmscript2xml (`io.github.ariera.fmscript2xml`, repo `ariera/fmscript2xml-app`): a native macOS (Swift/SwiftUI, macOS 14+) menu bar app that converts plain-text
FileMaker script steps on the clipboard into FileMaker clipboard objects.

- **Read [PLAN.md](PLAN.md) first.** It holds the architecture, decisions
  (D1–D11), phases and open questions. Update its checklists and decisions log
  as work progresses.
- The Python reference implementation lives at `~/dev/EMBO/fmscript2xml`
  (`src/fmscript2xml/`). Port behaviour from there; when in doubt, the fixtures
  in its `tests/fixtures/` are the source of truth.
- The FileMaker clipboard "binary" format is just the `fmxmlsnippet` XML as
  UTF-8 under the pasteboard type `CorePasteboardFlavorType 0x584D5353` (XMSS).
  No AppleScript, and FileMaker doesn't need to be installed.
- `FMScriptKit` must stay free of AppKit/SwiftUI so it can be tested and used
  from the CLI.
- Every parsed step must carry its source line range (needed by the inspector).
- **Never commit production FileMaker scripts** (D14). Real-world fixtures are
  read from `$FMSCRIPT_PRIVATE_FIXTURES` at test time only. Committed fixtures
  under `Tests/Fixtures/public/` must be synthetic, with no EMBO table, field,
  layout or script names.
- Licence: GPL-3.0-or-later.
- Copyright header for source files:
  `Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.`
  followed by `SPDX-License-Identifier: GPL-3.0-or-later`.
- The repo is public and commits go straight to `main`. Check every commit for
  production script content before pushing.
- Implementation brief and scope: PLAN.md §14.
