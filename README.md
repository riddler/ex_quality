# ExQuality

Runs an Elixir project's quality tools in parallel and reports the run as a
fixed set of stages, each with a status, a one-line summary, and findings that
carry a `file:line`.

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
  [{:ex_quality, "~> 0.6", only: :dev, runtime: false}]
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

## Two modes

```bash
mix quality --quick    # while coding
mix quality            # before committing, and in CI
```

Quick mode skips Dialyzer and coverage enforcement, the two slow stages. Tests
still run, and everything else is unchanged. Full mode runs every enabled
stage.

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
| Gettext | `mix gettext.extract --merge`, then reads the `.po` files | `:gettext` |
| Sobelow | `mix sobelow` | `:sobelow` |
| Tests | `mix test` | always |
| Coverage | `mix coveralls`, or `mix test --cover` | `:excoveralls`, or a threshold in `test_coverage` |

Format runs first and fixes what it can. Compile runs next and gates the rest:
there is no point analysing code that does not build. Everything after that
runs in parallel and prints as it finishes, so a 0.5s stage is not held behind
a 30s one.

Umbrella projects are first-class: tools are detected across every child app,
findings are tagged with the app they came from, and coverage is aggregated
across the suite. See [docs/umbrella.md](docs/umbrella.md).

## Machine-readable reports

The exit code says a run failed, not what failed. A script that wants to route
on the result - hand the Credo findings to one fixer, the test failures to
another - asks for a report instead of scraping the console:

```bash
mix quality --report .quality.json   # human output on stdout, report to a file
mix quality --format json            # report on stdout, human output on stderr
```

```json
{
  "status": "error",
  "version": "0.6.0",
  "duration_ms": 5014,
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
human output is rendered from, so the two can never disagree. Full schema in
[docs/reports.md](docs/reports.md).

## Working with a coding agent

ExQuality ships a [`usage-rules.md`](usage-rules.md) for AI coding assistants,
readable by [usage_rules](https://hex.pm/packages/usage_rules). It tells an
agent which mode to run, how to read a failure, not to truncate the output, and
which fixes are never acceptable - lowering a coverage threshold, adding a
`.sobelow-conf` ignore - because a tool silencing its own findings is a
regression dressed as a pass.

The properties above are what make an agent loop cheap: a passing run costs an
agent nine lines of context instead of several tool reports, and a failing one
gives it `file:line` targets without a second command.

## Documentation

- [Configuration](docs/configuration.md) - `.quality.exs`, CLI flags, precedence
- [Stages](docs/stages.md) - what each stage runs, reports, and how thresholds are sourced
- [Reports](docs/reports.md) - the JSON report schema
- [Umbrella projects](docs/umbrella.md) - detection, findings, coverage, Sobelow
- [CI and pre-commit](docs/ci.md) - pipelines, PLT caching, hooks

## License

MIT

## Contributing

Issues and pull requests welcome at
[github.com/riddler/ex_quality](https://github.com/riddler/ex_quality).
