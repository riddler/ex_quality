# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **`mix quality.verify` runs the gate and attests that what ran was the *full* gate.** A green run is not by itself evidence of a green gate: `--profile`, `--test-scope`, `--quick`, `--skip` and `--until-first-failure` all produce `"status": "ok"`, and each checks less. When an agent runs the gate unattended and reports "gate green", nobody observed the run, and the narrow one and the full one produce the same three words. The task runs `mix quality` in-process with the caller's flags, then attests over the report: every stage green, no profile, scope `all`, no quick mode, no stage skipped for a run-level reason, and coverage measured when the project measures it. It exits non-zero naming every failed condition at once. A stage skipped for a project-level reason (`:sobelow not installed`, `disabled in .quality.exs`) attests but is named in the output - "full gate green" and "here is what this project never checks" are two different facts, and the reader needs both. The attestation deliberately does not prove the gate is *strong*: a weakened `.quality.exs` attests honestly against the weakened gate, and the docs say so
- **Skipped stages carry a structural `skip_kind` in the report**: `"run"` when the skip names this run (`--quick`, a `--skip`, a profile, `--until-first-failure`, `compile failed`) and a full `mix quality` closes it, `"project"` when the project does not check this at all (tool not installed, disabled in `.quality.exs`) and a fuller run cannot close it, `null` when the stage was not skipped. The two kinds were previously distinguishable only by reading the reason's prose, which was never a contract - rephrasing a summary in a patch release would have silently turned a narrowed run into an attested one downstream. `ExQuality.Stage.skipped/3` takes the kind as an optional third argument; the default for an unlabelled skip is `:project`, the conservative direction, so a custom stage that has not opted in fails to attest as a gap rather than passing as a narrowing

## [0.13.0] - 2026-08-02

### Changed

- **Stage status lines carry colour**: green on a passing stage's tick and name, dim on a skipped line, and the failure line unchanged because it already rendered in red. Colour is a second channel over the `✓`/`✗`/`○`, never a replacement for it, so anything reading the output without a terminal still reads the status off the glyph. Both shells format through `IO.ANSI`, which drops the codes when stdout is not a terminal, so CI logs, piped runs and `--format json` are unchanged and there is no flag to turn it off
- The two identical renderers for stage results are now one. `ExQuality.Printer.print_result/1` prints straight to the shell when no printer agent is running, which is all the sequential format and compile phases needed from it, so `mix quality` no longer carries its own copy of the same three clauses

### Fixed

- **The guide links on the hex.pm package page reached the guides rather than their markdown source.** hex.pm renders the README from the tarball and resolves relative paths against it, and `docs/` ships in the package, so `docs/configuration.md` resolved to the file. The README links to HexDocs by absolute URL now. Links between the guides stay relative, which is what ExDoc resolves

## [0.12.0] - 2026-08-01

### Added

- **`test: [scope: :changed]`, or `--test-scope changed`, runs only the test files covering the code that changed.** Every flag this library had narrows *stages*, and the expensive question is how much *code*. Measured on a large umbrella that adopted it: across a run of agentic development `mix quality` averaged 61.7s, of which the suite was 68%, while the same agent could run a single test file in about 3s. `--quick` does not address that - it removes dialyzer and the coverage threshold and still runs every test, which against that split is 10% of the cost. Changed files are resolved against the merge base with the repository's default branch, including uncommitted and untracked work, because an agent mid-task has everything uncommitted and a diff that reads only committed history would report no changes on exactly the runs this exists for. `lib/foo/bar.ex` maps to `test/foo/bar_test.exs`, in an umbrella under the same app, and a changed test file is itself. `--test-scope` also takes `all` or a glob string, and `test: [base_ref: "origin/main"]` overrides what `:changed` is measured against
- **A scope that resolves to no test files runs the full suite.** This is the one failure mode that would make the feature worse than not having it, because it fails in the safe-looking direction: exit 0, `"status": "ok"`, nothing run. The report says which happened, carrying the achieved `scope` with `requested_scope` and `fallback_reason` beside it, so a caller checking `scope == "all"` never has to reason about fallbacks
- **Coverage on a scoped run is absent rather than lower.** It is reported as `"coverage": "skipped"` with a reason and never as a number: a percentage over a subset of the suite is not a smaller truth, it is a different and misleading one, and an adopting project that lowers a recorded figure on a green run would corrupt it against a run that never measured
- **Profiles.** `profiles:` in `.quality.exs` names bundles of options, selected with `mix quality --profile loop`, so the fast path has a name a project's docs and its agent instructions can point at - a fast path nobody invokes is worth nothing. A profile's `stages:` key is an allow-list; every other stage, built-in or custom, is reported as skipped naming the profile. The profile merges over the config file and under the CLI. An unknown name fails the run, because falling back to "run everything" would turn a typo into a slow green
- **`--until-first-failure`** runs one stage at a time, cheapest first, and stops at the first failure. An iterating caller does not need a full battery report, it needs the next thing to fix, and a run that pays for the suite before saying "you have a formatting error" is the opposite of that
- **`test: [coverage: false]`** was already config-settable; profiles make it settable per profile, so a run can drop instrumentation while keeping dialyzer, which previously required taking all of `--quick`. Measured on a 3,700-test umbrella, warm build, 15 cores: 3.3s of 47s wall clock, but +46% user time, so the wall cost moves toward the CPU figure where cores are scarce
- **`--report -`** writes the report to stdout, as `--format json` does. Agents were parsing human terminal text because a file path is one more step
- **`profile`, `scope` and `base_ref` at the report root**, always present. `status` alone does not say what a run is evidence for: a green run over three test files and a green full run are different claims, and this is what lets anything that ratchets a number, moves a baseline or gates a merge refuse to move on the narrow one
- The Tests stage reports `scope`, `files`, `test_files`, `base_ref` and the coverage keys above in its own object
- `ExQuality.Scope`, which owns scope parsing and resolution
- `ExQuality.Config.apply_profile/2` and `ExQuality.Config.profile/1`
- A stage result may carry `meta`, a map of extra report fields describing what the stage did rather than what it found

### Changed

- Format, Compile and Tests can now be turned off by `--skip <key>` or by a profile's `stages:` list, and are reported as skipped with the reason like any other stage. They have never been skippable before, and an unprofiled run with no `--skip` still runs all three unconditionally
- A run with no `--profile`, no `--test-scope` and no `--until-first-failure` behaves exactly as it did in 0.11.0. This is a 0.x library with real users, and the default path does not move

## [0.11.0] - 2026-08-01

### Fixed

- **A skipped custom stage's reason is no longer whatever the toolchain printed first.** The reason a person reads was the command's first non-empty line, which made it hostage to output the command did not write: `mix` emits `==> app` headers for an umbrella and a build-lock notice when another stage holds the lock, either of which turned `skipped (the database has no tables - run bin/test-setup)` into `skipped (==> admin)`. That defeats the point of `skip_exit_code:`, which exists to turn a confusing failure into a reason somebody can act on. The document's `summary` is now preferred when the command wrote one, falling back to the first line for a command that prints prose or sets `parse: :none`
- **A custom stage's `command:` may name a project's own script.** `System.cmd/3` resolves a bare name on the PATH and otherwise wants an absolute path - even `./bin/check.sh` raises `:enoent` - so a repo-relative script, which is the ordinary case for a custom stage, had to be written as `command: "bash", args: ["bin/check.sh"]`. A command containing `/` is now expanded before it runs, relative to `cd:` when the entry names one and to the project root otherwise, so an entry reads as the shell it looks like. A bare name still goes to the PATH and an absolute path is used as it stands

## [0.10.0] - 2026-08-01

### Added

- **`compile: [force: true]`** compiles dev and test with `--force`, so a local run matches the cold build CI does. The usual argument for `--force` - that a warm build hides warnings - is obsolete, since Elixir re-emits persisted diagnostics for unchanged files. One class does survive: remove a public function and its callers are not recompiled, because a remote call is not a compile-time dependency, so nothing warns locally and CI fails. Off by default, since it costs a full recompile of the project's own apps on every run and is redundant in CI. The success summary names it (`dev + test compiled (forced, warnings as errors)`), and a forced run that passes stays as quiet as an incremental one

## [0.9.0] - 2026-08-01

### Added

- **Credo can run more than one config.** A `.credo.exs` that declares a second config - the usual case is one check over `priv/*/migrations/`, which sits outside credo's default `files.included` - had that config silently never run, because the stage always invoked `mix credo` once with no `--config-name`. A check the project believes is enforced, was not. `credo: [configs: ["default", "migrations"]]` now runs one invocation per name, in order, and merges the results into one stage result
- Findings from multiple credo configs are deduplicated on `{file, line, column, check}`, so two configs with overlapping `files` globs do not double an issue count
- A credo run that fails without reporting issues now names the config it came from (`Check failed in "migrations" (see output)`), because the likeliest cause is a config name `.credo.exs` does not define
- **Custom stages.** A project with a house check, a schema linter, a custom mix task or a shell script gate could have ExQuality's parallelism, timing, report and printer, or it could have its own check, but not both - so those checks lived outside the run, outside the JSON report, and outside anything that routes findings to fixers. `custom:` in `.quality.exs` registers them as stages. An entry names either a `module:` implementing the existing `ExQuality.Stage` contract, or a `command:` run by the new `ExQuality.Stages.Command`
- A custom command reports structured findings by printing one JSON document on stdout (`summary`, `stats`, `findings`); only `file` and `message` are required per finding, and `app` is inferred from the path. Output that does not parse falls through verbatim, as everywhere else. `parse: :none` opts out for a command known to print prose
- `skip_exit_code:` lets a custom command say "not applicable" - a nullability check needs a migrated test database, and without it the stage fails with a database error that reads like a code problem. The stage reports `:skipped` with the command's own reason instead
- `--skip <key>` skips any stage by key, built-in or custom, and is repeatable. `@switches` is static, so a custom stage could never have a `--skip-<key>` generated for it. The existing `--skip-credo` and friends are unchanged
- `ExQuality.Finding.from_map/2`, the reading half of the report's finding encoding. It is what a custom command's output is decoded with, and what a consumer of a report needs in order to read one back

### Changed

- Malformed `custom:` entries fail the run at load time and name the offending entry: a missing `key` or `name`, neither or both of `module`/`command`, a key or name colliding with a built-in stage, a duplicate key, an unknown `kind`, or a module that is not loadable or does not export `run/1`. A stage that never registers is a check nobody is told is not running

## [0.8.0] - 2026-08-01

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

[Unreleased]: https://github.com/riddler/ex_quality/compare/v0.13.0...HEAD
[0.13.0]: https://github.com/riddler/ex_quality/compare/v0.12.0...v0.13.0
[0.11.0]: https://github.com/riddler/ex_quality/compare/v0.11.0...v0.12.0
[0.10.0]: https://github.com/riddler/ex_quality/compare/v0.10.0...v0.11.0
[0.9.0]: https://github.com/riddler/ex_quality/compare/v0.9.0...v0.10.0
[0.9.0]: https://github.com/riddler/ex_quality/compare/v0.8.0...v0.9.0
[0.8.0]: https://github.com/riddler/ex_quality/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/riddler/ex_quality/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/riddler/ex_quality/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/riddler/ex_quality/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/riddler/ex_quality/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/riddler/ex_quality/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/riddler/ex_quality/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/riddler/ex_quality/releases/tag/v0.1.0
