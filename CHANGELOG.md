# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- **Dialyzer could report `✓ No warnings` on a project with 110 real warnings.** The Gettext stage ran `mix gettext.extract --merge`, which recompiles the project, alongside the analysis stages that read the same build. Dialyzer, invoked with `--no-compile`, hit `Could not get Core Erlang code` and produced nothing, and the debug_info escape hatch promoted that to a pass
- Dialyzer now separates "ran and found nothing" from "never ran" by whether dialyxir printed its own `Total errors:` tally, and reports the second as a failure (`Analysis did not complete (build changed under it? see output)`) rather than a pass
- The Gettext stage found no `.po` files in an umbrella and reported `All translations complete` having read nothing. It now looks under every child app as well as the root, and reports `:skipped` with the reason when it examined no files
- The Gettext stage rejected every path containing `/en/` and every `errors.po` invisibly, so a project whose only locale was `en` had every file filtered out and still went green
- Dialyzer findings in an umbrella carried `app: null` and an app-relative `file` that did not open from the umbrella root. Each path is now resolved against the child apps by existence; an ambiguous path is left alone rather than guessed at
- A failing test suite came back with no findings and the whole run log in `output`. Each ExUnit failure is now parsed into a finding with `file`, `line`, `app`, the test module and the assertion message

### Changed

- **The Gettext stage no longer writes to your repository.** `mix gettext.extract --merge` rewrote `.pot`/`.po` files and left the dev build inconsistent enough that the next `mix compile --warnings-as-errors` failed. It is now opt-in with `gettext: [extract: true]`, and the stage reads the committed files as they stand
- Gettext reports `%ExQuality.Finding{}` structs with app attribution rather than a hand-built prose string, so its failures route like every other stage's
- Gettext's source locale is configurable (`gettext: [source_locale: "en"]`), as is the excluded basename list (`gettext: [exclude: ["errors.po"]]`)

### Added

- **Mix alias detection.** ExQuality shells out to the real `mix credo`, `mix dialyzer`, `mix format`, `mix sobelow`, `mix deps.unlock` and `mix test.coverage`, and Mix resolves aliases before tasks. A project that aliases one of those names silently changed what the stage measured: `mix sobelow` ran the alias, ignored every switch and wrote no report; `mix test.coverage` ran the entire suite a second time before aggregating. Those stages now refuse to run and name the alias (`✗ Sobelow: mix sobelow is aliased in mix.exs`). `mix test` is the deliberate exception, since a `test:` alias does the setup the suite needs
- `ExQuality.Aliases`, with `shadowing?/1` and `shadowed/2`
- Stages declare whether they read the build or write to it (`stage_kind/1`, `ExQuality.Stage.kind/2`). Writers run serialized before the parallel readers, the way compilation already gates the run
- A project mark under `assets/`: an SVG with a transparent surround, so it reads on a light or a dark background, plus PNG renders from 512 down to 32. It is the README's header, and the published docs' logo and favicon. The assets are not shipped in the package: HexDocs is built from the checkout at publish time, so nothing downloading the dependency needs them

## [0.7.0] - 2026-08-01

### Added

- `ExQuality.Finding`, a structured representation of a single actionable problem (file, line, column, severity, check, message, and the raw tool output it came from)
- Stage results may carry `findings`; `ExQuality.Stage.findings/1` reads them
- Credo parses its issues into findings, and failure output renders them grouped by file and sorted by line
- Stages without a parser, and output that does not parse, still print in full: findings never replace output they did not account for
- Every stage that is considered and not run now prints a line saying so, with the reason (`○ Dialyzer: skipped (--quick)`, `○ Doctor: skipped (:doctor not installed)`, `○ Credo: skipped (disabled in .quality.exs)`)
- `ExQuality.Config.skip_reason/2` and `ExQuality.Stage.skipped/2`
- `ExQuality.Umbrella`, which answers which child apps exist, where they live, and what they declare
- Findings carry the umbrella app their file belongs to, and rendered output is grouped by app
- Test failures name the apps they came from (`3 of 4,180 failed (web: 3)`)
- `mix quality --report PATH` writes a JSON report of the run, and `--format json` puts it on stdout with the human output on stderr. A caller can route on which stage failed and on its findings instead of scraping the console or re-running the tool
- `ExQuality.Report`, which builds that report from the same results the human output is rendered from
- A Sobelow security stage, auto-enabled on `:sobelow`, with `--skip-sobelow` to turn it off. Findings at or above the project's `exit:` threshold block the run and are rendered; the rest are reported as a count (`2 blocking findings (1 high, 1 medium), 3 informational not shown`) and shown under `--verbose` or `sobelow: [show_informational: true]`
- The Sobelow stage runs once per Phoenix child app in an umbrella, where `mix sobelow` alone finds nothing to scan, and tags each finding with its app
- `ExQuality.Umbrella.app_deps/0`, the child dependencies keyed by app
- Coverage without ExCoveralls: a project that sets `test_coverage: [summary: [threshold: N]]` is measured with Elixir's own `mix test --cover`. In an umbrella the run exports per app and aggregates with `mix test.coverage`, so a module exercised by another app's tests no longer reads as 0%
- A failing coverage check reports the modules under the threshold as findings, with their source files, instead of the whole per-module table
- `test: [coverage: true | false]` in `.quality.exs`, to measure coverage in a project that states no threshold, or to never measure it
- `:native_coverage` in `ExQuality.Tools.detect/0`, true when `:excoveralls` is absent
- `mix quality.plt`, which builds the Dialyzer PLT outside a run so a container image or CI job can cache it instead of paying for it inside a check
- A run that has to build the PLT says so while it happens (`⋯ Dialyzer: building PLT (this is a one-time cost)`), instead of a multi-minute wait behind a stage that prints one line at the end, and reports it afterwards (`No warnings (PLT built this run)`, `stats.plt_built`)
- `ExQuality.Plt`, which recognises PLT work in dialyxir's output
- `ExQuality.OutputCollector.new/1` takes an `:on_line` handler, called with each line of a command's output as it arrives

- `ExQuality.Json`, which reads a JSON document out of output a compiler or a tool also wrote to

- Guides under `docs/`, shipped with the package and published with the docs: configuration, stages, reports, umbrella projects, and CI and pre-commit
- `ExQuality.Finding.relative_path/1`, which normalises a path a tool reported into one relative to the run's root

### Changed

- The README leads with the output contract - a passing stage costs one line, every stage the run considered is reported with its reason, a failure renders as findings with `file:line` - instead of a feature list, and the reference detail it carried moves into `docs/`. The comparison table is gone: it made unverifiable claims about other tools that would rot
- `usage-rules.md` is organised around what an agent has to decide: which command to run, what each line shape means, what to do about each stage's findings, and the fixes that are never acceptable. The anti-fixes are collected in one place rather than scattered, and cover skipping a failing test, adding a `--skip-*` flag and weakening a check, not just coverage and Sobelow thresholds
- The package description names the tools, the output and the audience, so it is findable by what someone would search for on Hex
- A passing run and `mix quality.init` end with `✓` rather than `✅`, matching the stage lines
- `:doctor` moves to `~> 0.23`, which requires `decimal ~> 3.1` and clears GHSA-rhv4-8758-jx7v, an unbounded exponent in `Decimal.new` that enables unauthenticated denial of service. `:jason` moves to 1.4.5, the first release whose optional `:decimal` requirement admits 3.x
- Dialyzer runs with `--format short --format dialyxir`. Each warning's one-line form becomes a finding naming the warning (`no_return`, `pattern_match`), and the warning count is the number of them instead of a count of lines shaped like `file.ex:12:`, which also counted PLT chatter and any explanation that named a second file. dialyxir's long explanation of each warning is still printed, so it stays in the stage's output and in the JSON report
- The security audit runs `mix deps.audit --format json`. Each vulnerability becomes a finding against the lockfile, naming the advisory, the version in use and the version that fixes it, instead of being counted by searching the human output for `Advisory:` and `severity: high`. Unused dependencies become findings too. `stats.high_severity` and its siblings are replaced by `stats.vulnerabilities_by_severity`
- Credo runs with `--format json`. Findings name the check that produced them (`Credo.Check.Readability.ModuleDoc`) instead of its category, the issue count is the number of issues rather than a summary-line parse, and an issue that credo reported is never dropped for having an unfamiliar line shape. A stage summary now reads `5 issues (2 readability, 3 design)`

### Fixed

- Findings report a path relative to the run's root. mix_audit reports an absolute lockfile, so a vulnerability rendered as `/Users/someone/code/app/mix.lock`: longer to read, not what a reader would type, different between a laptop and CI for the same problem, and comparing as a different finding. It is the same base `ExQuality.Umbrella.app_for_path/2` matches, so a finding's `file` and its `app` can no longer disagree about where it is. A path outside the project root stays absolute
- A run that stops at a compile error now reports the analysis stages it never reached as skipped, instead of saying nothing about them

- A disabled or uninstalled stage no longer vanishes from the output, where it read as a stage that passed
- Tool auto-detection reads every umbrella child app's dependencies, not just the root's. An umbrella root usually declares no deps, so credo, dialyzer and friends were reported as not installed and a run that checked almost nothing passed
- Test statistics sum every app's summary line instead of reporting the first app's numbers as the whole suite's
- Coverage reads every `[TOTAL]` line; when apps are measured separately the lowest leads, with the per-app numbers alongside it
- The coverage threshold is read from `coveralls.json`'s `coverage_options`, where excoveralls actually writes `minimum_coverage`. Only the top level was looked at, so a project configuring it the standard way had no threshold enforced
- An integer threshold (`minimum_coverage: 70`) no longer crashes the summary
- The Format stage reports a failing `mix format` instead of discarding its exit code. A file with a syntax error names no `.ex` file to count, so the first line of the run was a green tick on a broken file
- The Format stage reports a project with no `.formatter.exs` as skipped, rather than failing the run over a config file it never had
- `.quality.exs` is read from the project root instead of the working directory, and an umbrella child with no file of its own now reads the umbrella root's

## [0.6.0] - 2026-04-05

### Fixed

- Output full, non-truncated content when errors occur.

## [0.5.0] - 2026-02-23

### Changed

- Condensed `usage-rules.md` by removing first-time setup, auto-detection, and detailed configuration sections that aren't needed for day-to-day LLM usage

## [0.4.0] - 2026-02-23

### Fixed

- Include `:jason` as a runtime dependency instead of dev/test only, fixing compilation warnings in host projects
- Pass `--no-compile` to `mix dialyzer` to avoid race conditions with parallel analysis stages competing over `_build/dev`
- Mark tests using `File.cd!` as `async: false` to prevent intermittent compilation failures from global working directory changes

### Changed

- Updated `usage-rules.md` to instruct LLMs not to truncate `mix quality` output

## [0.3.0] - 2026-02-03

### Added

- **Test options pass-through**: Pass extra arguments to `mix test` or `mix coveralls`:
  - Via CLI using `--` separator: `mix quality --quick -- --only integration`
  - Via config file: `test: [args: ["--only", "integration"]]`
  - CLI args override config file args (no merge)
  - Supports any test flags: `--only`, `--include`, `--exclude`, `--seed`, etc.

## [0.2.0] - 2026-01-09

### Added

- **`mix quality.init`** now automatically configures ExCoveralls in `mix.exs` when coverage is selected:
  - Adds `test_coverage: [tool: ExCoveralls]` to project configuration
  - Adds `preferred_cli_env` settings for all coveralls commands
  - Smart detection prevents duplicate configuration
  - Properly indents to match existing project style

## [0.1.0] - 2026-01-09

### Added

- Initial release of ExQuality (formerly Quality)
- **Three-phase execution pipeline:**
  - Phase 1: Auto-fix (format)
  - Phase 2: Compilation (dev + test in parallel)
  - Phase 3: Parallel analysis with streaming output
- **Quality stages:**
  - Format: Auto-fixes code formatting with `mix format`
  - Compile: Compiles dev + test environments in parallel with warnings as errors
  - Credo: Static analysis with `--strict` mode (configurable)
  - Dialyzer: Type checking with graceful PLT handling
  - Doctor: Documentation coverage checking
  - Gettext: Translation completeness validation
  - Test: Test suite with optional coverage via excoveralls
- **Quick mode** (`--quick`):
  - Skips dialyzer (slow type checking)
  - Skips coverage enforcement (tests run, % not checked)
  - Perfect for rapid iteration during development
- **Auto-detection system:**
  - Automatically enables stages based on installed dependencies
  - No configuration needed for standard setups
- **Configuration system:**
  - 4-tier precedence: Defaults → Auto-detection → `.quality.exs` → CLI flags
  - Project-level customization via `.quality.exs`
  - Per-stage enable/disable controls
  - CLI flags for runtime overrides
- **Streaming output:**
  - Results display as each stage completes
  - No interleaving (serialized via `Quality.Printer`)
  - Fast stages provide immediate feedback
- **Actionable feedback:**
  - Full tool output preserved in failure details
  - File:line references for easy navigation
  - Works for both humans and LLM coding assistants
- **CLI options:**
  - `--quick` - Fast mode for iterative development
  - `--skip-dialyzer` - Skip Dialyzer type checking
  - `--skip-credo` - Skip Credo static analysis
  - `--skip-doctor` - Skip Doctor documentation checks
  - `--skip-gettext` - Skip Gettext translation checks
  - `--verbose` - Show full output even on success
- **Documentation:**
  - Comprehensive README with workflow examples
  - `usage-rules.md` for LLM integration
  - Example `.quality.exs` configuration file
- **Coverage threshold:**
  - Single source of truth (reads from coveralls config)
  - Respects `coveralls.json` or `mix.exs` settings
  - No duplicate configuration needed

### Technical Details

- Zero runtime dependencies
- Optional dev dependencies: credo, dialyxir, doctor, excoveralls, gettext
- Parallel execution using Elixir Tasks
- Agent-based output serialization (ExQuality.Printer)
- Collectable protocol for silent output capture (ExQuality.OutputCollector)
- Tool detection via dependency scanning (ExQuality.Tools)
- Deep-merge configuration system (ExQuality.Config)

### Philosophy

ExQuality is designed for rapid, iterative development with confidence:
1. Fast feedback loop with `--quick` mode
2. Comprehensive verification with full mode
3. Actionable output with file:line references
4. Zero configuration required (works out of the box)
5. Progressive enhancement (add tools as needed)

[Unreleased]: https://github.com/riddler/ex_quality/compare/v0.6.0...HEAD
[0.6.0]: https://github.com/riddler/ex_quality/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/riddler/ex_quality/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/riddler/ex_quality/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/riddler/ex_quality/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/riddler/ex_quality/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/riddler/ex_quality/releases/tag/v0.1.0
