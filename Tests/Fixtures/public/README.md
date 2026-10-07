# Public fixtures

Each folder holds an `input.txt` (plain-text script steps) and the
`expected.xml` it must convert to. All content is synthetic: no production
table, field, layout or script names (PLAN.md D14).

Two kinds:

- **FileMaker-verified** (`expected.xml` copied from FileMaker, compared
  semantically): BracketInStringLiteral, CalculationComments, CloseWindow,
  CommitRecordsRequests, GoToRecord, GoToRelatedRecord, PauseResumeScript,
  PerformScriptOnServer, PerformScriptOnServerWithCallback, PrintSetup,
  SaveRecordAsPdf, SetField, ShowCustomDialog, SortRecordsByField. These come
  from the Python repo's `tests/fixtures/simple/`, with names replaced.
- **Regression fixtures** (`expected.xml` written by the reference
  implementation with `tools/new-fixture.sh`, compared byte for byte): all
  others. They pin down current behaviour, quirks included, across every
  handler and parser edge case.

To turn a bug report into a fixture, reproduce it with neutral names and run:

```sh
tools/new-fixture.sh MyCase path/to/input.txt
```

Production scripts never go here. Run them locally from outside the repo with
`FMSCRIPT_PRIVATE_FIXTURES=/path/to/fixtures swift test`.
