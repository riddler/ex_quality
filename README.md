<p align="center">
  <img src="assets/ex_quality.svg" alt="" width="128" height="128">
</p>

# ExQuality

Runs an Elixir project's quality tools in parallel and reports the run as one
stage per tool, each with a status, a one-line summary, and findings that carry
a `file:line`.

```
mix quality
```

## The output is the point

Every quality tool prints in its own format, at its own length, and says
nothing when it did not run. Reading a run means reading several walls of
text and inferring what is missing from them.

ExQuality normalises that. One run, one stream, one shape per stage:

```
Running quality checks...

✓ Format: No changes needed (458ms)
✓ Compile: dev + test compiled (warnings as errors) (325ms)

Running analysis stages in parallel...

○ Dialyzer: skipped (--quick)
○ Gettext: skipped (:gettext not installed)
○ Sobelow: skipped (:sobelow not installed)
✓ Doctor: Passed (519ms)
✓ Credo: No issues (775ms)
✗ Dependencies: 1 vulnerability (1 moderate) (2.5s)
✓ Tests: 345 of 345 passed (4.1s)

────────────────────────────────────────────────────────────
Dependencies - FAILED
────────────────────────────────────────────────────────────
mix.lock
  -  [error] decimal 2.3.0: Unbounded exponent in `Decimal.new` enables
     unauthenticated DoS (moderate severity, patched in 3.0.0) (GHSA-rhv4-8758-jx7v)
```

Three properties follow from that, and they are what the tool is for:

- **A passing stage costs one line.** Detail is printed for failures only. A
  green run is nine lines, not nine tool reports.
- **Every stage the run considered is reported**, skipped ones included, with
  the reason. Absence is never something a reader has to interpret, and a stage
  that silently did not run cannot read as a stage that passed.
- **A failure is rendered as findings**: each one a `file:line`, a message and
  the rule that produced it, grouped by file. Anything a parser could not
  account for is printed verbatim rather than dropped.

Do not pipe a run through `head`, `tail` or `grep`. The output is already the
minimum needed to act, and truncating it removes findings, not noise. If you
want to route on a result rather than read it, ask for
[a JSON report](#machine-readable-reports).

## Installation

```elixir
def deps do
  [{:ex_quality, "~> 0.12", only: :dev, runtime: false}]
end
```

Then set up the tools you want to run:

```bash
mix deps.get
mix quality.init              # interactive; pre-selects credo, dialyzer, excoveralls
mix quality.init --skip-prompts
```

`mix quality.init` detects what is already installed, adds the rest to
`mix.exs`, runs `mix deps.get`, writes each tool's config, and creates a
`.quality.exs`. Nothing about it is required: ExQuality runs whatever the
project already depends on.

## Three modes

```bash
mix quality --test-scope changed   # between edits
mix quality --quick                # while coding
mix quality                        # before committing, and in CI
```

Full mode runs every enabled stage. Quick mode drops Dialyzer and the coverage
threshold, the two slow stages - but it still runs every test, and on a large
suite the tests are most of the wall clock. That is the difference between the
first two lines above: `--quick` narrows *which checks run*, and `--test-scope`
narrows *how much code they run over*, which is the expensive question.

`--test-scope changed` runs only the test files covering the code you have
changed, committed or not. Two rules keep the result readable:

- **A scope that resolves to no test files runs the whole suite.** A green run of
  nothing is worse than a slow one, because it fails in the safe-looking
  direction.
- **Coverage is reported as skipped, never as a number.** A percentage over a
  subset of the suite is not a smaller truth, it is a different one.

A project can name a bundle of settings in `.quality.exs`, so its docs and its
agents point at one word instead of a flag list:

```elixir
profiles: [loop: [stages: [:format, :compile, :credo], test: [scope: :changed]]]
```

```bash
mix quality --profile loop            # the bundle above
mix quality --until-first-failure     # stop at the first thing to fix
```

See [Configuration](https://hexdocs.pm/ex_quality/configuration.html#test-scope).

## Stages

A stage is enabled when the project depends on the tool behind it. There is
nothing to switch on.

| Stage | Runs | Enabled when |
|---|---|---|
| Format | `mix format` | a `.formatter.exs` exists |
| Compile | `mix compile --warnings-as-errors`, dev and test | always |
| Credo | `mix credo --format json` | `:credo` |
| Dialyzer | `mix dialyzer --format short --format dialyxir` | `:dialyxir` |
| Dependencies | `mix deps.unlock --check-unused`, `mix deps.audit --format json` | always; audit needs `:mix_audit` |
| Doctor | `mix doctor` | `:doctor` |
| Gettext | reads the `.po` files | `:gettext` |
| Sobelow | `mix sobelow` | `:sobelow` |
| Tests | `mix test` | always |
| Coverage | `mix coveralls`, or `mix test --cover` | `:excoveralls`, or a threshold in `test_coverage` |

Format runs first and fixes what it can. Compile runs next and gates the rest:
there is no point analysing code that does not build. Everything after that
runs in parallel and prints as it finishes, so a 0.5s stage is not held behind
a 30s one.

Umbrella projects are first-class: tools are detected across every child app,
findings are tagged with the app they came from, and coverage is aggregated
across the suite. See [Umbrella projects](https://hexdocs.pm/ex_quality/umbrella.html).

## Machine-readable reports

The exit code says a run failed, not what failed. A script that wants to route
on the result - hand the Credo findings to one fixer, the test failures to
another - asks for a report instead of scraping the console:

```bash
mix quality --report .quality.json   # human output on stdout, report to a file
mix quality --format json            # report on stdout, human output on stderr
mix quality --report -               # the same, spelled the way a pipe reads
```

```json
{
  "status": "error",
  "version": "0.6.0",
  "duration_ms": 5014,
  "profile": null,
  "scope": "all",
  "base_ref": null,
  "stages": [
    {
      "name": "Dialyzer",
      "status": "skipped",
      "summary": "--quick",
      "stats": {},
      "findings": [],
      "duration_ms": 0
    },
    {
      "name": "Dependencies",
      "status": "error",
      "summary": "1 vulnerability (1 moderate)",
      "stats": {"vulnerabilities": 1, "vulnerabilities_by_severity": {"moderate": 1}},
      "findings": [
        {
          "file": "mix.lock", "line": null, "column": null,
          "app": null, "severity": "error",
          "check": "GHSA-rhv4-8758-jx7v",
          "message": "decimal 2.3.0: Unbounded exponent in `Decimal.new` enables unauthenticated DoS (moderate severity, patched in 3.0.0)"
        }
      ],
      "duration_ms": 2400
    }
  ]
}
```

Every stage carries the same keys whatever its status, so a consumer reads one
field rather than branching. The report is built from the same results the
human output is rendered from, so the two can never disagree.

`scope` says how much of the suite the run covered, and is what lets anything
that ratchets a number, moves a baseline or gates a merge refuse to move on a
narrow run: a green run over three test files and a green full run are different
claims. Full schema in [Reports](https://hexdocs.pm/ex_quality/reports.html).

## Working with a coding agent

ExQuality ships a [`usage-rules.md`](https://hexdocs.pm/ex_quality/usage-rules.html) for AI coding assistants,
readable by [usage_rules](https://hex.pm/packages/usage_rules). It tells an
agent which command to run for which situation, how to read a failure, not to
truncate the output, and which fixes are never acceptable - lowering a coverage
threshold, adding a `.sobelow-conf` ignore - because a tool silencing its own
findings is a regression dressed as a pass.

Two things make an agent loop cheap, and they pull in opposite directions. The
output properties above are one: a passing run costs nine lines of context
instead of several tool reports, and a failing one gives `file:line` targets
without a second command. The other is that the run has to be quick enough to be
worth repeating. An aggregate command that always runs the full suite is one an
agent will either invoke and pay for, or quietly stop invoking - both worse than
the individual test runs it would have reached for otherwise. `--test-scope
changed` is the answer to that, and `scope` in the report is how the full gate
stays distinguishable from it.

## Documentation

- [Configuration](https://hexdocs.pm/ex_quality/configuration.html) - `.quality.exs`, CLI flags, precedence
- [Stages](https://hexdocs.pm/ex_quality/stages.html) - what each stage runs, reports, and how thresholds are sourced
- [Reports](https://hexdocs.pm/ex_quality/reports.html) - the JSON report schema
- [Umbrella projects](https://hexdocs.pm/ex_quality/umbrella.html) - detection, findings, coverage, Sobelow
- [CI and pre-commit](https://hexdocs.pm/ex_quality/ci.html) - pipelines, PLT caching, hooks

## License

MIT

## Contributing

Issues and pull requests welcome at
[github.com/riddler/ex_quality](https://github.com/riddler/ex_quality).
