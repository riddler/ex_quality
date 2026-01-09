# Quality - Usage Rules for LLM Assistants

## Overview

Quality is a parallel code quality checker for Elixir. When working in Elixir projects that use Quality, follow these guidelines to help users maintain code quality efficiently.

## Core Workflow

### During Active Development (Fast Iteration)

```bash
mix quality --quick
```

**When to recommend `--quick`:**
- User is actively implementing features
- User is making frequent code changes
- User wants fast feedback (< 5 seconds typically)
- Tests aren't complete yet
- Coverage threshold will fail but tests pass

**What `--quick` does:**
- ✅ Runs format (auto-fixes)
- ✅ Runs compilation (both dev + test)
- ✅ Runs credo
- ✅ Runs tests (must pass)
- ✅ Runs doctor/gettext if available
- ❌ Skips dialyzer (slow)
- ❌ Skips coverage enforcement (tests run, % not checked)

### Before Committing (Full Verification)

```bash
mix quality
```

**When to recommend full mode:**
- User is ready to commit
- User is opening a pull request
- User asks to "verify everything"
- In CI/CD pipelines

**What full mode does:**
- ✅ Runs everything including dialyzer and coverage

## Common Scenarios

### Scenario 1: User implements new feature

```
User: "I've added a new user registration feature"
LLM: "Great! Let's verify it with quick mode for fast feedback:
      mix quality --quick

      Then once everything passes and you're ready to commit, run:
      mix quality"
```

### Scenario 2: Quality check fails

When quality reports failures, the output includes file:line references. Use these to:

1. **Locate the issue** - Show the file and line number
2. **Explain the problem** - Interpret what the tool is reporting
3. **Suggest fix** - Provide code changes with context
4. **Re-run** - Recommend `mix quality --quick` after fix

Example output from Quality:
```
✗ Credo: 5 issue(s) (1 refactoring, 2 readability, 2 design) (0.4s)

────────────────────────────────────────────────────────────
Credo - FAILED
────────────────────────────────────────────────────────────
┃ [R] ↗ Predicate function names should not start with 'is'...
┃       lib/quality/stages/dialyzer.ex:92:8
```

**Your response should:**
- Read the file at the line mentioned
- Explain why it's an issue
- Suggest the fix
- Offer to make the change

### Scenario 3: User wants faster checks

```
User: "Quality is taking too long"
LLM: "You can use quick mode during development:
      mix quality --quick

      Or skip specific slow checks:
      mix quality --skip-dialyzer

      Or disable stages in .quality.exs:
      [dialyzer: [enabled: false]]"
```

### Scenario 4: Tests incomplete

```
User: "I haven't written all tests yet"
LLM: "Use quick mode while developing:
      mix quality --quick

      This runs your tests but doesn't enforce coverage thresholds.
      Once tests are complete, run:
      mix quality"
```

## Configuration

### When to create `.quality.exs`

Suggest creating `.quality.exs` when user:
- Wants to permanently disable a stage
- Finds credo too strict
- Wants to customize tool behavior
- Has project-specific requirements

### Example configurations

**Disable dialyzer project-wide:**
```elixir
[
  dialyzer: [enabled: false]
]
```

**Make credo less strict:**
```elixir
[
  credo: [strict: false]
]
```

**Doctor summary only:**
```elixir
[
  doctor: [summary_only: true]
]
```

## Integration with Development Workflow

### Recommended workflow

1. **Make changes** - User modifies code
2. **Quick check** - Run `mix quality --quick` for fast feedback
3. **Fix issues** - Address any failures
4. **Repeat** - Continue development cycle
5. **Full verification** - Run `mix quality` before committing
6. **Commit** - Once everything passes

### When writing code

**DO:**
- Suggest `mix quality --quick` after making changes
- Run it before claiming implementation is complete
- Check output for file:line references to fix issues
- Use it as a fast feedback loop

**DON'T:**
- Run full `mix quality` during rapid iteration (too slow)
- Ignore quality check failures
- Disable all checks (defeats the purpose)
- Forget to run full `mix quality` before committing

## Auto-Detection

Quality automatically enables stages based on dependencies. **You don't need to configure anything.**

| Tool | Dep Required | Behavior |
|------|-------------|----------|
| Credo | `:credo` | Auto-enabled if present |
| Dialyzer | `:dialyxir` | Auto-enabled if present |
| Doctor | `:doctor` | Auto-enabled if present |
| Gettext | `:gettext` | Auto-enabled if present |
| Coverage | `:excoveralls` | Uses coveralls if present, else plain tests |

**When suggesting dependencies**, mention that Quality will auto-detect and use them.

## Interpreting Output

### Success output
```
✓ Format: No changes needed (0.1s)
✓ Compile: dev + test compiled (warnings as errors) (1.8s)
✓ Credo: No issues (1.2s)
✓ Tests: 248 passed, 0 failed, 87.3% coverage (5.2s)

✅ All quality checks passed!
```
All checks passed, safe to commit.

### Failure output
```
✗ Credo: 5 issue(s) (1 refactoring, 2 readability, 2 design) (0.4s)

────────────────────────────────────────────────────────────
Credo - FAILED
────────────────────────────────────────────────────────────
[Full tool output with file:line references]
```

**How to help:**
1. Parse the file:line references
2. Read the affected files
3. Explain each issue
4. Suggest fixes
5. Offer to implement changes

### Streaming output behavior

Quality prints results as each stage completes:
```
✓ Doctor: 92% documented (0.4s)    ← finished first
✓ Credo: No issues (1.8s)           ← finished second
✓ Tests: 248 passed (5.2s)          ← finished third
✓ Dialyzer: No warnings (32.1s)     ← finished last
```

This means **fast checks give feedback immediately** - don't wait for slow checks.

## CLI Flags Reference

```bash
mix quality                    # Full verification
mix quality --quick            # Fast iteration mode
mix quality --skip-dialyzer    # Skip specific stage
mix quality --skip-credo       # Skip credo
mix quality --skip-doctor      # Skip doctor
mix quality --skip-gettext     # Skip gettext
```

Flags can be combined:
```bash
mix quality --quick --skip-credo
```

## Common Issues and Solutions

### "Dialyzer is slow"
```bash
# During development
mix quality --quick

# Or disable permanently
echo '[dialyzer: [enabled: false]]' > .quality.exs
```

### "Credo is too strict"
```elixir
# .quality.exs
[credo: [strict: false]]
```

### "Coverage is failing but tests pass"
```bash
# Use quick mode (tests run, coverage not enforced)
mix quality --quick
```

### "Need to skip all checks temporarily"
```bash
# Not recommended, but possible
mix quality --skip-credo --skip-dialyzer --skip-doctor --skip-gettext
# Or just run tests
mix test
```

## Best Practices for LLM Assistants

1. **Default to `--quick` during development** - It's faster and users appreciate it
2. **Suggest full mode before commits** - Ensures everything is verified
3. **Parse file:line references** - Use them to locate and fix issues
4. **Explain failures clearly** - Interpret tool output for users
5. **Offer to fix issues** - Don't just point them out
6. **Remember the workflow** - Quick for iteration, full for verification
7. **Respect auto-detection** - Don't suggest installing tools unless needed
8. **Use .quality.exs sparingly** - CLI flags are often sufficient

## Examples of Good Interactions

### Example 1: After code changes
```
User: "I updated the user controller"
LLM: "Great! Let's verify the changes:

     mix quality --quick

     [If issues found, explain and offer to fix]
     [If passed, suggest committing]"
```

### Example 2: Before PR
```
User: "Ready to open a PR"
LLM: "Let's run full quality checks first:

     mix quality

     This ensures everything passes including dialyzer and coverage."
```

### Example 3: Fixing issues
```
User: "Quality is failing"
LLM: [Reads quality output]
     "I see 3 credo issues:

     1. lib/user.ex:42 - Module missing @moduledoc
     2. lib/user.ex:58 - Function too complex
     3. lib/api.ex:15 - Nested modules should be aliased

     Let me fix these for you:
     [Shows fixes]

     After I apply these, run:
     mix quality --quick"
```

## Key Takeaway

**Quality enables a fast feedback loop during development (`--quick`) while ensuring comprehensive verification before commits (full mode).** Always recommend the right mode for the user's current phase of work.
