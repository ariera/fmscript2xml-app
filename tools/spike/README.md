# Phase 0 paste spike

Puts an `fmxmlsnippet` file on the clipboard under its FileMaker flavor,
written natively with `NSPasteboard` (no AppleScript), so you can check that
FileMaker pastes it.

```sh
swift run spike-paste tools/spike/steps.xml               # XMSS only
swift run spike-paste tools/spike/steps.xml --with-text   # XMSS + plain text
swift run spike-paste tools/spike/script.xml              # XMSC (Scripts list)
swift run spike-paste tools/spike/custom-function.xml     # XMFN (Manage Custom Functions)
swift run spike-paste --read                              # inspect the clipboard
```

What to check, in FileMaker Pro 22, 26 and DEV:

1. `steps.xml`: paste into a script in the Script Workspace → three steps.
2. `steps.xml --with-text`: paste into the Script Workspace → still steps (not
   text); paste into TextEdit → the XML text.
3. `script.xml`: paste into the Scripts list of the Script Workspace → a new
   script.
4. `custom-function.xml`: paste into File → Manage → Custom Functions.
5. Copy some steps in FileMaker, then `swift run spike-paste --read` to see
   which pasteboard types FileMaker itself writes.
