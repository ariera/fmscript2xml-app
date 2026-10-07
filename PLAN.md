# FM Script Paste (fmscript2xml-app) — Development plan

A native macOS menu bar app that turns plain-text FileMaker script steps on the
clipboard into FileMaker script-step objects you can paste straight into the
Script Workspace, triggered by a global keyboard shortcut.

It replaces today's setup (Python `fmscript2xml` CLI + Automator Quick Action +
Services shortcut) with a single signed app, and adds a snippet history and a
visual inspector for debugging conversions.

- Reference implementation: `~/dev/EMBO/fmscript2xml` (Python, v0.5.3)
- Status: planning
- Last updated: 2026-10-07

---

## 1. Key finding: no FileMaker "compiler" is involved

The Python `fmclip.py` assumes FileMaker registers a handler that compiles XML
into a proprietary binary format, so FileMaker must be installed. **This is not
the case.** Verified on 2026-10-07:

1. A 160-byte `fmxmlsnippet` XML file was put on the clipboard via the existing
   AppleScript path (`read file as «class XMSS»`).
2. Reading the pasteboard back from Swift showed exactly 160 bytes, identical
   to the file (`<?xml version="1.0"…><fmxmlsnippet…>`), under the types
   `CorePasteboardFlavorType 0x584D5353` and `dyn.ah62d4rv4gk8zuxnxnq`.
   `0x584D5353` is ASCII `XMSS`.

AppleScript's `as «class XMSS»` only tags raw bytes with a four-char type code.
FileMaker parses the XML itself when you paste. So writing the clipboard is:

```swift
let pb = NSPasteboard.general
pb.clearContents()
pb.setData(Data(xml.utf8), forType: .init("CorePasteboardFlavorType 0x584D5353"))
```

Consequences:

- **FileMaker is not a runtime dependency.** No AppleScript, no temp files.
  The app may *show* whether FileMaker Pro is installed (informational only),
  but never blocks on it.
- The Python `fmclip.py` docstring and README claims are wrong and should be
  corrected in the Python repo (tracked separately, see §12).

---

## 2. Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| D1 | **Rewrite the converter in Swift** (no bundled Python) | Core is ~3,600 lines of stdlib-only Python (lark/lxml/yaml are not imported at runtime). Native gives ~3–5 MB app vs 40–80 MB, in-process conversion (<10 ms vs ~150–300 ms process spawn), standard signing/notarization, and a rich in-process data model for the inspector. |
| D2 | **Menu bar app** (`LSUIElement`, no Dock icon), launch at login via `SMAppService` | It's a utility that should stay out of the way. |
| D3 | **Global hotkey via [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)**, default **⌃⌥⌘F** | Provides the recorder UI for Settings and conflict handling. Uses Carbon `RegisterEventHotKey`, so **no Accessibility permission** needed. |
| D4 | **Clipboard written natively** with `NSPasteboard` under the XMSS flavor | See §1. |
| D5 | **History**: newest-first, bounded, **default 20**, configurable; **failed runs count** toward the limit | Failures are the most useful entries to debug. One list keeps the model simple. |
| D6 | **Editable inspector** with live reconversion | Doubles as a test bench for the parser. |
| D7 | **"Did you mean" suggestions** for unknown step names, in v1 | Cheap with 167 known step names; high value for typos and AI-generated scripts. |
| D8 | **Source map is part of the core data model from day one** | The inspector's line↔step linking needs it, and it can't be bolted on later without reworking the parser. |
| D9 | **Shared fixture corpus** is the contract between Python and Swift | 885 real-world + 14 targeted fixtures (`input.txt` → `expected.xml`) already exist. Swift becomes the primary implementation; Python is frozen once parity is reached. |
| D10 | **Distribution: signed with EMBO's Developer ID, notarized DMG on GitHub Releases** (not the App Store) | Open-source project; GitHub Releases doubles as the update feed. Sandboxing would work, but adds friction for no gain. |
| D11 | **Minimum macOS 14 (Sonoma)** | SwiftUI `@Observable`, `MenuBarExtra`, `SMAppService`, `SettingsLink`. |
| D12 | **Fully open source, GPL-3.0-or-later**, hosted at `github.com/ariera/fmscript2xml-app` | Copyleft keeps forks open. Compatible with the MIT dependencies (KeyboardShortcuts, Sparkle). Rules out the Mac App Store, which D10 already does. |
| D13 | **Python implementation is frozen** once Swift reaches parity | One implementation to maintain. |
| D14 | **Production FileMaker scripts are never committed** | They are EMBO's internal code. They may be used for local testing only (§9). |
| D15 | **App name: FM Script Paste**; bundle ID `io.github.ariera.fmscriptpaste`; repo stays `ariera/fmscript2xml-app` | Name says what it does. Define the name and bundle ID in one place (`project.yml` / a `Branding` constant). |
| D16 | **Copyright notice**: "Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera." | Credits the original author; fits a copyleft project open to contributions. Used in source headers and the About window. |
| D17 | **Tooling**: XcodeGen `project.yml` for the app target (no hand-edited `.xcodeproj`); SwiftPM for `FMScriptKit`, `FMClipboard` and the CLI; Swift 6 language mode with strict concurrency; Swift Testing | Agents and diffs handle text project files well. |
| D18 | **No telemetry or crash reporting; English only; CLI is a developer/testing tool in v1** | Keeps v1 small and private. |

---

## 3. Architecture

```
fmscript2xml-app/
├── Package.swift                  # SwiftPM: core library + CLI + tests
├── Sources/
│   ├── FMScriptKit/               # Pure Swift, no AppKit. The converter.
│   │   ├── Lexing/                # CalcScanner (strings, comments, brackets), line joiner
│   │   ├── Parsing/               # Parser → [ParsedStep] with source ranges
│   │   ├── Registry/              # StepRegistry (bundled steps.json)
│   │   ├── Generation/            # XMLBuilder, StepHandler protocol, handlers/*
│   │   ├── Diagnostics/           # Diagnostic, codes, StepNameSuggester
│   │   └── Converter.swift        # convert(_:) -> ConversionResult
│   ├── FMClipboard/               # NSPasteboard read/write for FM flavors
│   └── fmscript2xml/              # Swift CLI (drop-in for the Python CLI)
├── App/                           # Xcode app target (SwiftUI)
│   ├── AppDelegate / App.swift    # MenuBarExtra, lifecycle
│   ├── HotKey/                    # KeyboardShortcuts names + handler
│   ├── Pipeline/                  # ClipboardConversionService
│   ├── History/                   # HistoryStore, HistoryEntry
│   ├── Inspector/                 # Inspector window (split view)
│   ├── Settings/                  # Settings scene
│   └── Feedback/                  # HUD, sounds, notifications
├── Tests/
│   ├── FMScriptKitTests/          # Unit tests ported from Python
│   ├── ConformanceTests/          # Fixture runner + semantic XML comparator
│   └── Fixtures/
│       ├── public/                # Synthetic fixtures, committed
│       └── private/               # gitignored; production scripts for local runs only
└── tools/
    └── diff-against-python.sh     # Differential test: run both impls on all inputs
```

`FMScriptKit` has no UI dependencies. That keeps it testable from the command
line and lets the CLI target replace the Python CLI.

### 3.1 Core data model

```swift
struct ConversionResult {
    let input: String
    let xml: String?                 // nil if conversion failed under strict policy
    let steps: [StepTrace]           // one per parsed input step
    let diagnostics: [Diagnostic]
    let duration: Duration
    var status: Status { … }         // .ok / .warnings / .failed
}

struct StepTrace {
    let sourceLines: ClosedRange<Int>   // multi-line steps span several lines
    let stepName: String                // as written
    let resolvedName: String?           // registry match
    let handler: String                 // handler type used, for debugging
    let xmlSteps: Range<Int>            // index range into emitted <Step>s
                                        // (1→many: ID policy emits a helper comment + step)
    let xmlTextRange: Range<String.Index>? // span in the pretty-printed XML, for highlighting
}

struct Diagnostic {
    enum Severity { case error, warning, info }
    let severity: Severity
    let code: Code                   // .unknownStep, .unbalancedBrackets, .idLeftBlank,
                                     // .unknownParameter, .emptyInput, …
    let lines: ClosedRange<Int>
    let column: Int?
    let message: String
    let suggestion: Suggestion?      // e.g. replace "Go to Layuot" with "Go to Layout"
}
```

### 3.2 Conversion policy

The Python converter has `stop_on_error` (strict) vs continue-on-error. The app
uses **strict by default**: if any `error` diagnostic exists, the clipboard is
left untouched and the run is recorded as failed. A setting allows "copy what
converted" (continue-on-error). Warnings never block.

---

## 4. Hotkey flow

1. Hotkey fires → capture `NSWorkspace.shared.frontmostApplication` (name +
   bundle id) for the history entry.
2. Read `NSPasteboard.general.string(forType: .string)`.
   - Empty or no text → if the clipboard already holds XMSS, show
     "Already FileMaker steps"; otherwise show "Clipboard has no text". No
     history entry.
3. `Converter.convert(text)` → `ConversionResult`.
4. Success/warnings → write XMSS to the pasteboard (§1), then HUD + sound
   ("4 steps ready to paste", plus a warning count if any).
5. Failure → leave the clipboard alone; notification with the first error
   ("Line 3: unknown step 'Go to Layuot'. Did you mean 'Go to Layout'?") and an
   **Open inspector** action.
6. Record the result in history (both outcomes).
7. Optional (off by default): auto-paste by sending ⌘V. This needs
   Accessibility permission, so it's requested only when the user turns it on.

---

## 5. History

- **Order and size**: newest first; capacity from Settings (default **20**,
  range 0–200; **0 disables history**). When full, the oldest entry is dropped.
  Failed runs count toward the capacity.
- **Entry**: `id`, `date`, `sourceApp`, `origin` (`.hotkey` / `.inspector`),
  `input`, `xml`, `status`, `diagnostics`, `stepCount`, `duration`,
  `converterVersion`.
- **De-duplication**: if the input is identical to the newest entry's, move
  that entry to the top (refresh date and result) instead of adding a new one.
- **Actions**: copy as FileMaker steps (default click), copy XML as text, copy
  original text, open in inspector, reconvert with the current converter,
  delete.
- **Storage**: JSON file in `~/Library/Application Support/fmscript2xml-app/history.json`,
  written atomically. Setting: **Keep history after quitting** (default on).
  Off keeps it in memory only, because scripts can contain hard-coded
  credentials or endpoints. **Clear history** in Settings and the inspector.
- **Menu bar**: the last 5–10 entries, each with a status dot
  (ok / warnings / error), first line of input, and relative time.

---

## 6. Inspector (editable)

A regular window (`Window` scene), opened from the menu bar or from a failure
notification.

- **Layout**: `NavigationSplitView`
  - Sidebar: full history list with status dots, filter by status, search.
  - Detail: header (time, source app, step count, duration, status) and
    toolbar (**Copy as steps**, Copy XML, Reconvert, Delete).
  - Body: **Input** (editable, line numbers) beside **Output XML** (read-only,
    syntax-tinted), with a **diagnostics list** at the bottom.
- **Line↔step linking**: hovering or selecting input lines highlights the XML
  steps they produced, and the reverse. Error lines get a red gutter mark,
  warning lines amber.
- **Live editing**: edits reconvert in-process after a ~150 ms debounce.
  Editing creates a working draft; the history entry is not changed until you
  act on it.
- **Copy as steps** from an edited draft writes XMSS and records a **new**
  history entry with `origin: .inspector`.
- **Diagnostics list**: click to jump to the line. Diagnostics with a
  suggestion show a **Fix** button that applies it to the draft
  (for example the did-you-mean replacement).
- **Explain mode** (debug disclosure per step): parsed name, resolved registry
  entry (id, XML name), handler, parsed params (positional + named). This shows
  what the parser actually saw, which is the main thing you need when a step
  converts wrongly.
- **New scratch**: an empty draft not tied to any entry, used as a playground.

---

## 7. "Did you mean" suggestions

- Applied to **unknown step names**. Candidates are the 167 registry names plus
  known aliases.
- Normalize first: case-insensitive, collapse whitespace, unify typographic
  quotes, ignore a trailing `…`.
- Rank by Damerau–Levenshtein distance (transpositions such as `Layuot` →
  `Layout` count as 1). Accept if distance ≤ max(2, 25% of length). Tie-break
  on shared prefix length.
- Report the best match as `Diagnostic.suggestion`. Show up to 3 alternatives in
  the inspector.
- Later: the same approach for named parameter labels (`Animaton:` →
  `Animation:`).

---

## 8. Settings

| Setting | Default | Notes |
|---|---|---|
| Convert shortcut | ⌃⌥⌘F | KeyboardShortcuts recorder |
| Open inspector shortcut | none | Optional second shortcut |
| History length | 20 | 0–200; 0 disables |
| Keep history after quitting | on | |
| On errors | Leave clipboard unchanged | Alternative: copy what converted |
| Feedback | HUD + sound | Toggle each |
| Auto-paste after converting | off | Requests Accessibility permission when turned on |
| Launch at login | on (asked on first run) | `SMAppService.mainApp` |
| FileMaker Pro detected | read-only | Lists installed versions; informational only |

---

## 9. Keeping Python and Swift in step

- Each fixture is a folder with `input.txt` and `expected.xml`.
- **Public fixtures** (`Tests/Fixtures/public/`, committed): synthetic scripts
  only. Start from the Python repo's 14 `tests/fixtures/simple/` cases and the
  root `.txt` files, **after replacing EMBO-specific names** (for example
  `elc_grp_joi_PSUB__Person#Committee`, `SCO__Scores`, STF messages) with
  neutral ones. Grow this set until every handler and parser edge case has
  coverage, so CI is meaningful without production data.
- **Private fixtures** (production scripts, D14): **never committed**, never
  copied into this repo's tracked tree. The conformance runner reads them from
  the directory in `FMSCRIPT_PRIVATE_FIXTURES` (for example the Python repo's
  `tests/fixtures/real_world/`, 885 scripts) and skips them when the variable
  is unset. `Tests/Fixtures/private/` is gitignored as a fallback location.
- Safeguards: `.gitignore` entries, a pre-commit hook that rejects files under
  `Tests/Fixtures/` outside `public/`, and a CI check doing the same.
- Bug reports from production scripts become **new synthetic public
  fixtures** that reproduce the issue without the original content.
- Port `tests/utils/semantic_comparator.py` so comparison ignores formatting
  and the ID-policy differences the Python suite already tolerates.
- `tools/diff-against-python.sh`: run both CLIs over every `input.txt` and diff
  semantically. This is the parity gate in Phase 1.
- After parity: Swift is the only maintained implementation. Bug fixes land
  in Swift, with a new fixture. The Python package is frozen (D13): final
  release, README pointing to this project, repo archived.

---

## 10. Phases

### Phase 0 — Spikes (1–2 days)

Goal: retire the risky assumptions before writing the port.

- [ ] Swift script writes XMSS XML to the pasteboard; paste into FileMaker Pro
      22, 26 and DEV Script Workspace.
- [ ] **Text alongside XMSS?** Write both XMSS and `public.utf8-plain-text`;
      check FileMaker still pastes steps (not text) in the Script Workspace.
      If so, keep the text flavor so pasting elsewhere still gives text.
- [ ] Minimal `MenuBarExtra` app with a KeyboardShortcuts hotkey; confirm it
      fires while FileMaker is frontmost and needs no Accessibility permission.
- [ ] Capture the frontmost app at hotkey time.
- [ ] Check the XMSC (whole scripts) and XMFN (custom functions) flavors work
      the same way, for later.

Exit: written findings appended to §13 (Decisions log).

### Phase 1 — Core port: `FMScriptKit` (largest phase)

Port order follows the dependency chain. Each module lands with its unit tests
ported from Python.

1. [ ] Package skeleton, bundled `steps.json`, `StepRegistry`.
2. [ ] `CalcScanner`: string literals, `//` and `/* */` calc comments, bracket
       balance (see Python commits 22f6f5f, 1766569).
3. [ ] Line joiner for multi-line steps (preserve line breaks inside calcs).
4. [ ] `Parser` → `[ParsedStep]` **with source line ranges** (D8): name,
       params (positional + named), disabled (`//`), comments (`#`).
5. [ ] `XMLBuilder`: `fmxmlsnippet` wrapper, CDATA for calculations, ID-policy
       helper comments.
6. [ ] Handlers, by group: comment, variable, control (If/Else If/Else/End If,
       Exit Script, Pause/Resume), window, layout, field, script, find,
       dialog (Show Custom Dialog buttons), communication, misc, generic
       fallback.
7. [ ] `Converter.convert` → `ConversionResult` with `StepTrace`s.
8. [ ] Swift CLI `fmscript2xml` with the same flags as the Python CLI.
9. [ ] Conformance runner + semantic comparator; differential script.
10. [ ] Scrubbed public fixtures, pre-commit hook and CI check (§9).

Exit: all public fixtures pass in CI; all 885 private fixtures pass locally;
ported unit tests pass; differential run against Python shows no semantic
differences.

### Phase 2 — Diagnostics, source map, suggestions

- [ ] `Diagnostic` codes emitted by the parser and handlers (unknown step,
      unbalanced brackets, unknown parameter, ID left blank, empty input).
- [ ] `StepTrace.xmlSteps` and `xmlTextRange` filled in by the generator,
      including 1→many for ID-policy helper comments.
- [ ] `StepNameSuggester` (§7) with tests on real typos.

Exit: every fixture produces a complete, consistent source map (test asserts
every emitted `<Step>` maps back to exactly one input range).

### Phase 3 — App MVP (replaces Automator)

- [ ] Xcode app target, `MenuBarExtra`, `LSUIElement`.
- [ ] Hotkey → pipeline (§4) → XMSS on clipboard.
- [ ] HUD + sound + failure notification with "Open inspector".
- [ ] Settings: shortcut, on-errors policy, feedback, launch at login,
      FileMaker detection.
- [ ] First-run window: explains the shortcut and offers launch at login.

Exit: daily use replaces the Automator Quick Action.

### Phase 4 — History

- [ ] `HistoryStore` (§5) with persistence, capacity, de-duplication.
- [ ] Menu bar recent list with status dots; click to re-copy.
- [ ] Settings: history length, keep after quitting, clear.

### Phase 5 — Inspector

- [ ] Read-only first: sidebar, input/output panes, diagnostics list, hover
      linking, explain mode.
- [ ] Editable: live reconvert, Fix buttons for suggestions, Copy as steps →
      new entry, scratch draft.

### Phase 6 — Packaging and release

- [ ] App icon, About window (converter version, links).
- [ ] EMBO Developer ID signing, hardened runtime, notarization, DMG.
- [ ] Local release script `tools/release.sh`, run on Alejandro's Mac (Q6):
      build → `codesign` with EMBO's Developer ID Application certificate
      from the login keychain → `xcrun notarytool submit --keychain-profile`
      → staple → DMG → upload to a GitHub Release with `gh release create`.
      No signing secrets in GitHub.
      Prerequisites: EMBO's Account Holder/Admin issues the Developer ID
      Application certificate; notarisation credentials stored once with
      `xcrun notarytool store-credentials`; Sparkle EdDSA key in the keychain.
- [ ] Updates: Sparkle with an appcast published from GitHub Releases.
- [ ] GPL-3.0-or-later notices in source headers and the About window;
      CONTRIBUTING.md (including the no-production-scripts rule).
- [ ] User README: install, shortcut, troubleshooting; retire
      `docs/automator-keyboard-shortcut.md` in the Python repo.

### Later / ideas

- Reverse direction: FileMaker steps on the clipboard → plain text (needs an
  XML → text renderer).
- Other object types: whole scripts (XMSC), custom functions (XMFN).
- Did-you-mean for parameter labels.
- Services menu entry ("Convert selection to FileMaker steps").
- Share a fixture as a bug report straight from the inspector (input +
  expected/actual XML).

---

## 11. Risks

| Risk | Mitigation |
|---|---|
| Subtle behaviour differences in the port (regex semantics, Unicode, whitespace) | 899 fixtures + differential testing in Phase 1; port the semantic comparator. |
| Python keeps evolving during the port | Freeze new Python features while Phase 1 runs; port any bug fix as a fixture first. |
| Future FileMaker versions change the clipboard format | Phase 0 checks 22/26/DEV; the pasteboard code is isolated in `FMClipboard`. |
| Hotkey conflicts with other apps | KeyboardShortcuts warns about conflicts; shortcut is configurable. |
| Production scripts leak into the public repo | D14: gitignore, pre-commit hook, CI check; private fixtures live outside the repo. |
| Sensitive content in persisted history | "Keep history after quitting" toggle, Clear history, local file only. |
| Signing/notarization needs an Apple Developer account | Open question Q1. |

---

## 12. Related tasks in the Python repo

- Correct the `fmclip.py` module docstring and README: FileMaker is not
  required; XMSS is raw XML under a four-char pasteboard type.
- Deferred (Q8): licence and production-script clean-up of the Python repo.
  Left as is for now.
- Optionally replace the AppleScript path with a PyObjC `NSPasteboard` write.

---

## 13. Open questions and decisions log

**Open**

- None blocking Phases 0–3.

**Decided (2026-10-07)**

- Rewrite in Swift rather than bundle Python (D1).
- Failed runs count toward the history limit (D5).
- Inspector is editable (D6).
- "Did you mean" ships in v1 (D7).
- Q1 → EMBO's Apple Developer account signs the app (D10).
- Q2 → Distributed via GitHub Releases (D10).
- Q3 → Python implementation freezes after parity (D13).
- The project is fully open source under GPL-3.0-or-later (D12, was Q4).
- Q5 → Hosted on the personal account: `github.com/ariera/fmscript2xml-app` (D12).
- Production scripts are never committed; local testing only (D14).
- Q6 → Releases are signed and notarised locally on Alejandro's Mac with
  EMBO's Developer ID; no signing secrets in GitHub.
- Q8 → The Python repo is left as is for now.
- Q7 → Contributors notice with author credit (D16).
- App name FM Script Paste (D15); tooling defaults (D17, D18).
- Implementation runs through Phase 3, pushing directly to `main` of a public
  repo (§14).

---

## 14. Implementation brief (for the implementing agent)

**Scope: Phases 0 → 3**, then stop and report. Phases 4–6 are out of scope
for this run.

**Repository and git**

- Create the **public** repo `ariera/fmscript2xml-app` with
  `gh repo create ariera/fmscript2xml-app --public --source . --push`.
- Push directly to `main`; no branches or PRs needed. Small, focused commits
  with clear messages.
- The repo is public from the first push, so **the very first commit** must
  contain the planning files plus the D14 safeguards: `.gitignore` entries,
  the pre-commit hook (installed via `git config core.hooksPath .githooks`)
  and the CI check. Before every push, check that nothing under
  `Tests/Fixtures/` outside `public/`, and no production script content, is
  staged.
- CI: GitHub Actions on `macos-latest` running `swift build` and `swift test`
  (public fixtures only) plus the fixture-location check.

**Working rules**

- The Python reference is at `~/dev/EMBO/fmscript2xml`. Read it; don't modify
  it (Q8).
- Private fixtures: `export FMSCRIPT_PRIVATE_FIXTURES=~/dev/EMBO/fmscript2xml/tests/fixtures/real_world`.
- Tick checklist items in this plan as they land, and append findings to the
  decisions log (§13).
- Dev builds are ad-hoc signed. Developer ID signing and notarisation are
  Phase 6 and done by Alejandro locally.

**Steps that need Alejandro**

- Phase 0 paste tests in FileMaker Pro 22/26/DEV: prepare a one-command spike
  (`swift run spike-paste <file.xml> [--with-text]`) and ask Alejandro to
  paste and report.
- Phase 3: before testing the hotkey, Alejandro disables the Automator
  Quick Action's ⌃⌥⌘F shortcut (System Settings → Keyboard → Keyboard
  Shortcuts → Services) so the two don't collide.
- First launch prompts (notifications, login item) are approved by Alejandro.

**Done when**

- Phase 1 exit: all public fixtures pass in CI; all 885 private fixtures pass
  locally; differential run against Python shows no semantic differences.
- Phase 2 exit: complete source maps for every fixture; suggestions tested.
- Phase 3 exit: FM Script Paste runs from the menu bar, ⌃⌥⌘F converts the
  clipboard, failures notify with the error and leave the clipboard alone,
  Settings work. Report what was verified, what Alejandro still needs to try
  in FileMaker, and any deviations from this plan.
