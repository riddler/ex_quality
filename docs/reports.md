# Reports

The exit code says a run failed, not what failed. A caller that wants to route
on the result asks for a report rather than scraping the console or re-running
the tool.

```bash
mix quality --report .quality.json   # human output on stdout, report to a file
mix quality --format json            # report on stdout, human output on stderr
```

Both can be given at once. `--report` is usually the more useful of the two,
because it leaves the human stream intact.

The report is built from the same results the human output is rendered from, so
the two can never disagree.

## Top level

```json
{
  "status": "error",
  "version": "0.6.0",
  "duration_ms": 5014,
  "stages": []
}
```

| Field | Type | Notes |
|---|---|---|
| `status` | `"ok"` \| `"error"` | `"error"` if any stage failed |
| `version` | string | the ExQuality version that produced the report |
| `duration_ms` | integer | wall clock time of the whole run, which is **not** the sum of the stage durations, because the analysis stages run in parallel |
| `stages` | array | every stage the run considered, in the order it reported them |

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
| `name` | string | `Format`, `Compile`, `Credo`, `Dialyzer`, `Dependencies`, `Doctor`, `Gettext`, `Sobelow`, `Tests`, or a custom stage's own name |
| `status` | `"ok"` \| `"error"` \| `"skipped"` | |
| `summary` | string | the same one-line summary the console prints; for a skipped stage, the reason |
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
  "stats": {},
  "findings": [],
  "duration_ms": 0
}
```

Reasons are the flag (`--quick`, `--skip-credo`, `--skip <key>`), the missing
package (`:gettext not installed`), `disabled in .quality.exs`, `compile
failed`, or - for a custom command declaring `skip_exit_code` - whatever the
command itself said.

**Every stage the run considered appears**, skipped ones included, so absence is
never something a caller has to interpret.

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
