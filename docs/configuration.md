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
mix quality --verbose             # print full output even for stages that passed
mix quality --report PATH         # also write a JSON report to PATH
mix quality --format json         # JSON report on stdout, human output on stderr
```

Flags combine: `mix quality --quick --skip-credo`.

A skipped stage is still reported, with the flag as its reason:

```
○ Credo: skipped (--skip-credo)
```

## `.quality.exs`

A keyword list at the project root. Every key is optional.

```elixir
[
  # Global
  quick: false,

  compile: [
    warnings_as_errors: true
  ],

  credo: [
    enabled: :auto,
    strict: true,
    all: false
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
