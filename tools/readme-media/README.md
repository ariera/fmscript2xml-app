# README media

- `workflow.gif` is an illustration, not a screen recording. Regenerate it
  with `swift tools/readme-media/make-workflow-gif.swift`. The script it shows
  is `demo-script.txt`.
- `inspector.png`, `settings.png` and `about.png` are captures of a Debug build
  filled with synthetic scripts. Debug builds accept `-FMSPDebugChannel`,
  `-FMSPPasteboardName`, `-FMSPSourceApp` and `-FMSPSuppressNotifications`, and
  listen for `io.github.ariera.fmscriptpaste.debug.<channel>.<hook>` distributed
  notifications (`convert`, `inspector`, `snapshotInspector`,
  `snapshotSettings`, `snapshotAbout`); see `App/Sources/FMScriptPasteApp.swift`.

All content must be synthetic: no production scripts or names (PLAN.md D14).
