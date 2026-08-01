# Configuration

ExQuality runs without configuration. Everything below is for overriding what
it decides on its own.

## Precedence

Four sources, merged in order, later wins:

1. **Defaults**
2. **Auto-detection** - a stage is available when the project depends on its tool
3. **`.quality.exs`** - read from the project root, not the working directory
4. **CLI flags**

Auto-detection only ever sets availability. A stage that is available can still
be turned off by `.quality.exs` or a flag, and one that is unavailable can be
forced on with `enabled: true` - which will fail if the tool really is missing.

## CLI flags

```bash
mix quality --quick               # skip dialyzer and coverage enforcement
mix quality --skip-credo          # skip static analysis
mix quality --skip-dialyzer       # skip type checking
mix quality --skip-doctor         # skip documentation coverage
mix quality --skip-gettext        # skip translation checks
mix quality --skip-sobelow        # skip security analysis
mix quality --skip-dependencies   # skip unused deps and the security audit
mix quality --skip KEY            # skip any stage by key; repeatable
mix quality --verbose             # print full output even for stages that passed
mix quality --report PATH         # also write a JSON report to PATH
mix quality --format json         # JSON report on stdout, human output on stderr
```

Flags combine: `mix quality --quick --skip-credo`.

A skipped stage is still reported, with the flag as its reason:

```
○ Credo: skipped (--skip-credo)
```

`--skip KEY` takes a stage key rather than being one switch per stage, so it
also reaches a custom stage, which has no `--skip-<key>` of its own. It is
repeatable, and it names itself as the reason:

```bash
mix quality --skip nullability --skip credo
```

```
○ Nullability: skipped (--skip nullability)
○ Credo: skipped (--skip credo)
```

## `.quality.exs`

A keyword list at the project root. Every key is optional.

```elixir
[
  # Global
  quick: false,

  compile: [
    warnings_as_errors: true,
    force: false
  ],

  credo: [
    enabled: :auto,
    strict: true,
    all: false,
    # Names of the .credo.exs configs to run, in order. nil is one run with no
    # --config-name, which is credo's own default. See docs/stages.md.
    configs: nil
  ],

  dialyzer: [
    enabled: :auto
  ],

  doctor: [
    enabled: :auto,
    summary_only: false
  ],

  gettext: [
    enabled: :auto,
    # The locale the source is written in, whose .po files are not checked.
    source_locale: "en",
    # Basenames to skip. Phoenix generates errors.po with empty entries.
    exclude: ["errors.po"],
    # Run `mix gettext.extract --merge` first. It writes to the repository and
    # recompiles the project, so the run serialises this stage when it is on.
    extract: false
  ],

  sobelow: [
    enabled: :auto,
    # Confidence level that blocks a run, used only when .sobelow-conf sets no
    # `exit:` of its own.
    exit: "medium",
    # Render the findings below that level as well as counting them.
    show_informational: false
  ],

  dependencies: [
    enabled: :auto,
    check_unused: true,
    audit: :auto
  ],

  test: [
    # :auto measures coverage when the project's own config asks for it.
    coverage: :auto,
    # Extra arguments for mix test / mix coveralls.
    args: []
  ]
]
```

### `enabled`

Every stage takes one of three values:

| Value | Meaning |
|---|---|
| `:auto` | run when the tool is installed (the default) |
| `true` | always run; errors if the tool is missing |
| `false` | never run; reported as `○ Credo: skipped (disabled in .quality.exs)` |

## Custom stages

A project's own check - a house rule, a schema linter, a custom mix task, a
shell script gate - runs as a stage of the run rather than beside it, declared
under `custom:`. It then has the same parallelism, timing, printer and JSON
report as a built-in stage, which is what lets a caller route its findings.

```elixir
custom: [
  # A command. This is the case most projects want.
  [
    key: :nullability,
    name: "Nullability",
    command: "mix",
    args: ["schema.nullability", "--format", "json"],
    env: [{"MIX_ENV", "test"}],
    kind: :reader
  ],

  # A module, for anything the command form cannot express.
  [key: :house_rules, name: "House rules", module: MyApp.Quality.HouseRules]
]
```

Every entry is a keyword list with `key` and `name`, plus either `module` or
`command`. Registration lives in the entry rather than in callbacks on a module
so the config file alone says what a run will contain: a stage that only
announces itself once it has run cannot be reported as skipped.

### Module entries

`module:` names a module exporting `run/1` and returning an
`ExQuality.Stage.result()` - the contract every built-in stage already
satisfies. It may also export `stage_kind/1`; a module that does not is a
reader.

### Command entries

| Key | Default | Meaning |
|---|---|---|
| `command`, `args` | required | passed to `System.cmd/3` |
| `env` | `[]` | extra environment |
| `cd` | project root | working directory |
| `kind` | `:reader` | `:writer` runs it serialized, ahead of the readers |
| `parse` | `:json` | `:json` attempts the finding contract, `:none` never tries |
| `skip_exit_code` | none | exit code meaning "not applicable" |
| `enabled` | `true` | `false` skips the stage, reported with the file as the reason |

Exit code 0 is a pass, anything else is a failure. The command runs with
`stderr_to_stdout: true`. The JSON finding contract, and the reader/writer
warning, are in [stages.md](stages.md#custom-stages).

A bare `command` is looked up on the PATH. One containing `/` is a path and is
expanded before it runs, so a project's own script can be named directly:

```elixir
[key: :schema, name: "Schema", command: "bin/checks/schema.sh"]
```

It is relative to `cd` when the entry names one and to the project root
otherwise, so the entry reads as the shell it looks like: `cd <cd> && <command>
<args>`. An absolute path is used as it stands.

### Validation

A malformed entry fails the run at load time and names itself, because a stage
that never registers is a check nobody is told is not running. The rules:

- `key` and `name` are both required.
- exactly one of `module` or `command`.
- `key` and `name` may not collide with a built-in stage. A custom stage
  shadowing Credo is the same class of bug as an aliased mix task.
- `key` must be unique across entries.
- `kind` must be `:reader` or `:writer`; `parse` must be `:json` or `:none`;
  `skip_exit_code` must be an integer.
- `module` must be loadable and export `run/1`.

### What custom stages are not for

Filling gaps in built-in stages. Routing a second `mix credo` config through a
custom command would work and would be a mistake: the output comes back as text
instead of per-check findings, and per-check routing is the reason the JSON
report exists. If a built-in stage cannot express something its tool supports,
that is a bug in the stage - `credo.configs` exists for exactly that reason.

Nor are they a way to get out from under a failing check. Converting a stage
into a custom one so it can be skipped moves the problem rather than fixing it.

## Test arguments

Extra arguments reach `mix test` or `mix coveralls` two ways. On the command
line, after `--`:

```bash
mix quality -- --only integration
mix quality --quick -- --include slow --seed 0
```

Or in `.quality.exs`:

```elixir
[test: [args: ["--only", "integration"]]]
```

CLI arguments replace the configured ones rather than merging with them.

## Thresholds are not configured here

Coverage and security thresholds are deliberately absent from `.quality.exs`.
They are read from the tool that owns them - `coveralls.json`, `test_coverage`
in `mix.exs`, `.sobelow-conf` - so a project has one place to change what
"passing" means, and changing it is visible as a change to that file. See
[stages.md](stages.md).
