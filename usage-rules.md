# ExQuality - Usage Rules for LLM Assistants

## Overview

ExQuality is a parallel code quality checker for Elixir that runs format, compile, credo, dialyzer, dependency checks, and tests concurrently.

## First-time Setup

After adding `:ex_quality` to your dependencies:

```bash
# Interactive setup (recommended)
mix quality.init

# Use defaults without prompts
mix quality.init --skip-prompts

# Install all available tools
mix quality.init --all
```

This will:
- Detect which tools are already installed
- Prompt for which tools to add (credo, dialyzer, excoveralls recommended)
- Add dependencies to mix.exs with latest versions
- Run `mix deps.get` automatically
- Create tool configs (.credo.exs, coveralls.json, etc.)
- Create .quality.exs configuration file

**Available tools:**
- `credo` - Static code analysis
- `dialyzer` - Type checking (dialyxir)
- `coverage` - Test coverage (excoveralls)
- `doctor` - Documentation coverage
- `audit` - Security scanning (mix_audit)
- `gettext` - Internationalization

## Core Commands

### Quick mode (development)
```bash
mix quality --quick
```
- **Use during**: Active development, frequent changes, implementing features
- **Runs**: format, compile (dev+test), credo, dependencies, tests, doctor/gettext
- **Skips**: dialyzer (slow), coverage enforcement
- **Speed**: ~5 seconds typically

### Full mode (verification)
```bash
mix quality
```
- **Use before**: Commits, pull requests, CI/CD
- **Runs**: Everything including dialyzer and coverage enforcement

## CLI Flags

```bash
mix quality --quick               # Fast iteration mode
mix quality --skip-dialyzer       # Skip type checking
mix quality --skip-credo          # Skip static analysis
mix quality --skip-doctor         # Skip doc coverage
mix quality --skip-gettext        # Skip translation checks
mix quality --skip-dependencies   # Skip dependency checks
```

Flags can be combined: `mix quality --quick --skip-credo`

## Auto-Detection

ExQuality automatically enables stages based on installed dependencies:

- **Credo** - Auto-enabled if `:credo` installed
- **Dialyzer** - Auto-enabled if `:dialyxir` installed
- **Dependencies** - Always runs (unused deps check)
  - Security audit auto-enabled if `:mix_audit` installed
- **Doctor** - Auto-enabled if `:doctor` installed
- **Gettext** - Auto-enabled if `:gettext` installed
- **Coverage** - Uses `:excoveralls` if installed, else plain `mix test`

## Configuration

Create `.quality.exs` in project root:

```elixir
[
  # Disable specific stage
  dialyzer: [enabled: false],

  # Make credo less strict
  credo: [strict: false],

  # Configure dependencies
  dependencies: [
    check_unused: true,
    audit: false  # Skip security audit
  ]
]
```

## Working with ExQuality Output

### Success
```
✓ Format: No changes needed (0.1s)
✓ Compile: dev + test compiled (1.8s)
✓ Credo: No issues (1.2s)
✓ Dependencies: No unused dependencies (0.3s)
✓ Tests: 248 passed, 87.3% coverage (5.2s)

✅ All quality checks passed!
```

### Failures
When ExQuality fails, output includes **file:line references**:
- Parse file:line to locate issues
- Read affected files
- Explain what needs fixing
- Suggest/implement fixes
- Re-run `mix quality --quick`

Example failure:
```
✗ Credo: 5 issue(s) (0.4s)
────────────────────────────────────
lib/user.ex:42 - Module missing @moduledoc
lib/api.ex:58 - Function too complex
```

## Common Patterns

**After code changes:**
```
mix quality --quick  # Fast feedback
```

**Before committing:**
```
mix quality  # Full verification
```

**Dialyzer is slow:**
```elixir
# .quality.exs
[dialyzer: [enabled: false]]
```

**Coverage failing but tests pass:**
```bash
mix quality --quick  # Skips coverage enforcement
```

**Unused dependencies found:**
```bash
# ExQuality tells you which deps to remove
mix deps.unlock package_name
```

**Security vulnerabilities found:**
- Update affected packages to patched versions
- Follow recommendations in ExQuality output
