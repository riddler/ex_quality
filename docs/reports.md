# Reports

The exit code says a run failed, not what failed. A caller that wants to route
on the result asks for a report rather than scraping the console or re-running
the tool.

```bash
mix quality --report .quality.json   # human output on stdout, report to a file
mix quality --format json            # report on stdout, human output on stderr
mix quality --report -               # the same, spelled the way a pipe reads
```

Both of the first two can be given at once. `--report PATH` is usually the more
useful, because it leaves the human stream intact. `--report -` is `--format
json` under another name: the report takes stdout and the human output moves to
stderr, rather than the two being interleaved into something nothing can parse.

The report is built from the same results the human output is rendered from, so
the two can never disagree.

## Top level

```json
{
  "status": "error",
  "version": "0.6.0",
  "duration_ms": 5014,
  "profile": "loop",
  "scope": "changed",
  "base_ref": "origin/main",
  "stages": []
}
```

| Field | Type | Notes |
|---|---|---|
| `status` | `"ok"` \| `"error"` | `"error"` if any stage failed |
| `version` | string | the ExQuality version that produced the report |
| `duration_ms` | integer | wall clock time of the whole run, which is **not** the sum of the stage durations, because the analysis stages run in parallel |
| `profile` | string \| null | the `--profile` the run used |
| `scope` | string | how much of the suite ran: `"all"`, `"changed"`, or the glob |
| `base_ref` | string \| null | what `"changed"` was measured against |
| `stages` | array | every stage the run considered, in the order it reported them |

`status` alone does not say what a run is evidence for. A green run scoped to
three test files and a green full run are different claims, so **anything that
ratchets a recorded number, moves a baseline, or gates a merge has to check
`scope` and refuse to move on anything but `"all"`.** That is what the field is
for.

`scope` is the scope the run *achieved*. A `:changed` run that resolved to no
test files ran the whole suite, so it reports `"all"` and puts the request on the
Tests stage as `requested_scope` with a `fallback_reason` beside it. A caller
checking `scope == "all"` never has to reason about fallbacks.

## Stage

```json
{
  "name": "Dependencies",
  "status": "error",
  "summary": "1 vulnerability (1 moderate)",
  "stats": {"vulnerabilities": 1, "vulnerabilities_by_severity": {"moderate": 1}},
  "findings": [],
  "duration_ms": 2400
}
```

| Field | Type | Notes |
|---|---|---|
| `name` | string | `Format`, `Compile`, `Credo`, `Dialyzer`, `Dependencies`, `Doctor`, `Docs`, `Gettext`, `Sobelow`, `Tests`, or a custom stage's own name |
| `status` | `"ok"` \| `"error"` \| `"skipped"` | |
| `summary` | string | the same one-line summary the console prints; for a skipped stage, the reason |
| `skip_kind` | `"run"` \| `"project"` \| null | which kind of skip this is; `null` unless the stage was skipped |
| `stats` | object | stage-specific counts, `{}` when the stage has none |
| `findings` | array | parsed problems; empty when there are none, or when the stage could not parse its output |
| `duration_ms` | integer | `0` for a skipped stage |
| `output` | string | present only on a failure with no findings |

Every stage carries the same keys whatever its status, so a consumer reads one
field for the explanation rather than branching. A skipped stage puts its
reason in `summary`:

```json
{
  "name": "Dialyzer",
  "status": "skipped",
  "summary": "--quick",
  "skip_kind": "run",
  "stats": {},
  "findings": [],
  "duration_ms": 0
}
```

Reasons are the flag (`--quick`, `--skip-credo`, `--skip <key>`), the missing
package (`:gettext not installed`), `disabled in .quality.exs`, `compile
failed`, or - for a custom command declaring `skip_exit_code` - whatever the
command itself said.

`skip_kind` says which of two things the skip means, structurally, so a
consumer never parses the reason's prose. `"run"` means the caller asked for a
narrower run - `--quick`, a `--skip`, a profile, `--until-first-failure`,
`compile failed` - and a full `mix quality` closes the gap. `"project"` means
the project does not check this at all - the tool is not installed, the stage
is disabled in `.quality.exs` - and a fuller run cannot close it. A skipped
stage that declared no kind (a custom stage that has not opted in - see
`ExQuality.Stage.skipped/3`) reports `"project"`, so an unlabelled skip fails
to attest as a gap rather than passing as a narrowing. `mix quality.verify`
routes on this field; see [ci.md](ci.md#attesting-a-full-run).

**Every stage the run considered appears**, skipped ones included, so absence is
never something a caller has to interpret.

## The Tests stage

The Tests stage carries what it ran as well as what it found, because a test
count says nothing about how much of the suite produced it:

```json
{
  "name": "Tests",
  "status": "ok",
  "summary": "12 of 12 passed (scope changed, 3 files vs origin/main, no coverage)",
  "scope": "changed",
  "files": 3,
  "test_files": [
    "test/user_test.exs",
    "test/user/email_test.exs",
    "test/accounts_test.exs"
  ],
  "base_ref": "origin/main",
  "coverage": "skipped",
  "coverage_reason": "not measured on a scoped run",
  "stats": {"test_count": 12, "passed_count": 12, "failed_count": 0},
  "findings": [],
  "duration_ms": 2800
}
```

| Field | Type | Notes |
|---|---|---|
| `scope` | string | always present, `"all"` for a full run |
| `files` | integer | how many test files ran; absent on a full run |
| `test_files` | array | which ones; absent on a full run |
| `base_ref` | string | absent unless a diff was taken |
| `coverage` | `"skipped"` | present only on a scoped run, where coverage is **absent rather than lower** |
| `coverage_reason` | string | why it was not measured |
| `requested_scope` | string | present only when the run fell back to the full suite |
| `fallback_reason` | string | why it fell back, e.g. `no test files map to the changed files` |

A scoped run never reports a coverage percentage in `stats`. See
[Test scope](configuration.md#test-scope).

## Custom stages

A project's custom stages appear in `stages[]` like any other, so **`name` is
not one of a fixed nine** and a consumer must not switch on it exhaustively.
Route on `status` and `findings`, and treat `name` as a label.

A custom stage's `stats` are whatever its command reported, so the keys are its
own rather than drawn from the built-in set. See
[configuration.md](configuration.md#custom-stages).

## Finding

```json
{
  "file": "lib/user.ex",
  "line": 42,
  "column": 3,
  "app": "web",
  "severity": "info",
  "check": "Credo.Check.Readability.ModuleDoc",
  "message": "Modules should have a @moduledoc tag."
}
```

| Field | Type | Notes |
|---|---|---|
| `file` | string | the file the problem is in |
| `line` | integer \| null | `null` when the tool reported none |
| `column` | integer \| null | `null` when the tool reported none |
| `app` | string \| null | the umbrella app the file belongs to, when known |
| `severity` | `"error"` \| `"warning"` \| `"info"` | |
| `check` | string \| null | the tool's rule identifier: a check module, a warning name, an advisory ID |
| `message` | string | the problem |

## Findings and `output`

`findings` is the parsed form; `output` is the fallback. For a failure, one of
the two is always present.

A stage whose parser did not account for its tool's output carries that output
verbatim under `output` instead of dropping it. Findings never replace output
they did not account for, so a parser being wrong about a format degrades into
"shows the original lines" rather than silently hiding a real problem.

## Routing on a report

Read the report rather than re-running a tool to find out what broke.

```elixir
report = "quality.json" |> File.read!() |> Jason.decode!()

for stage <- report["stages"], stage["status"] == "error" do
  case stage["findings"] do
    [] -> {stage["name"], {:output, stage["output"]}}
    findings -> {stage["name"], {:findings, findings}}
  end
end
```
