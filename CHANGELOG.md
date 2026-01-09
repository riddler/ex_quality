# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- **BREAKING**: Package renamed from `quality` to `ex_quality`
- **BREAKING**: Module namespace changed from `Quality` to `ExQuality`
- Mix task name remains `mix quality` (unchanged)
- GitHub repository URL updated to `https://github.com/riddler/ex_quality`

### Migration Guide

If you were using an earlier version:

1. Update your `mix.exs` dependency:
   ```elixir
   # Old
   {:quality, "~> 0.1.0", only: :dev, runtime: false}

   # New
   {:ex_quality, "~> 0.1.0", only: :dev, runtime: false}
   ```

2. Update any direct module references (if any):
   ```elixir
   # Old
   Quality.Config.load()

   # New
   ExQuality.Config.load()
   ```

3. Mix task usage remains the same:
   ```bash
   mix quality          # Still works!
   mix quality --quick  # Still works!
   ```

## [0.1.0] - 2026-01-09

### Added

- Initial release of ExQuality (formerly Quality)
- **Three-phase execution pipeline:**
  - Phase 1: Auto-fix (format)
  - Phase 2: Compilation (dev + test in parallel)
  - Phase 3: Parallel analysis with streaming output
- **Quality stages:**
  - Format: Auto-fixes code formatting with `mix format`
  - Compile: Compiles dev + test environments in parallel with warnings as errors
  - Credo: Static analysis with `--strict` mode (configurable)
  - Dialyzer: Type checking with graceful PLT handling
  - Doctor: Documentation coverage checking
  - Gettext: Translation completeness validation
  - Test: Test suite with optional coverage via excoveralls
- **Quick mode** (`--quick`):
  - Skips dialyzer (slow type checking)
  - Skips coverage enforcement (tests run, % not checked)
  - Perfect for rapid iteration during development
- **Auto-detection system:**
  - Automatically enables stages based on installed dependencies
  - No configuration needed for standard setups
- **Configuration system:**
  - 4-tier precedence: Defaults → Auto-detection → `.quality.exs` → CLI flags
  - Project-level customization via `.quality.exs`
  - Per-stage enable/disable controls
  - CLI flags for runtime overrides
- **Streaming output:**
  - Results display as each stage completes
  - No interleaving (serialized via `Quality.Printer`)
  - Fast stages provide immediate feedback
- **Actionable feedback:**
  - Full tool output preserved in failure details
  - File:line references for easy navigation
  - Works for both humans and LLM coding assistants
- **CLI options:**
  - `--quick` - Fast mode for iterative development
  - `--skip-dialyzer` - Skip Dialyzer type checking
  - `--skip-credo` - Skip Credo static analysis
  - `--skip-doctor` - Skip Doctor documentation checks
  - `--skip-gettext` - Skip Gettext translation checks
  - `--verbose` - Show full output even on success
- **Documentation:**
  - Comprehensive README with workflow examples
  - `usage-rules.md` for LLM integration
  - Example `.quality.exs` configuration file
- **Coverage threshold:**
  - Single source of truth (reads from coveralls config)
  - Respects `coveralls.json` or `mix.exs` settings
  - No duplicate configuration needed

### Technical Details

- Zero runtime dependencies
- Optional dev dependencies: credo, dialyxir, doctor, excoveralls, gettext
- Parallel execution using Elixir Tasks
- Agent-based output serialization (ExQuality.Printer)
- Collectable protocol for silent output capture (ExQuality.OutputCollector)
- Tool detection via dependency scanning (ExQuality.Tools)
- Deep-merge configuration system (ExQuality.Config)

### Philosophy

ExQuality is designed for rapid, iterative development with confidence:
1. Fast feedback loop with `--quick` mode
2. Comprehensive verification with full mode
3. Actionable output with file:line references
4. Zero configuration required (works out of the box)
5. Progressive enhancement (add tools as needed)

[Unreleased]: https://github.com/riddler/ex_quality/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/riddler/ex_quality/releases/tag/v0.1.0
