# ExQuality Plan: Findings, Umbrellas, and More Stages

Status: in progress. Nothing here has shipped in a release yet.

This document collects the changes we want to make to ExQuality, why each one
matters, and where in the current codebase it lands. It is written to be worked
from later, so each proposal names the modules and functions it touches.

## Progress

Update this table as work lands. "Done" means committed with tests, credo,
dialyzer and format all green; it does not mean released.

| Item | Status | Where |
| --- | --- | --- |
| P1. Findings model | Done | `d3c5a02` on `feat/findings-model` |
| P2. Skipped stages must say so | Done | `16fbce4` on `feat/findings-model` |
| P3a. Umbrella tool auto-detection | Done | `feat/findings-model` |
| P3b. Umbrella test statistics | Done | `feat/findings-model` |
| P3c. Findings carry their app | Done | `feat/findings-model` |
| P4. Machine-readable output | Done | `feat/findings-model` |
| P5. Sobelow stage | Done | `feat/findings-model` |
| P6. Coverage without ExCoveralls | Done | `feat/findings-model` |
| P7. Dialyzer PLT lifecycle | Done | `feat/findings-model` |
| P8.1. Format discards the exit code | Done | `feat/findings-model` |
| P8.2. Dialyzer warning counting | Done | `feat/findings-model` |
| P8.3. Vulnerability counting | Done | `feat/findings-model` |
| P8.4. Credo machine format | Done | `feat/findings-model` |
| P8.5. `.quality.exs` from the project root | Done | `feat/findings-model` |

### P1 notes

Landed as `ExQuality.Finding` plus an **optional** `findings` key on
`Stage.result`, read through `Stage.findings/1`. Optional rather than required
so the remaining stages adopt findings one at a time instead of in a single
mechanical edit. `Mix.Tasks.Quality.display_failure_details/1` renders findings
when a stage supplies them and falls back to verbatim `output` otherwise.

Credo is the only stage converted so far. Two things were deliberately left for
later:

- `check` holds credo's **category** (`readability`, `refactor`, ...), not the
  check module the P1 sketch shows. Credo's text output does not name the
  module; `--format json` does, which is P8.4. That switch retires the parser
  added here.
- `stats.issue_count` still comes from the summary-line parse rather than
  `length(findings)`, because an issue whose location line does not parse is
  deliberately dropped from findings. Reconciling the two numbers belongs with
  the same JSON switch.

The open question about a default limit was answered as **unlimited by
default**; `--max-findings` stays opt-in so the existing no-truncation promise
holds. `Format` still emits no findings.

### P2 notes

`build_analysis_stages/1` now returns both the stages to run and a
`Stage.skipped/2` result for every stage it left out, printed before the
parallel stages start so the reader sees what the run is not evidence for
before any of it scrolls past.

The reason comes from `Config.skip_reason/2`, which distinguishes a CLI switch
from `.quality.exs` by recording a `disabled_by` key when either source sets
`enabled: false`. Quick mode is still resolved in the task rather than in
`Config`, because it only ever suppresses dialyzer; an explicit disable is
reported in preference to `--quick`.

Skipped results are returned alongside the real ones, so P4's JSON shape gets
them for free. The reason lives in `summary`; a `:skipped` entry has no
separate `reason` field.

Left alone deliberately: the final `✅ All quality checks passed!` line says
nothing about skips. The per-stage lines above it already do, and qualifying
the summary line is a wording question better settled once P4 exists.

### P3 notes

Umbrella knowledge landed in one place, `ExQuality.Umbrella`: `umbrella?/0`,
`apps_paths/0`, `app_for_path/2` and `child_deps/0`. Each answers `false`, `%{}`
or `nil` for a single-app project, so no caller branches on the project shape.

`child_deps/0` reads each child's `mix.exs` through `Mix.Project.in_project/3`
and caches the result in `:persistent_term` for the VM, because `Tools.detect/0`
is called once by `Config.load/1` and again by the test stage. A child whose
`mix.exs` fails to evaluate contributes nothing rather than crashing detection;
the compile stage reports that problem far better than detection could.

A `fixtures/umbrella` project covers P3a end to end: credo is declared only by
`apps/core`, so a run that reads the root alone reports credo as not installed
and passes. The integration test asserts the run fails, and that the findings
are grouped under `── core ──`.

Two deliberate departures from the sketch above:

- The test summary names only the apps that **failed**
  (`3 of 4,180 failed (web: 3)`), not every app with its zero. A ten-app
  umbrella would otherwise spend most of the line on apps a reader has no
  action to take on.
- Several `[TOTAL]` coverage lines mean the apps were measured separately, so
  there is no suite-wide number to report. The lowest leads, labelled as such
  (`72.1% coverage (lowest of 3 apps)`), with the rest in
  `stats.coverage_by_app`. Averaging them would print a number no tool
  produced. `String.to_float` also became `Float.parse`, so an integer
  percentage no longer raises.

App names in test stats stay **strings**, taken from the `==> app` headers,
rather than being converted to atoms: they come from tool output, and
`Finding.app` is the only place an app name is trusted enough to be an atom
(it comes from `Mix.Project.apps_paths/0`).

Credo is still the only stage emitting findings, so P3c is visible there alone.
Each stage picks up app tagging as it adopts findings.

### P4 notes

Both surfaces landed: `--report PATH` writes JSON to a file and leaves the
human stream alone, `--format json` puts JSON on stdout and moves the human
stream to stderr. They compose. `ExQuality.Report` builds the document from the
same result list the human renderer uses, so the two can never disagree.

Moving the human stream is done by installing `ExQuality.Shell.Stderr` for the
duration of the run rather than teaching each call site which mode it is in;
the previous shell is restored in an `after`. Only the verbatim failure body
needs to know, because it writes with `IO.write/2` rather than through the
shell (a deliberate 0.6.0 decision about truncation), so it takes the device as
an argument.

Four departures from the sketch above:

- A skipped stage puts its reason in `summary` like every other status, rather
  than in a separate `reason` field. Consistent with the P2 decision, and it
  leaves a consumer with one field to read instead of a branch.
- Stages carry `stats` too. It is already structured, and `test_count` /
  `coverage` are exactly what a caller would otherwise re-derive. Pair lists
  such as `failures_by_app` become JSON objects, since JSON has no tuples.
- A failing stage with no findings carries its tool's `output`, mirroring the
  human renderer's fallback. Without it, the JSON would be strictly less
  informative than the console for every stage that has not adopted findings
  yet, which is most of them.
- `Finding.raw` is not in the JSON. It exists so a parser bug degrades into
  showing the original lines, and the `output` fallback above already covers
  the machine reader's version of that.

Emitting the report needed one exit path for the whole run, which closed a P2
hole on the way: a compile failure used to abort before the analysis stages
were even enumerated, so the run said nothing about them. It now reports each
as `skipped (compile failed)`, in both streams.

The report is written before `Mix.raise/1`, so a failing run still produces
one. The exit code is unchanged: 0 or 1 for the whole run, with the report as
the thing to route on.

### P5 notes

`ExQuality.Stages.Sobelow` runs the tool with `--format json` and reads the
report from `--out` rather than stdout, so nothing the tool writes to either
stream can corrupt it. An older sobelow that does not know `--out` still prints
the JSON, so stdout is tried as a fallback before a scan is called a failure;
a scan that produced no report at all fails the stage loudly with the tool's
output, because a broken invocation is not a clean bill of health.

`--config` turned out to be unusable: it replaces *every* other option with the
contents of `.sobelow-conf`, including the output format, so asking for JSON
and asking for the project's config are mutually exclusive. The stage reads
`.sobelow-conf` itself and passes the parts that say what to scan (`ignore`,
`ignore_files`, `router`, `skip`, `threshold`) as switches.

`--exit` is never passed either. The stage decides pass or fail from the
findings it parsed, against the same threshold sobelow would have used, which
is what lets it distinguish "nothing blocking" from "did not run" and lets it
report the informational count instead of just swallowing it.

Three decisions the sketch above did not settle:

- **Threshold precedence.** `.sobelow-conf`'s `exit:` wins over
  `.quality.exs`, which only supplies a default for a project without that
  file; the default when neither says is `medium`. Sobelow's own default is to
  never fail, which would make the stage a no-op gate. A conf that explicitly
  asks for no exit status is still honoured: every finding becomes
  informational and is counted.
- **The expand flag** is `sobelow: [show_informational: true]`, plus the
  existing `--verbose`, rather than a new CLI switch of its own.
- **Which apps to scan.** Only child apps declaring `:phoenix` or `:sobelow`.
  Sobelow halts with an error on anything else, and a run that named every
  non-Phoenix app as unscanned would spend most of its output on apps a reader
  has no action to take on. This needed `Umbrella.app_deps/0`;
  `child_deps/0` is now derived from it and shares its cache.

Confidence rides in the finding's message (`XSS (medium confidence)`) because
`severity` is already spent on whether the finding blocks. `check` is
sobelow's module (`Config.CSRF`), split off the front of its finding type.

`mix quality.init` was deliberately left alone: sobelow is a Phoenix tool, and
offering it to every project the installer touches would be wrong.

Not covered by an integration fixture. One would need a Phoenix app and a real
sobelow dependency; the stage is covered by unit tests that stub the command
and write a real report file the way sobelow does.

### P6 notes

The open question is answered: `mix test.coverage` **does** enforce the
threshold and exits 3, both in a single app and at an umbrella root, so the
stage does not have to compare the aggregate itself. `--export-coverage` is the
opposite: it suppresses the summary and the check entirely, which is why the
umbrella path is two commands rather than one.

`Stages.Test` now picks one of three modes — `:coveralls`, `:native`,
`:plain` — instead of a `use_coveralls` boolean, and everything downstream reads
the mode. The umbrella scan, summary formatting and threshold reading are
shared between the two measuring modes; only the command and the table format
differ.

Four decisions the sketch above did not settle:

- **Native coverage is not on for every project without excoveralls.** Elixir's
  built-in threshold defaults to **90%** whether or not a project has ever
  thought about coverage, so enabling it unconditionally would turn a passing
  `mix quality` red over a number nobody chose. It runs when the project states
  a threshold the way the built-in tool reads it
  (`test_coverage: [summary: [threshold: N]]`), which is the project saying it
  wants a gate. `test: [coverage: true]` in `.quality.exs` forces it on for a
  project that wants measuring without stating a number, and `false` forces it
  off.
- **The threshold printed by the tool wins over the one read from config.**
  `mix test --cover` names the threshold it enforced, but only on a failure,
  which is the one case where being exact matters.
  `read_coverage_threshold/1` became mode-aware rather than trying every key:
  reading `minimum_coverage` for a native run would report a threshold nothing
  enforces.
- **Findings name a file, not a module.** The coverage table names modules, but
  every other stage's findings are `file:line`, and P3c's app tagging can only
  be derived from a path. The source is read out of the compiled beam's
  `compile_info` in `_build/test` rather than by loading the module, which was
  compiled into an environment this process is not running in. A module whose
  beam is not found falls back to its own name as the `file`, so the finding is
  still reported.
- **Modules are reported only when the run failed on coverage.** The threshold
  is a statement about the total, so a passing run can hold a module at 0% and
  there is nothing for a reader to do about it. Reporting it anyway would put
  findings on a stage that passed.

Two fixes on the way, both under the same "single source of truth" promise:
`coveralls.json`'s `minimum_coverage` is read from `coverage_options`, where
excoveralls actually writes it (only the top level was looked at, so a project
configuring it the standard way had no threshold enforced at all), and an
integer threshold no longer crashes the summary formatter.

Covered by a `fixtures/native_coverage` integration test end to end: no
excoveralls, a stated threshold, one of four functions tested, and an assertion
that the failure names the module and its source file. A second case asserts
`--quick` runs the suite without measuring.

### P7 notes

The progress line is printed **while the build runs**, not derived from the
output afterwards, because reporting a four-minute wait once it is over does
nothing for the reader who is staring at a stalled terminal. The stage now
streams `mix dialyzer` into `ExQuality.OutputCollector` with an `:on_line`
handler instead of capturing it wholesale; the collector reassembles lines,
since a chunk arrives at whatever boundary the port gives it.

`ExQuality.Plt` holds the one piece of dialyxir-specific knowledge involved:
which of its lines mean a build. `Creating`, `Copying`, `Adding N modules to`
and the umbrella-child line count; `Checking N modules in` deliberately does
not, because it runs against a warm PLT too. `build_watcher/1` fires once, on
the first of them, so a build reports progress rather than noise. It uses an
atomic rather than a process, so it has nothing to clean up and cannot outlive
the command it is watching.

Three decisions the sketch above left open:

- **A PLT build is not a skipped-adjacent status.** It stays a pass. Analysis
  against a freshly built PLT is the same analysis as against a warm one, and
  reporting it as anything less than a pass would put a false gap in the very
  output P2 exists to close. What was actually missing was an explanation for
  the duration, so the build is reported instead: `stats.plt_built` and a
  summary note (`No warnings (PLT built this run)`), carried in the JSON report
  for free. The stat is present only when it happened, since a key that is
  false on every warm run tells a reader nothing.
- **`mix quality.plt` rather than `mix quality --plt-only`.** The warm-up is a
  different job with different output: a check summarises, and this task exists
  precisely for the progress, so it passes dialyxir's own stream through as it
  arrives. A flag on `mix quality` would have to suppress every other phase to
  mean anything.
- **No PLT detection before the run.** Deciding "the PLT is cold" up front
  would mean reimplementing dialyxir's path resolution (`plt_core_path`,
  `plt_local_path`, `plt_file`, OTP and Elixir version strings), and getting it
  wrong prints a one-time-cost warning on a run that pays no such cost. Reading
  what the tool says it is doing cannot be wrong in that way.

`Printer.print_message/1` now falls back to the shell when no printer is
running, so a stage that reports progress can also be run outside a parallel
run without failing on a missing agent.

Not covered by an integration fixture: one would need a real dialyxir
dependency and a real PLT build, which is minutes per run. The stage's unit
tests stub the command and write the output the way dialyxir does, streaming it
through the same collector.

The README's CI note was corrected on the way. It suggested caching
`priv/plts`, which is a path dialyxir uses only if a project configures it;
by default the PLTs live in `_build` and `Mix.Utils.mix_home/0`.

### P8 notes

Taken one at a time, since they share a theme rather than an implementation.

**P8.1.** The Format stage now reads the exit code of `mix format` itself, not
the `--check-formatted` run before it: that one exits non-zero whenever a file
needs formatting, which is the ordinary case. A failing `mix format` keeps the
`files_formatted` count alongside the failure, because it still rewrites every
file it could parse before giving up on the one it could not.

Reading the exit code turned up a second case the old code was hiding: `mix
format` also fails when there is no `.formatter.exs`, which is a project that
has never used the formatter rather than a project with a problem. Failing
every such run would be a new gate nobody asked for, so the stage reports it as
skipped, which is what P2 exists to make readable.

**P8.2.** `--format short` puts each warning on one line
(`lib/user.ex:42:5:no_return Function create/1 has no local return.`), which
makes the count the number of findings and gives each one the warning's name
(`no_return`, `pattern_match`) as its `check`. The old heuristic counted every
line matching `.exs?:\d+:`, so PLT chatter and any explanation naming a second
file counted as warnings.

Both formatters are passed (`--format short --format dialyxir`), because
dialyxir accepts `--format` more than once and prints each warning in every
format asked for. The short line is what parses; the long explanation stays in
`output`, which is what a reader falls back to when the one-liner is not enough
and what the JSON report carries for a stage that parsed nothing. It costs
nothing to parse: the explanation's header line ends at the warning name, with
no message after it, so it never reads as a second finding for the same
warning.

Every dialyzer warning fails the stage, so findings are `severity: :error`
rather than `:warning`; the tool's word for them is not a statement about how
much they matter.

`mix quality.plt` is untouched. It runs `mix dialyzer --plt`, which builds
rather than analyses, and its whole purpose is to pass dialyxir's own progress
through.

**P8.3.** `mix deps.audit --format json` gives the advisory, the version in
use and the version that fixes it, so the finding says what to do
(`plug 1.13.6: Arbitrary code execution (high severity, patched in 1.14.0)`)
rather than how many lines said `Advisory:`. Severity comes from the advisory
itself and is carried in the message, because `Finding.severity` is spent on
"this blocks the run", which every vulnerability does.

The finding's file is the lockfile the vulnerable version is pinned in, since
that is the file a reader changes. An advisory with no severity or no patched
version says so; guessing either would be worse than a gap.

Two decisions the sketch above did not settle:

- **Unused dependencies became findings as well.** They had to: findings stand
  in for output when a stage has them, so a stage that rendered only its
  vulnerabilities would have hidden the unused-dependency list beside them.
- **A failing check that parses into nothing turns findings off for the whole
  stage**, rather than for its own half. Half a rendered stage plus half a
  swallowed one is the failure mode the P1 fallback exists to prevent, and an
  audit that failed while reporting no vulnerability is mix_audit saying
  something about itself that only its output records.

**P8.4.** `mix credo --strict --format json` replaces the text parser, which
answers both things P1 left open: `check` is the check module, and
`issue_count` is `length(issues)` rather than a summary-line parse that could
disagree with the findings beside it. The five category regexes are gone; the
summary's breakdown is a frequency count over the issues' own categories,
ordered most severe first.

The JSON is looked for in the output rather than assumed to be all of it,
because `mix` compiles the project first and prints as it goes. That belongs to
no one stage, so it landed as `ExQuality.Json.decode/1`: the whole output, then
each line opening an object in column one (a compact document, which is what
`mix deps.audit` writes), then the rest of the output from each such line (a
pretty-printed one, which is what credo writes).

A run that printed no document at all is reported as a failure with credo's own
output, which is what a version too old to know `--format json` produces. The
alternative -- keeping the text parser as a fallback -- would mean carrying two
parsers indefinitely to serve a version that has not existed since credo 1.0.

Severity is `:warning` for credo's `warning` category and `:info` for the rest.
Credo's own severity is `priority`, but it is a number tuned per check for
sorting, not a statement about whether the issue is a bug.

**P8.5.** `Config.config_path/0` resolves the project root from
`Mix.Project.project_file/0`, and an umbrella child with no `.quality.exs` of
its own falls back to the umbrella root's, since the settings describe the
tree. The root lookup needs `Mix.Project.parent_umbrella_project_file/0`, which
is Elixir 1.15; on the 1.14 this package still supports, only the project's own
root is read. The decision that does the work is testable on its own
(`config_path/2` takes both roots), because the wiring to `Mix.Project` is not.

## Motivating context

The driving real-world project is a large Elixir umbrella (10 apps, a
CQRS/Event-Sourcing core, a Phoenix web app, a marketing site) where all tooling
runs inside a Docker Compose service. That project currently drives six
independent check scripts and a bash loop that re-invokes an LLM per failing
check. Collapsing that onto `mix quality` is the goal, and every gap it exposed
is a general gap, not a quirk of that repo.

Every proposal below is written to hold for a single-app project too. Umbrella
support is the forcing function, not the audience.

## The guiding principle, sharpened

ExQuality's differentiator is **actionable output**: show the minimum a reader
needs in order to act, and nothing else. Today that is implemented as:

- **On success**: one line per stage. This is right, and should not change.
- **On failure**: the entire raw stdout of the failing tool
  (`Mix.Tasks.Quality.display_failure_details/1`, `lib/mix/tasks/quality.ex:243`,
  which does a bare `IO.write(failure.output)`).

The failure path is the correct *policy* with a placeholder *implementation*. A
tool's whole stdout is a usable proxy for "the findings" only while the project
is small. Scale it up and the proxy breaks down:

- A failing `mix test` across ten umbrella apps is thousands of lines, of which
  perhaps forty matter.
- `mix dialyzer` prints a header, a PLT status block, then warnings.
- `mix sobelow` prints an ASCII banner and every low-confidence finding
  alongside the medium and high ones that actually block.
- `mix test --cover` prints a full per-module percentage table when the only
  actionable rows are the ones under threshold.

The v0.6.0 fix ("output full, non-truncated content when errors occur") was the
right call against the alternative of blind truncation, and `usage-rules.md`
correctly tells LLMs never to pipe through `tail`. But "never truncate" and
"show only what is actionable" are only in tension while output is an
unstructured stream.

**So the central proposal is: make the unit of output a finding, not a stream.**
Once a stage returns a list of structured findings, ExQuality can show all of
them, or the first N with an honest count of the rest, without ever losing a
`file:line`. Truncation stops being a risk because nothing is being cut out of
the middle of a blob.

Everything else in this document either depends on that or is made cheaper by
it.

---

## P1. A findings model

**Problem.** `ExQuality.Stage.result` (`lib/ex_quality/stage.ex`) carries
`output` as a `String.t()` and `stats` as a loose map of counts. Each stage
re-derives counts from its own tool's text with a bespoke regex, then throws the
structure away and hands back the raw string. `Stages.Credo.parse_categories/1`
and `Stages.Dialyzer.parse_warning_count/1` already do most of the parsing work
required to build real findings, then discard everything but a number.

**Proposal.** Add `ExQuality.Finding`:

```elixir
%ExQuality.Finding{
  file: "apps/web/lib/web/contacts.ex",  # relative to project root
  line: 42,
  column: 8,                                      # optional
  app: :web,                                  # optional, umbrella only
  severity: :error | :warning | :info,
  check: "Credo.Check.Readability.ModuleDoc",     # tool-specific rule id
  message: "Modules should have a @moduledoc tag.",
  raw: "..."                                      # the source lines, verbatim
}
```

Extend `Stage.result` with `findings: [Finding.t()]`, keeping `output` for the
tail that does not parse into findings (a compiler crash, a PLT build failure, a
tool that changed its format). Rendering rule:

1. If `findings` is non-empty, render findings. Group by file, sort by line.
2. If `findings` is empty but the stage failed, fall back to today's behaviour
   and print `output` verbatim. **Unparseable output is never hidden.**

The `raw` field is what keeps this honest: a finding always carries the text it
was derived from, so a parser bug degrades into "shows the original lines"
rather than "silently drops a real problem".

**Why this serves actionable output.** It lets a `--max-findings` style limit
exist without lying. "Showing 40 of 218 findings" is honest and complete at the
level a reader acts on, where `| head -40` is neither. It also means the
existing summary lines stop being independently parsed guesses and start being
`length(findings)`.

**Open questions.**

- Default limit, or unlimited by default? Leaning unlimited by default with an
  opt-in `--max-findings`, because the current no-truncation guarantee is a
  promise users have already been told to rely on.
- Should `Format` emit findings (one per reformatted file)? It is a fix, not a
  problem, so probably not.

---

## P2. Skipped stages must say so

**Problem.** `Stage.result` declares a `:skipped` status
(`lib/ex_quality/stage.ex:21`), `Printer.do_print_result/1` handles it
(`lib/ex_quality/printer.ex:76`), and `Mix.Tasks.Quality.display_phase_result/1`
handles it (`lib/mix/tasks/quality.ex:238`). **No stage ever returns it.**
`build_analysis_stages/1` (`lib/mix/tasks/quality.ex:176`) simply omits disabled
stages from the task list, so a skipped stage produces no output at all.

A run that skipped dialyzer is textually indistinguishable from a run where
dialyzer had nothing to say. For a human, that is a papercut. For an LLM reading
the output as evidence, it is a false clean bill of health, and it is the exact
failure mode where an agent reports "all checks pass" on unverified code.

**Proposal.** Emit a `:skipped` result for every stage that was considered and
not run, with the reason attached:

```
○ Dialyzer: skipped (--quick)
○ Doctor: skipped (:doctor not installed)
○ Credo: skipped (disabled in .quality.exs)
```

Silence is the one thing output should never be ambiguous about, and one line
per skipped stage is cheap.

---

## P3. Umbrella awareness

Three separate defects, one theme.

### P3a. Tool auto-detection reads only the root project

**Problem.** `ExQuality.Tools.get_project_deps/0` (`lib/ex_quality/tools.ex:58`)
reads `Mix.Project.config()[:deps]`. In an umbrella, the root `mix.exs` almost
always has `defp deps, do: []`, with credo, dialyxir, excoveralls and friends
declared in the child apps. So `Tools.detect/0` returns all `false`, and
`mix quality` silently runs only format, compile, dependencies and test.

Silently is the operative word: because of P2, the run prints a clean result and
never mentions that credo and dialyzer did not happen.

**Proposal.** When `Mix.Project.umbrella?/0` is true, union the root deps with
each child's. `Mix.Project.apps_paths/0` gives the child paths;
`Mix.Project.in_project/4` reads each child's config. Cache the result for the
run.

**Fallback.** Users on an older ExQuality can already work around this with
`.quality.exs` (`credo: [enabled: true]` etc.), and that stays supported.
Auto-detection should just stop needing it.

### P3b. Test statistics are read from the first app only

**Problem.** `Stages.Test.parse_test_stats/2` (`lib/ex_quality/stages/test.ex:79`)
uses `Regex.run/2` on `~r/(\d+) tests?, (\d+) failures?/`. `Regex.run` returns
the **first** match. An umbrella `mix test` prints one summary line per app, so
the reported counts are whichever app ran first, not the suite.

The exit code is still correct, so this never causes a wrong pass/fail. It makes
the summary line wrong, which is worse in a specific way: a confident, specific,
false number ("3 of 12 failed" when the truth is "3 of 4,180 failed") reads as
more trustworthy than no number at all.

**Proposal.** `Regex.scan/2` and sum. Same treatment for the coverage regex
(`test.ex:97`), where an umbrella can print more than one `[TOTAL]`. Where
per-app numbers are available, attribute them:

```
✗ Tests: 3 of 4,180 failed (web: 3, core: 0, repo: 0, ...)
```

### P3c. Findings should carry their app

Once P1 exists, tag each finding with its umbrella app and group failures by app
in the rendered output. In a ten-app umbrella, "which app is broken" is the first
question a reader has, and it is currently answerable only by reading paths.

---

## P4. Machine-readable output

**Problem.** `mix quality` exits 0 or 1 for the whole run
(`Mix.Tasks.Quality.run/1` calls `Mix.raise/1` on any failure). A caller cannot
tell *which* stage failed without scraping the console.

That is the blocker for the automation this is meant to serve. The motivating
project's `bin/prep-commit.sh` runs six checks in six separate `until` loops
precisely so it knows which fix instruction to hand the LLM on failure. Collapsed
onto a single `mix quality` with a single exit code, that routing is lost, and
you are back to booting an agent that must re-run tools to find out what broke.

**Proposal.** Structured output derived from the findings model:

```bash
mix quality --format json          # machine output on stdout, human on stderr
mix quality --report .quality.json # human on stdout, machine to a file
```

Shape:

```json
{
  "version": "0.7.0",
  "status": "error",
  "duration_ms": 48213,
  "stages": [
    {
      "name": "Credo",
      "status": "error",
      "summary": "5 issues (2 readability, 3 design)",
      "duration_ms": 412,
      "findings": [
        {
          "file": "lib/user.ex", "line": 42, "column": 3,
          "app": "web", "severity": "warning",
          "check": "Credo.Check.Readability.ModuleDoc",
          "message": "Modules should have a @moduledoc tag."
        }
      ]
    },
    { "name": "Dialyzer", "status": "skipped", "reason": "--quick" }
  ]
}
```

`--report` is probably the more useful of the two: it keeps the human stream
intact while giving a script something to route on, which suits a pre-commit
driver better than parsing stdout.

**Why this serves actionable output.** It is the same principle applied to a
non-human reader. A script that can ask "which stages failed, and what are the
findings" never needs to re-run a tool to find out.

---

## P5. Sobelow stage

**Problem.** No security static-analysis stage exists. Sobelow is the standard
Phoenix answer and is already a hard gate in the motivating project.

**Proposal.** `ExQuality.Stages.Sobelow`, auto-enabled on `:sobelow` in deps.

The actionable-output angle is unusually strong here, because sobelow's default
output is mostly *not* actionable:

- It prints a large ASCII banner.
- It prints findings at all three confidence levels (high/red, medium/yellow,
  low/green), but `.sobelow-conf`'s `exit:` setting decides which ones actually
  fail the build. A project on `exit: "medium"` gets low-confidence findings
  printed on every run that nobody is expected to act on.

So the stage should **separate blocking findings from informational ones**: emit
findings at or above the configured exit threshold as `severity: :error`, and
report the rest as a count only (`3 low-confidence findings not shown`), with a
flag to expand them. That is the principle doing real work rather than just
reformatting.

**Design notes.**

- Prefer `mix sobelow --format json` if the installed version supports it. It
  removes the parser entirely and makes P1 nearly free for this stage.
- **Umbrella:** `mix sobelow` at an umbrella root does not fan out to child apps
  on its own, and each Phoenix app carries its own `.sobelow-conf`. Projects
  work around this with a root alias per app
  (`cmd --app web mix sobelow --config`). The stage should do that fan-out
  itself when `Mix.Project.umbrella?/0`, running per app in parallel and merging
  findings, tagged by app per P3c.
- **Do not offer to modify `.sobelow-conf`.** Adding an `ignore` entry or
  lowering `exit:` is a security decision, and a tool that silences its own
  findings to go green is a regression dressed as a pass. The motivating project
  enforces this with a hook that denies edits to the file. ExQuality should
  never suggest suppression as a remedy in its output.

---

## P6. Coverage without ExCoveralls

**Problem.** `Stages.Test` only measures coverage when `:excoveralls` is
installed (`lib/ex_quality/stages/test.ex:27-39`); otherwise it runs bare
`mix test`. Elixir has shipped built-in coverage since 1.11
(`mix test --cover`, with `test_coverage: [summary: [threshold: N]]` and
`mix test.coverage` for aggregation), and plenty of projects use it rather than
take on a dependency.

Compounding it, `read_coverage_threshold/0` (`test.ex:120`) looks for
`test_coverage[:minimum_coverage]` and `test_coverage[:threshold]`, but the
built-in tool nests it as `test_coverage[:summary][:threshold]`. So even a
project that sets a threshold the standard way has it read as `nil`.

**Proposal.**

- Add a third tool key, `:native_coverage`, true whenever `:excoveralls` is
  absent, and run `mix test --cover` in full (non-quick) mode.
- Teach `read_coverage_threshold/0` the `[:summary][:threshold]` path, keeping
  the `coveralls.json` and `minimum_coverage` lookups for excoveralls projects.
  The "single source of truth" promise in the README should hold for both tools.
- Parse the built-in `Percentage | Module` table and the
  "Coverage test failed, threshold not met" line.
- **Report only the modules under threshold as findings, not the whole table.**
  A 400-module umbrella prints 400 rows; the actionable subset is the handful
  below the line. This is the coverage-shaped instance of the central principle.
- **Umbrella:** per-app `mix test --cover` only sees its own app's modules, so a
  module covered by another app's tests reads as 0%. The correct sequence is
  `mix test --cover --export-coverage default` followed by `mix test.coverage`
  to aggregate. The stage should do this automatically under
  `Mix.Project.umbrella?/0`.

**Open question.** Does `mix test.coverage` enforce the threshold and set a
non-zero exit, or only print? If only print, the stage has to compare the
aggregate against the threshold itself.

---

## P7. Dialyzer PLT lifecycle

**Problem.** `Stages.Dialyzer` runs `mix dialyzer --no-compile`
(`lib/ex_quality/stages/dialyzer.ex:26`). `--no-compile` is correct and was
added deliberately in 0.4.0 to stop the parallel stages fighting over
`_build/dev`. But nothing builds the PLT. On a cold checkout or a fresh CI
container, the first `mix quality` pays a multi-minute PLT build inside a stage
whose printed output is a single line at the end, so the run looks hung.

The current graceful-degradation path
(`debug_info_error?/1`, `dialyzer.ex:84`) is a good instinct pointed at a
different problem.

**Proposal.**

- Detect PLT-building in the output and report it as distinct progress rather
  than letting it hide inside stage latency. `Printer` already serializes output,
  so a `⋯ Dialyzer: building PLT (this is a one-time cost)` line is cheap.
- Add `mix quality.plt` (or `mix quality --plt-only`) as an explicit warm-up
  target, so CI and container images can build the PLT in a cacheable step
  instead of inside a check.
- Consider treating "PLT was built this run" as a `:skipped`-adjacent status
  rather than a pass, since a first-run PLT build followed by a clean analysis
  is not the same evidence as a clean analysis against a warm PLT.

---

## P8. Smaller correctness items

Individually minor. Grouped because they share a root cause: parsing tool text
with heuristics, which P1 partly retires.

1. **`Format` discards the exit code.** `lib/ex_quality/stages/format.ex:28`
   drops the result of `mix format`, and the stage hardcodes `status: :ok`. On a
   file with a syntax error, `mix format` fails, `parse_files_needing_format/2`
   filters the `SyntaxError` line out (it does not end in `.ex`), and the stage
   prints `✓ Format: No changes needed`. Compile catches the real problem
   moments later, so nothing is lost overall, but the first line of the run is a
   green tick on a broken file. Report the failure.

2. **Dialyzer warning counting is a line-shape heuristic.**
   `parse_warning_count/1` (`dialyzer.ex:88`) counts lines matching
   `~r/\.exs?:\d+:/`, which also matches the PLT-build chatter and any warning
   that wraps onto a second path-bearing line. Consider `--format short` or
   `--format dialyxir` for a stable machine shape.

3. **Vulnerability counting is a substring heuristic.**
   `Stages.Dependencies.count_vulnerabilities/1` counts lines containing
   `"Advisory:"` or `"advisory"`, and `count_by_severity/2` greps for
   `severity: high`. mix_audit supports `--format json`; use it.

4. **Credo has a machine format too.** `mix credo --strict --format json` (or
   `--format oneline`) would replace the five-regex category parser in
   `Stages.Credo` and feed P1 directly.

5. **`.quality.exs` is read from `File.cwd!()`** (`lib/ex_quality/config.ex:161`)
   rather than the project root. Running `mix quality` from a subdirectory of an
   umbrella silently drops the config. Use `Mix.Project.deps_path/0`'s parent or
   an explicit project-root helper.

---

## Sequencing

The dependency order matters more than the priority order.

**Phase 1: foundation.**
P1 (findings model) and P2 (skipped stages). P1 is the enabler for P4, and makes
P5 and P6 much smaller than they would otherwise be. P2 is a handful of lines
and closes a correctness hole in what the output *claims*, so it should not wait.

**Phase 2: umbrella correctness.**
P3a, P3b, P3c. These are bugs, not features, and a large umbrella is currently
getting quietly wrong answers from ExQuality. P3a in particular produces a
falsely green run.

**Phase 3: the automation surface.**
P4 (machine-readable output). Unlocks replacing a per-check bash driver with a
single `mix quality` plus a router.

**Phase 4: new stages.**
P5 (sobelow) and P6 (native coverage), in either order. Both land more cleanly
after P1.

**Phase 5: polish.**
P7 (PLT lifecycle) and the P8 items, folded in opportunistically. Several P8
items get easier once the corresponding tool is switched to a JSON format,
so pair them with the stage work rather than doing them as a batch.

Phases 1 and 2 are plausibly one minor release; 3 and 4 each warrant their own.

---

## Non-goals

- **Replacing per-tool invocation.** `mix quality` is a full-project gate. It
  should not grow file-scoped targeting; `mix credo lib/foo.ex` already exists
  and is the right tool for a tight loop.
- **Auto-fixing anything but formatting.** `Stages.Format` is deliberately the
  only stage that writes to the tree
  (`format.ex`: "This is the only stage that modifies code"). Keep it that way.
  ExQuality reports; the caller decides what to change.
- **Suppressing findings.** No stage should ever propose editing a tool's
  ignore-list as a remedy. See P5.
- **Replacing per-job CI parallelism.** A CI system that runs credo, sobelow and
  tests as separate jobs across separate runners gets parallelism, per-job logs,
  and independent retries that a single `mix quality` job cannot match.
  ExQuality's place there is as the local gate and the shared configuration
  source, not as a mandatory CI entrypoint. Documentation should say so rather
  than implying `mix quality` is the CI answer everywhere.
