# Changelog

## Converter 0.6.6

- **Go to Portal Row goes to the right row.** `First`, `Last`, `Next` and
  `Previous` became a calculation FileMaker commented out (`/*First*/`), and
  `Select` and `Exit after last` were lost. They now convert to FileMaker's
  own options; a row given by calculation stays a calculation.
- **Truncate Table keeps its table.** The table was dropped, so the pasted step
  emptied the *current* table. It now names the base table, and FileMaker
  picks it by name on paste. Careful: if no base table has that exact name,
  FileMaker silently uses the current table instead, so a named table now
  always gives a warning to check the pasted step.

## Converter 0.6.5

- **`With dialog: Off` is kept on every step.** Steps without their own
  converter (Delete All Records, Delete Record/Request, Truncate Table, Import
  and Export Records, Replace Field Contents and 20 more) wrote the option as
  an element FileMaker doesn't know, so the pasted step showed
  `With dialog: On`. They now write it as FileMaker does; checked in
  FileMaker on all 27 steps that have the option.

## Converter 0.6.4

- **Layouts shown with their table occurrence are picked by name.** FileMaker
  shows a selected layout as `“Customers” (Customers)`. Go to Layout and Go to
  Related Record (`Using layout:`) read that as a calculation, which isn't
  valid, so FileMaker commented the step out on paste. The table occurrence is
  now dropped and the layout is selected by name.

## Converter 0.6.3

- **`Perform Script [ Specified: By name ; … ]` calls the calculated
  script.** The calculation was used as a literal script name, so
  `Specified: By name ; $scriptName` called a script named “$scriptName”.
  It is now a calculated name, as is a name given as a variable
  (`Perform Script [ $scriptName ]`), matching Perform Script on Server.

## Converter 0.6.2

- **`Perform Script [ Calculated: … ]` keeps its calculation.** The script
  name calculation was dropped, leaving an empty `<Calculated>`, and
  `Calculated:` was reported as an unknown parameter. The calculated name now
  also comes before the parameter, as in FileMaker's XML.

## Converter 0.6.1

- **Names in curly quotes are unquoted.** `Perform Script [ “My Script” ]`,
  `Install OnTimer Script [ “My Script” ; … ]`, `Go to Layout [ “Customers” ]`
  and `Go to Related Record [ … ; Using layout: “Customers” ]` now pick the
  script or layout by name, as straight quotes already did. Before, the quotes
  ended up in the name (or Go to Layout turned it into an invalid
  calculation), so the pasted step pointed at nothing.
- **Perform Script can call a script in another file.** `Perform Script [
  Specified: From list ; “Script” from file: “File” ]` (and `File: "File"`)
  now pastes as a call to that script in that file: FileMaker matches the
  external data source and the script by name. Before, the file was dropped
  without a warning, so the step called a script with that name in the
  current file, and in the `from file:` form the script name was lost too.
  Perform Script on Server (with or without callback) still can't do this;
  it now gives a warning instead of dropping the file silently.
