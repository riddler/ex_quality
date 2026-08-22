# ExQuality usage rules

`mix quality` runs an Elixir project's quality tools in parallel and reports
the run as one stage per tool, each with a status, a one-line summary, and
findings carrying `file:line`.

## Which command

| Situation | Command |
|---|---|
| Between edits, many times | `mix quality --test-scope changed` |
| After editing code, iterating | `mix quality --quick` |
| Before committing, opening a PR, or declaring work done | `mix quality` |
| Reporting "gate green" where nobody watched the run | `mix quality.verify` |
| You need to route on *which* stage failed | `mix quality --report .quality.json` |
| Fresh checkout or container, Dialyzer installed | `mix quality.plt` once, first |

`--quick` skips Dialyzer and coverage enforcement. Everything else, tests
included, still runs. Use it while working; never use it as the final check
before reporting work complete.

## The inner loop

`--quick` narrows *which checks run*. It still runs every test, and on a large
suite the tests are most of the wall clock, so `--quick` between edits is not
much cheaper than a full run.

To narrow *how much code* the checks run over:

```bash
mix quality --test-scope changed        # only the tests covering your edits
mix quality --until-first-failure       # stop at the first thing to fix
```

`--test-scope changed` maps the files you have changed, committed or not, to the
test files covering them (`lib/foo/bar.ex` to `test/foo/bar_test.exs`; in an
umbrella, under the same app). The Tests line says what it ran:

```
✓ Tests: 12 of 12 passed (scope changed, 3 files vs origin/main, no coverage) (2.8s)
```

A scope that resolves to no test files runs the whole suite rather than reporting
a green run of nothing, and says so instead of quietly passing:

```
✓ Tests: 4,180 of 4,180 passed (scope changed fell back to the full suite: no test files map to the changed files)
```

**A scoped green is not a full green.** Coverage is not measured, and Dialyzer
still sees the whole project. Run a full `mix quality` before reporting work
complete, and never treat a scoped run as the final check.

With `--until-first-failure` the stages after the failure are reported as
`○ Tests: skipped (--until-first-failure)`. Those are not missing checks and not
something to report to the user - they are checks this run deliberately did not
pay for. Fix the failure and run again.

If the project's `.quality.exs` declares `profiles:`, use the one it names
instead of assembling flags yourself:

```bash
mix quality --profile loop
```

An unknown profile name fails the run rather than silently running everything, so
a name that works is a name the project chose.

## Never truncate the output

```bash
mix quality                        # correct
mix quality --quick                # correct
mix quality --test-scope changed   # correct

mix quality | tail -50   # wrong
mix quality 2>&1 | head  # wrong
mix quality | grep ✗     # wrong
```

The output is already the minimum needed to act: a passing stage costs one
line, and detail is printed only for failures. Truncating it removes findings,
not noise, and the findings are the reason to run the command.

## Reading the output

Four line shapes:

| Line | Meaning |
|---|---|
| `✓ Credo: No issues (775ms)` | passed; nothing to do |
| `✗ Credo: 5 issues (2 readability, 3 design)` | failed; detail printed below the summary block |
| `○ Dialyzer: skipped (--quick)` | did not run, with the reason |
| `⋯ Dialyzer: building PLT (this is a one-time cost)` | in progress; a multi-minute wait, not a hang |

Every stage the run considered is reported, skipped ones included. A stage you
do not see was not silently fine - it was not considered at all.

**Read the `○` lines.** `○ Credo: skipped (:credo not installed)` means the
project has no static analysis, and a green run proves less than it looks like
it does. That is worth telling the user, not passing over.

The reason distinguishes the two kinds. `:credo not installed` or `disabled in
.quality.exs` is a gap in what the project checks at all. `--quick`,
`not in profile :loop` and `--until-first-failure` are gaps in *this* run,
because you asked for a narrower one; a full `mix quality` closes them. In a
JSON report the distinction is structural: each skipped stage carries
`skip_kind: "project"` or `skip_kind: "run"`, so read the field rather than
the sentence.

Failures print below the summary, grouped by file:

```
────────────────────────────────────────────────────────────
Credo - FAILED
────────────────────────────────────────────────────────────
lib/user.ex
  42:3  [info] Modules should have a @moduledoc tag. (Credo.Check.Readability.ModuleDoc)
```

Read the named file at the named line and fix it there. Do not re-run the
underlying tool to get detail that is already on screen.

## Fixing what each stage reports

| Stage | The finding is | Fix by |
|---|---|---|
| Format | `mix format` failed, usually a syntax error | fixing the syntax; formatting itself is automatic |
| Compile | a compiler error or warning | fixing it at `file:line`; nothing downstream ran, so expect more after |
| Credo | a check module and its message | addressing it at `file:line`, or configuring the check in `.credo.exs` if it is genuinely wrong for the project |
| Dialyzer | a warning name (`no_return`, `pattern_match`) plus dialyxir's explanation | correcting the type or the code; a spec that contradicts the code is the code's problem more often than the spec's |
| Dependencies | an unused dep, or an advisory with the version that fixes it | `mix deps.unlock <pkg>` for unused; upgrading to the patched version for an advisory |
| Doctor | documentation coverage below the project's threshold | writing the missing `@moduledoc`/`@doc` |
| Gettext | missing or fuzzy translations | translating them, or resolving the fuzzy entries |
| any stage | `mix <task> is aliased in mix.exs` | renaming the alias, see below |
| a custom stage | whatever the project's own check reports | fixing it at `file:line`; the check is the project's, so ask before changing what it enforces |
| Sobelow | a security finding at or above the blocking threshold | fixing it at `file:line` |
| Tests | a test failure, or modules under the coverage threshold | fixing the code, or writing tests for the named modules |

Coverage failures name the modules that are under the threshold. Write tests
for those modules. Do not test unrelated code to raise the average.

## Mix aliases

ExQuality shells out to the real `mix credo`, `mix dialyzer`, `mix format`,
`mix sobelow`, `mix deps.unlock` and `mix test.coverage`. Mix resolves aliases
before tasks, so a `mix.exs` alias with one of those names changes what is
measured, silently.

Do not add an alias with one of those names. If the project already has one,
the stage says so and refuses to run; rename the alias (`sobelow.all` is the
usual choice) and update the scripts that call it.

`test` is the exception. An alias like
`test: ["ecto.create --quiet", "ecto.migrate", "test"]` is correct and
supported: it does the setup the suite needs.

## Never do these

These make a run go green without making the code better, which is worse than
a red run because it removes the signal:

- **Do not lower a coverage threshold.** It lives in `coveralls.json` or
  `test_coverage`, and changing it is a decision for a human.
- **Do not edit `.sobelow-conf`** to add an `ignore` or lower `exit:`. Silencing
  a security finding is a security decision, not a fix.
- **Do not add `--skip-*` or `--skip <key>` flags, or `enabled: false` in
  `.quality.exs`**, to get past a failing stage.
- **Do not convert a failing check into a custom stage in order to skip it.**
  Moving a check somewhere it can be turned off is not fixing it.
- **Do not use a custom stage to re-run a built-in tool with different flags.**
  Its output comes back as text instead of per-check findings, which is the
  routing the JSON report exists for. If a built-in stage cannot express
  something its tool supports, that is a bug in the stage - report it.
- **Do not delete, skip, or `@tag :skip` a failing test** to make the suite
  pass.
- **Do not weaken a check** (`credo: [strict: false]`,
  `compile: [warnings_as_errors: false]`) in response to it failing.
- **Do not use `--test-scope` or a profile to get past a failing stage**, and do
  not report work complete on a scoped run. Narrowing scope is for iterating, not
  for the final check.

If a finding really is wrong for this project, say so and let the user decide.
Report the failure rather than removing the thing that reported it.

## Routing on the result

The exit code says the run failed, not what failed. When you need to act on
specific stages programmatically, read a report instead of parsing the console:

```bash
mix quality --report .quality.json   # human output on stdout, report to a file
mix quality --format json            # report on stdout, human output on stderr
mix quality --report -               # the same as --format json
```

The root of the report says how much the run covered:

```json
{"status": "ok", "profile": "loop", "scope": "changed", "base_ref": "origin/main"}
```

`scope` is `"all"` for a full run. **Check it before treating a green run as
evidence about the whole project**, and never lower a recorded coverage number or
move a baseline on a run whose `scope` is not `"all"` - a scoped run does not
measure coverage at all, and the Tests stage reports `"coverage": "skipped"`
rather than a number.

Every stage carries the same keys whatever its status:

```json
{
  "name": "Credo",
  "status": "ok | error | skipped",
  "summary": "5 issues (2 readability, 3 design)",
  "stats": {"issue_count": 5},
  "findings": [
    {
      "file": "lib/user.ex", "line": 42, "column": 3,
      "app": "web", "severity": "info",
      "check": "Credo.Check.Readability.ModuleDoc",
      "message": "Modules should have a @moduledoc tag."
    }
  ],
  "duration_ms": 412
}
```

A skipped stage puts its reason in `summary`. A stage that failed without
parseable findings carries its tool's output under `output` instead; for a
failure, one of the two is always present.

A project can add stages of its own, so `name` is not one of a fixed set. Route
on `status` and `findings`; treat `name` as a label.

## Attesting a full gate

When you are about to write "gate green" somewhere a person will rely on it -
a PR description, a commit message, a ticket - and nobody watched the run, use
`mix quality.verify` instead of reading `mix quality`'s exit code. It runs the
gate and then checks that what ran was the full one: no profile, scope `all`,
no quick mode, no stage skipped for a run-level reason, coverage measured when
the project measures it. It exits non-zero and names every reason when the run
was narrower than that, and on success it also names what the project never
checks at all, which is worth passing on to the user.

Do not weaken anything to make it attest. The attestation failing means the
run was narrowed; run the full `mix quality.verify` with no flags.

## Configuration

`.quality.exs` at the project root, read before you change it:

```elixir
[
  credo: [strict: true],
  dialyzer: [enabled: false],
  test: [args: ["--only", "integration"]],
  profiles: [loop: [stages: [:format, :compile, :credo], test: [scope: :changed]]]
]
```

Test arguments also go after `--`: `mix quality -- --seed 0`. That is also how to
bound a failing suite while iterating:
`mix quality --test-scope changed -- --max-failures 3`.

If the file declares `profiles:`, those names are the project's answer to "what
should I run while iterating". Use them rather than inventing a flag combination,
and do not add or edit one to make a run pass.

Coverage and security thresholds are deliberately not configurable here. They
are read from the tool that owns them, so there is one place to change what
"passing" means. See `docs/configuration.md` and `docs/stages.md`.

## Dialyzer is slow

The first run builds a PLT, which takes minutes. That is expected, it is
reported while it happens, and `PLT built this run` in the summary is a normal
pass. Run `mix quality.plt` once on a fresh checkout to get it out of the way,
or `mix quality --quick` while iterating. Do not disable Dialyzer to avoid the
wait.
