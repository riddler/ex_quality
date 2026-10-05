<p align="center">
  <img src="assets/ex_quality.svg" alt="" width="128" height="128">
</p>

<p align="center">
  <a href="https://hex.pm/packages/ex_quality"><img src="https://img.shields.io/hexpm/v/ex_quality.svg" alt="Hex version"></a>
  <a href="https://hex.pm/packages/ex_quality"><img src="https://img.shields.io/hexpm/dt/ex_quality.svg" alt="Hex downloads"></a>
  <a href="https://hexdocs.pm/ex_quality/"><img src="https://img.shields.io/badge/hex-docs-lightgreen.svg" alt="Hex docs"></a>
  <a href="https://hex.pm/packages/ex_quality"><img src="https://img.shields.io/hexpm/l/ex_quality.svg" alt="License"></a>
</p>

# ExQuality

ExQuality is one command, `mix quality`, that runs an Elixir project's quality
tools in parallel and reports the whole gate in one shape. Each tool is one
stage with a status, a one-line summary, and findings that carry a
`file:line`, and the same results can be written as a JSON report for a script
to route on.

## Why: the output is the point

Every quality tool prints in its own format, at its own length, and says
nothing when it did not run, so reading a gate made of several tools means
reading several walls of text and inferring what is missing from them, and a
script that wants to act on a failure has to parse each tool its own way. With
ExQuality the gate is one run, one stream and one shape per stage: a passing
stage costs one line, a skipped stage says why it was skipped, and a failure
points at the `file:line` to fix.

## What a run looks like

![A mix quality run: green passing stages, dim skipped stages, and a red failing stage with its finding printed below](https://raw.githubusercontent.com/riddler/ex_quality/main/assets/example-output.svg)

Colour is a second channel over the `✓`, `○` and `✗`, never a replacement for
one. It is dropped when the output is not a terminal, so a CI log or a piped run
reads exactly the same minus the paint.

Three properties follow from that, and they are what the tool is for:

- **A passing stage costs one line.** Detail is printed for failures only. A
  green run is one line per stage, not one report per tool.
- **Every stage the run considered is reported**, skipped ones included, with
  the reason. Absence is never something a reader has to interpret, and a stage
  that silently did not run cannot read as a stage that passed.
- **A failure is rendered as findings**: each one a `file:line`, a message and
  the rule that produced it, grouped by file. Anything a parser could not
  account for is printed verbatim rather than dropped.

Do not pipe a run through `head`, `tail` or `grep`. The output is already the
minimum needed to act, and truncating it removes findings, not noise. If you
want to route on a result rather than read it, ask for
[a JSON report](docs/reports.md).

## Installation

```elixir
def deps do
  [{:ex_quality, "~> 0.15", only: :dev, runtime: false}]
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

## Basic usage

```bash
mix quality --test-scope changed     # between edits: only the tests covering changed code
mix quality --quick                  # while coding: drops Dialyzer and the coverage threshold
mix quality                          # before committing, and in CI: the full gate
mix quality --report .quality.json   # the full gate, plus a JSON report to route on
```

A stage is enabled when the project depends on the tool behind it, so there is
nothing to switch on for the common tools. `--quick` narrows *which checks
run*; `--test-scope` narrows *how much code they run over*. Neither measures
coverage, so neither is the full gate: run a bare `mix quality` for that. The
flags, profiles and test scope are in [Configuration](docs/configuration.md).

## Working with a coding agent

ExQuality ships a [`usage-rules.md`](usage-rules.md) for AI coding assistants,
readable by [usage_rules](https://hex.pm/packages/usage_rules). It tells an
agent which command to run for which situation, how to read a failure, not to
truncate the output, and which fixes are never acceptable - lowering a coverage
threshold, adding a `.sobelow-conf` ignore - because a tool silencing its own
findings is a regression dressed as a pass.

Two things make an agent loop cheap, and they pull in opposite directions. The
output properties above are one: a passing run costs a line per stage of context
instead of several tool reports, and a failing one gives `file:line` targets
without a second command. The other is that the run has to be quick enough to be
worth repeating. An aggregate command that always runs the full suite is one an
agent will either invoke and pay for, or quietly stop invoking - both worse than
the individual test runs it would have reached for otherwise. `--test-scope
changed` is the answer to that, and `scope` in the report is how the full gate
stays distinguishable from it.

## Documentation

- Do
  - [How to run the gate in CI and before each commit](docs/ci.md) - a pipeline step, attesting a full run, a warm Dialyzer PLT, a container image and a pre-commit hook
  - [Routing on a report](docs/reports.md#routing-on-a-report) - reading which stages failed and their findings from a script, a section of the Reports reference until its guide page exists
- Look up
  - [Configuration](docs/configuration.md) - the CLI flags, the `.quality.exs` keys, test scope, profiles, custom stages and precedence
  - [Stages](docs/stages.md) - what each stage runs, when it is enabled, what it reports and where its threshold comes from
  - [Reports](docs/reports.md) - the JSON report's fields: the top level, each stage and each finding
  - [Umbrella projects](docs/umbrella.md) - how detection, findings, tests, coverage and Sobelow behave at an umbrella root
  - [Usage rules](usage-rules.md) - the rules a coding agent reads: which command for which situation and which fixes are never acceptable
  - [Changelog](CHANGELOG.md) - what changed in each version, and how to enable each new stage

## Compatibility

- Elixir `~> 1.14`.
- One runtime dependency, `jason ~> 1.4`. ExQuality itself is a dev-only
  dependency (`only: :dev, runtime: false`).
- The tools it runs are the project's own dependencies, at the versions the
  project pins; a stage is reported as skipped when its tool is not installed.

## License

MIT

## Contributing

Issues and pull requests welcome at
[github.com/riddler/ex_quality](https://github.com/riddler/ex_quality).
