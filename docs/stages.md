# Stages

What each stage runs, what it reports, and where its threshold comes from.

A run has three phases. **Format** fixes what it can. **Compile** gates the
rest: analysing code that does not build wastes the wait. Everything else runs
in parallel and prints as it finishes.

## Format

Runs `mix format`, having first checked with `--check-formatted` so it can
report how many files it changed.

```
✓ Format: Formatted 3 files (0.2s)
✓ Format: No changes needed (458ms)
```

A project with no `.formatter.exs` is reported as skipped rather than failed:
it never had the config file, so there is nothing to enforce. A `mix format`
that fails - a syntax error, say - is reported as a failure, not as a green
tick over a file that could not be parsed.

## Compile

Compiles dev and test in parallel, with `--warnings-as-errors` by default.

```
✓ Compile: dev + test compiled (warnings as errors) (325ms)
✗ Compile: dev compilation failed
```

A failure here stops the run. The analysis stages that were never reached are
reported as skipped, with `compile failed` as the reason, so they do not read
as stages that passed.

Set `compile: [warnings_as_errors: false]` to allow warnings.

## Credo

Runs `mix credo --format json`, so an issue is never dropped for having an
unfamiliar line shape.

```
✓ Credo: No issues (775ms)
✗ Credo: 5 issues (2 readability, 3 design) (0.4s)
```

Each issue becomes a finding naming the check that produced it:

```
lib/user.ex
  42:3  [info] Modules should have a @moduledoc tag. (Credo.Check.Readability.ModuleDoc)
```

`credo: [strict: true]` is the default. Configure credo itself in `.credo.exs`.

### More than one config

A `.credo.exs` can declare several configs, and a check that lives in a second
one does not run under the default. That happens when a set of files sits
outside credo's default `files.included` - migrations are the usual case -
because folding them into the default config would subject them to the whole
default check set.

```elixir
credo: [configs: ["default", "migrations"]]
```

Each name is one `mix credo` invocation, in the order given, and the results
merge into a single stage result. Findings are deduplicated on file, line,
column and check, so two configs with overlapping `files` globs do not double
a count. A run that fails without reporting issues names the config it came
from, because the likeliest cause is a name `.credo.exs` does not define:

```
✗ Credo: Check failed in "migrations" (see output)
```

The runs are serial. `mix credo` can compile, and two concurrent mix runs
against the same `_build` is exactly what the writer/reader split exists to
prevent. The stage as a whole still runs in parallel with the other analysis
stages.

Without `configs`, one run happens with no `--config-name`, which is credo's
own default.

## Dialyzer

Runs `mix dialyzer --no-compile --format short --format dialyxir`. The short
form of each warning becomes a finding naming the warning (`no_return`,
`pattern_match`); dialyxir's long explanation is kept alongside it, in the
stage's output and in the JSON report.

```
✓ Dialyzer: No warnings (32.1s)
✗ Dialyzer: 2 warnings (12.4s)
```

Dialyzer analyses against a PLT, a cache of every module it has already seen.
Building one takes minutes, analysing against a warm one takes seconds. A run
that has to build it says so while it happens, rather than looking hung:

```
⋯ Dialyzer: building PLT (this is a one-time cost)
✓ Dialyzer: No warnings (PLT built this run) (252.4s)
```

`mix quality.plt` builds it outside a run, so a container image or CI job can
cache it. See [ci.md](ci.md). `--quick` skips this stage.

## Dependencies

Two checks in one stage. `mix deps.unlock --check-unused` always; and
`mix deps.audit --format json` when `:mix_audit` is installed.

```
✓ Dependencies: No unused dependencies (0.3s)
✗ Dependencies: 1 vulnerability (1 moderate) (2.5s)
```

Each vulnerability becomes a finding against the lockfile, naming the advisory,
the version in use and the version that fixes it. Unused dependencies become
findings too.

```
mix.lock
  -  [error] decimal 2.3.0: Unbounded exponent in `Decimal.new` enables
     unauthenticated DoS (moderate severity, patched in 3.0.0) (GHSA-rhv4-8758-jx7v)
```

## Doctor

Runs `mix doctor`, which enforces the documentation coverage thresholds in the
project's `.doctor.exs`.

```
✓ Doctor: Passed (519ms)
✗ Doctor: Documentation coverage below threshold
```

`doctor: [summary_only: true]` prints only the summary.

## Gettext

Reads the project's `.po` files for untranslated and fuzzy entries, under every
umbrella child app as well as the root, and reports each one at its `msgid`.

```
✓ Gettext: All translations complete (12 files) (30ms)
✗ Gettext: 4 missing, 2 fuzzy translations
○ Gettext: skipped (no .po files found)
```

Files in the source locale are not checked, because the source locale is
untranslated by definition. It is `"en"` unless `gettext: [source_locale: ...]`
says otherwise, and `errors.po` is excluded for the same reason. A run left
with nothing to read reports itself as skipped rather than complete.

This stage does not run `mix gettext.extract --merge`. That task writes: it
rewrites `.pot` and `.po` files, and it compiles the project to do it, which
changes the build the other stages are reading. `gettext: [extract: true]` opts
back in, and the run then serialises the stage rather than running it alongside
the readers.

No other stage can write to your repository.

## Custom stages

A project's own check runs as a stage rather than beside it, declared under
`custom:` in `.quality.exs`. It prints, times and reports like a built-in one:

```
✓ Nullability: No unsound claims (1.1s)
✗ Nullability: 2 unsound claims (0.9s)
○ Nullability: skipped (--skip nullability)
```

The entry forms, the option table and the validation rules are in
[configuration.md](configuration.md#custom-stages). Two things belong here.

### The reader/writer declaration is load-bearing

The analysis phase runs its stages concurrently, and that is only safe while
every one of them is a reader. A command that recompiles the project rewrites
the beams the other stages are part-way through reading, and the stage that
notices reports a failure about the build rather than about the code.

`kind: :reader` is the default, because most custom checks read source or query
a database. **If your command compiles, generates, or writes anything under
`_build` or the repository, declare `kind: :writer`.** A writer runs on its
own, before the readers, the same way the Compile stage is a serialized gate.

`MIX_ENV=test mix <task>` is normally still a reader here, because the Compile
stage has already built dev and test before the analysis phase starts. That is
the most common shape a custom command takes and it looks like a writer, which
is why it is worth saying.

### The JSON finding contract

A command that wants per-finding routing rather than a wall of text prints one
JSON document on stdout:

```json
{
  "summary": "2 unsound claims",
  "stats": {"finding_count": 2},
  "findings": [
    {
      "file": "apps/walt_ui/lib/walt_ui/contacts/contact.ex",
      "line": 14,
      "column": null,
      "app": "walt_ui",
      "severity": "error",
      "check": "unsound",
      "message": "field :email is typed non-nil but the column is nullable"
    }
  ]
}
```

Only `file` and `message` are required per finding. `app` may be omitted and is
inferred from the path. `severity` is `error`, `warning` or `info`. `summary`
and `stats` are optional; without them the stage counts its own findings.

Anything that does not parse falls through to `output` verbatim, which is the
rule the printer and the report already follow everywhere else. `parse: :none`
skips the attempt for a command known to print prose, so a tool that happens to
emit JSON for some other reason is not misread.

### Not applicable

A custom check often has a prerequisite ExQuality cannot know about: a migrated
test database, a running service, a generated file. Without a way to say "not
applicable" the stage fails with an error that reads like a code problem.

`skip_exit_code: 2` lets the command exit 2 and have the stage report itself as
skipped, with the command's own first line as the reason:

```
○ Nullability: skipped (test database is not migrated)
```

Which keeps the invariant a run depends on: a stage that says nothing would
read as a stage that passed.

## Aliased tasks

ExQuality shells out to the real `mix credo`, `mix dialyzer`, `mix format`,
`mix sobelow`, `mix deps.unlock` and `mix test.coverage`, and reads what they
print. Mix resolves aliases before tasks, so a project that defines an alias
with one of those names silently changes what the stage measures.

A stage checks before shelling out, and refuses rather than reporting a number
about a command it did not issue:

```
✗ Format: mix format is aliased in mix.exs
✗ Sobelow: mix sobelow is aliased in mix.exs
```

Rename the alias (`sobelow.all` is the usual choice) and point your own scripts
at the new name.

`mix test` is the deliberate exception: a `test:` alias that runs migrations
first is near-universal, and running it is what the suite needs.

## Sobelow

Runs `mix sobelow` on a Phoenix project.

Sobelow reports findings at three confidence levels, but only those at or above
the project's `exit:` threshold block a build. ExQuality renders those and
reports the rest as a count:

```
✗ Sobelow: 2 blocking findings (1 high, 1 medium), 3 informational not shown
```

The threshold comes from `.sobelow-conf` when that file sets one, because what
blocks a build is a security decision that belongs with the security config.
`sobelow: [exit: "high"]` in `.quality.exs` only supplies a default for a
project without one; the default when neither says is `"medium"`.

Pass `--verbose`, or set `sobelow: [show_informational: true]`, to render the
findings below the threshold as well.

ExQuality will never suggest editing `.sobelow-conf` to make a run pass. A tool
that silences its own findings to go green is a regression dressed as a pass.

## Tests

Runs `mix test`, or `mix coveralls` when coverage is being measured.

```
✓ Tests: 345 of 345 passed (4.1s)
✓ Tests: 248 passed, 87.3% coverage (5.2s)
✗ Tests: 3 of 4,180 failed (web: 3)
```

Extra arguments reach the test command via `--` or `test: [args: [...]]`. See
[configuration.md](configuration.md).

## Coverage

Coverage is part of the Tests stage, and `--quick` turns it off.

**The threshold is not configured in ExQuality.** It is read from whichever
coverage tool the project already uses, so there is one source of truth:

| Tool | Threshold read from |
|---|---|
| `:excoveralls` (`mix coveralls`) | `coveralls.json` → `coverage_options.minimum_coverage`, or `mix.exs` → `test_coverage: [minimum_coverage: 80.0]` |
| Elixir's own (`mix test --cover`) | `mix.exs` → `test_coverage: [summary: [threshold: 90]]` |

Without excoveralls, coverage is measured only when the project states a
threshold that way. Elixir applies a default of 90% whether or not a project
has ever thought about coverage, and ExQuality will not turn a green run red
over a number nobody chose. To measure anyway:

```elixir
# .quality.exs
test: [coverage: true]   # or false to never measure
```

When the threshold is missed, the modules under it are reported as findings,
rather than the whole per-module table:

```
✗ Tests: Coverage 62.5% (required: 90.0%)

lib/my_app/mailer.ex
  -  [error] MyApp.Mailer is 0.0% covered (threshold 90.0%)
lib/my_app/thing.ex
  -  [error] MyApp.Thing is 33.3% covered (threshold 90.0%)
```

Lowering the threshold to make a run pass is a decision for a human, not a fix.
