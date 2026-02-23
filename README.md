# ExQuality

A parallel code quality checker for Elixir projects that runs format, compile, credo, dialyzer, dependency checks, and tests concurrently with actionable feedback.

**Perfect for iterative development**: Use `mix quality --quick` during active coding, then `mix quality` for full verification before committing.

## Features

- **🚀 Fast iteration**: `--quick` mode skips slow checks (dialyzer, coverage) for rapid feedback
- **⚡ Parallel execution**: All checks run concurrently, maximizing CPU utilization
- **🔧 Auto-fix first**: Automatically fixes formatting before running analysis
- **📊 Streaming output**: See results as each stage completes, not after everything finishes
- **🎯 Actionable feedback**: Full tool output with file:line references for easy fixing
- **🤖 Auto-detection**: Automatically enables checks based on installed dependencies
- **⚙️ Configurable**: Customize via `.quality.exs` or CLI flags
- **🧠 LLM-friendly**: Includes `usage-rules.md` for AI coding assistants

## Quick Start

```elixir
# Add to mix.exs
def deps do
  [
    {:ex_quality, "~> 0.5", only: :dev, runtime: false}
  ]
end
```

```bash
# Install dependencies
mix deps.get

# Set up quality tools (interactive)
mix quality.init

# Or use defaults without prompts
mix quality.init --skip-prompts
```

This will:
1. Detect which tools are already installed
2. Prompt you to select additional tools (credo, dialyzer, excoveralls recommended)
3. Add dependencies to mix.exs
4. Run `mix deps.get`
5. Set up tool configurations (.credo.exs, coveralls.json, etc.)
6. Create .quality.exs for customization

Then run quality checks:

```bash
# During development - fast feedback
mix quality --quick

# Before committing - full verification
mix quality
```

## Workflow

### Iterative Development (Fast)

When you're actively coding and want quick feedback:

```bash
mix quality --quick
```

**Quick mode skips:**
- ❌ Dialyzer (type checking is slow)
- ❌ Coverage enforcement (tests run, but coverage % not checked)

**Quick mode runs:**
- ✅ Format (auto-fixes)
- ✅ Compilation (dev + test)
- ✅ Credo (static analysis)
- ✅ Dependencies (unused deps + security audit)
- ✅ Tests (must pass)
- ✅ Doctor (if installed)
- ✅ Gettext (if installed)

**Use this when**: Making frequent changes, implementing features, fixing bugs.

### Full Verification (Complete)

Before committing, pushing, or opening a PR:

```bash
mix quality
```

**Full mode runs everything:**
- ✅ Format
- ✅ Compilation
- ✅ Credo
- ✅ Dialyzer (comprehensive type checking)
- ✅ Dependencies (unused deps + security audit)
- ✅ Tests with coverage (enforces threshold)
- ✅ Doctor
- ✅ Gettext

**Use this when**: Ready to commit, opening PRs, in CI/CD.

## Execution Phases

ExQuality runs in three phases:

### Phase 1: Auto-fix
```
✓ Format: Formatted 3 files (0.2s)
```
Automatically fixes code formatting with `mix format`.

### Phase 2: Compilation (Blocking Gate)
```
✓ Compile: dev + test compiled (warnings as errors) (2.1s)
```
Compiles both dev and test environments in parallel. Must pass before analysis.

### Phase 3: Parallel Analysis (Streaming)
```
✓ Doctor: 92% documented (0.4s)              ← prints at 0.4s
✓ Credo: No issues (1.8s)                    ← prints at 1.8s
✓ Tests: 248 passed, 87.3% coverage (5.2s)   ← prints at 5.2s
✓ Dialyzer: No warnings (32.1s)              ← prints at 32.1s
```
All checks run concurrently. Results stream as each completes.

## CLI Options

```bash
# Quick mode for iterative development
mix quality --quick

# Skip specific stages
mix quality --skip-dialyzer
mix quality --skip-credo
mix quality --skip-doctor
mix quality --skip-gettext
mix quality --skip-dependencies

# Combine flags
mix quality --quick --skip-credo

# Pass options to mix test/coveralls (after --)
mix quality -- --only integration
mix quality --quick -- --include slow --seed 0
```

## Auto-Detection

ExQuality automatically enables stages based on installed dependencies:

| Stage | Requires | Auto-enabled? |
|-------|----------|---------------|
| Format | (none) | Always |
| Compile | (none) | Always |
| Credo | `:credo` | If installed |
| Dialyzer | `:dialyxir` | If installed |
| Dependencies | (none) / `:mix_audit` | Always (audit if installed) |
| Doctor | `:doctor` | If installed |
| Gettext | `:gettext` | If installed |
| Tests | (none) | Always |
| Coverage | `:excoveralls` | If installed |

**Example**: If you have credo and dialyxir in deps, ExQuality will run both automatically.

## Configuration

Create `.quality.exs` in your project root to customize behavior:

```elixir
[
  # Override auto-detection: force disable dialyzer
  dialyzer: [enabled: false],

  # Credo options
  credo: [
    strict: true,  # Use --strict mode (default: true)
    all: false     # Use --all flag (default: false)
  ],

  # Doctor options
  doctor: [
    summary_only: true  # Show only summary (default: false)
  ],

  # Dependencies options
  dependencies: [
    check_unused: true,  # Check for unused deps (default: true)
    audit: true          # Run security audit if mix_audit installed (default: :auto)
  ],

  # Test options - pass extra args to mix test/coveralls
  test: [
    args: ["--only", "integration"]  # e.g., --only, --include, --exclude, --seed
  ]
]
```

### Configuration Precedence

Configuration is merged in this order (later wins):

1. **Defaults** - Sensible built-in defaults
2. **Auto-detection** - Based on installed deps
3. **`.quality.exs`** - Project-specific config
4. **CLI flags** - Runtime overrides (highest priority)

**Example**: If `.quality.exs` disables dialyzer, but you run `mix quality` (no flags), dialyzer stays disabled. However, the auto-detection still marks it as "available" internally.

### Coverage Threshold

Coverage threshold is **NOT** configured in ExQuality. It reads from your existing excoveralls configuration:

- `coveralls.json` → `minimum_coverage` or `coverage_threshold`
- `mix.exs` → `test_coverage: [minimum_coverage: 80.0]`

This ensures a **single source of truth** for coverage requirements.

### Test Options

Pass extra arguments to `mix test` or `mix coveralls` using either method:

**Via CLI** (after `--` separator):
```bash
mix quality -- --only integration
mix quality --quick -- --include slow --seed 0
```

**Via `.quality.exs`**:
```elixir
[
  test: [
    args: ["--only", "integration"]
  ]
]
```

CLI args override config file args (no merge). This is useful for:
- Running only specific test tags: `--only integration`, `--exclude slow`
- Debugging with a specific seed: `--seed 12345`
- Including normally-excluded tests: `--include pending`

## Actionable Output

When checks fail, ExQuality shows the complete tool output with file:line references:

```bash
✗ Credo: 5 issue(s) (1 refactoring, 2 readability, 2 design) (0.4s)

────────────────────────────────────────────────────────────
Credo - FAILED
────────────────────────────────────────────────────────────
┃ [D] ↘ Nested modules could be aliased at the top of the invoking module.
┃       lib/mix/tasks/quality.ex:96:22 #(Mix.Tasks.Quality.run)
┃
┃ [R] ↗ Predicate function names should not start with 'is'...
┃       lib/ex_quality/stages/dialyzer.ex:92:8 #(ExQuality.Stages.Dialyzer.is_debug_info_error?)
```

**Why this matters:**
- Humans can click file:line in their editor
- LLMs can see exactly what needs fixing
- No need to run individual tools to get details

## Recommended Dependencies

For the best experience, add these to your `mix.exs`:

```elixir
def deps do
  [
    # Recommended quality tools
    {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
    {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
    {:excoveralls, "~> 0.18", only: :test},
    {:doctor, "~> 0.21", only: :dev, runtime: false},
    {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},

    # If you use translations
    {:gettext, "~> 0.24"},

    # Quality checker
    {:ex_quality, "~> 0.5", only: :dev, runtime: false}
  ]
end
```

## Integration

### In CI/CD

Run full quality checks in your CI pipeline:

```yaml
# GitHub Actions
- name: Run quality checks
  run: mix quality
```

**Note**: Dialyzer requires a PLT (Persistent Lookup Table). You may want to cache it:

```yaml
- name: Restore PLT cache
  uses: actions/cache@v3
  with:
    path: priv/plts
    key: ${{ runner.os }}-plt-${{ hashFiles('**/mix.lock') }}
```

### Pre-commit Hook

Add to `.git/hooks/pre-commit`:

```bash
#!/bin/sh
mix quality --quick
```

This gives you fast feedback before committing.

### In Your Development Workflow

**During feature development:**
```bash
# Make changes
vim lib/my_app/feature.ex

# Quick check (fast)
mix quality --quick

# Fix issues, repeat
```

**Before committing:**
```bash
# Full verification
mix quality

# If it passes, commit
git add .
git commit -m "Add feature"
```

## Comparison with Alternatives

| Feature | ExQuality | ex_check | al_check |
|---------|-----------|----------|----------|
| Parallel execution | ✅ | ✅ | ✅ |
| Streaming output | ✅ | ❌ | ❌ |
| Auto-fix first | ✅ | ✅ | ✅ |
| Auto-detect tools | ✅ | ✅ | ❌ |
| Quick mode | ✅ | ❌ | ✅ |
| LLM-friendly | ✅ | ❌ | ❌ |
| Config file | .quality.exs | .check.exs | alcheck.toml |
| Actionable output | ✅ Full tool output | ✅ | ✅ |

**ExQuality's differentiators:**
1. **Quick mode** - Fast iteration during development
2. **Streaming output** - See results as each check completes
3. **Auto-fix first** - Format code before analysis
4. **LLM integration** - Includes `usage-rules.md` for AI assistants

## Troubleshooting

### "Dialyzer is too slow"

Use quick mode during development:
```bash
mix quality --quick
```

Or disable it permanently in `.quality.exs`:
```elixir
[dialyzer: [enabled: false]]
```

### "Credo is too strict"

Adjust strictness in `.quality.exs`:
```elixir
[credo: [strict: false]]
```

Or create `.credo.exs` to configure credo directly.

### "I don't have doctor/gettext"

ExQuality auto-detects and skips them. No configuration needed.

### "Tests are failing"

ExQuality shows the full test output with file:line references. Look for the failure details in the output.

## Philosophy

**ExQuality is designed for rapid, iterative development with confidence.**

1. **Fast feedback loop**: `--quick` gives you sub-second feedback on most changes
2. **Comprehensive verification**: Full mode ensures everything is correct
3. **Actionable output**: See exactly what needs fixing, with file:line references
4. **Zero configuration**: Works out of the box with sensible defaults
5. **Progressive enhancement**: Add tools as you need them

## License

MIT

## Contributing

Issues and pull requests welcome at [https://github.com/riddler/ex_quality](https://github.com/riddler/ex_quality)
