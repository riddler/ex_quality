# Test Fixtures

This directory contains minimal Elixir projects used for integration testing of the ExQuality package.

## Purpose

These fixture projects allow us to test the `mix quality` command end-to-end without:
- Running into infinite recursion (where tests invoke themselves)
- Polluting the main test suite with fixture test files
- Needing to mock the entire Mix environment

## How They Work

Each fixture is a complete, minimal Mix project with:
- A `mix.exs` with ExQuality as a path dependency (`{:ex_quality, path: "..", ...}`)
- Source files in `lib/` that demonstrate specific scenarios
- Test files in `test/` appropriate to each scenario

During integration tests:
1. Fixtures are copied to `fixtures/tmp/` (gitignored)
2. Dependencies are installed with `mix deps.get`
3. `mix quality` is executed within the fixture
4. Exit codes and output are verified
5. Temp directories are cleaned up

## Fixtures

- **all_passing** - Clean project that passes all quality checks
- **format_needed** - Unformatted code to test auto-fix functionality
- **credo_issues** - Code with Credo violations (missing @moduledoc, TODO comments, deep nesting)
- **compile_error** - Code with compilation errors (undefined functions)
- **test_failures** - Code that compiles but has failing tests
- **with_config** - Project with a custom `.quality.exs` configuration file

## Running Manually

You can test any fixture manually:

```bash
cd fixtures/all_passing
mix deps.get
mix quality
```

## Adding New Fixtures

To add a new test scenario:

1. Create a new directory under `fixtures/`
2. Add a `mix.exs` with `{:ex_quality, path: "..", only: [:dev, :test], runtime: false}`
3. Create `lib/` and `test/` directories with your scenario code
4. Add a test case in `test/integration/quality_test.exs`

## Note

These fixtures are **not** run as part of the main test suite. They exist solely to be invoked by integration tests in `test/integration/quality_test.exs`.
