# ExQuality - Usage Rules for LLM Assistants

## Overview

ExQuality is a parallel code quality checker for Elixir that runs format, compile, credo, dialyzer, dependency checks, and tests concurrently. Stages are auto-enabled based on installed dependencies (e.g., credo, dialyxir, doctor, gettext, mix_audit, excoveralls).

## Core Commands

### Quick mode (development)
```bash
mix quality --quick
```
- **Use during**: Active development, frequent changes, implementing features
- **Runs**: format, compile (dev+test), credo, dependencies, tests, doctor/gettext
- **Skips**: dialyzer (slow), coverage enforcement

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

## Configuration

Stages can be configured in `.quality.exs` (e.g., `[dialyzer: [enabled: false], credo: [strict: false]]`).

## Important: Do Not Truncate Output

Do not pipe `mix quality` output through `tail`, `head`, or any truncation. The tool already captures and manages output to present only the minimal result needed. Truncating may hide critical failure details, file:line references, and summary information.

```bash
# Correct
mix quality
mix quality --quick

# Wrong - do not truncate
mix quality | tail -50
mix quality 2>&1 | tail -100
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
