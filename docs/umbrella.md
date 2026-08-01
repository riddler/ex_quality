# Umbrella projects

An umbrella is not a single project with more files in it. Detection, findings,
coverage and Sobelow all behave differently, and each difference exists because
the naive behaviour was wrong in a way that looked like a pass.

## Tool detection

An umbrella root's `mix.exs` usually declares no dependencies. Reading only the
root reports credo, dialyzer and everything else as not installed, and a run
that checks almost nothing passes.

ExQuality unions the root's dependencies with every child app's. A tool
declared in one app enables its stage for the run.

## Findings

Findings carry the app their file belongs to, and rendered output is grouped by
app, so a finding is attributable without reading the path:

```
web
  lib/web/user_controller.ex
    42:3  [info] Modules should have a @moduledoc tag. (Credo.Check.Readability.ModuleDoc)
```

In the JSON report this is the finding's `app` field. See
[reports.md](reports.md).

## Tests

Test statistics are summed across every app, rather than the first app's
numbers being reported as the whole suite's. A failure names the apps the
failures came from:

```
✗ Tests: 3 of 4,180 failed (web: 3)
```

## Coverage

A per-app `mix test --cover` only sees its own app's modules, so a module
exercised by another app's tests reads as 0%.

With Elixir's built-in coverage, ExQuality runs `mix test --cover
--export-coverage default` and then `mix test.coverage` to aggregate, which
gives one table and one suite-wide total.

With excoveralls, every `[TOTAL]` line is read. When apps are measured
separately, the lowest leads and the per-app numbers are reported alongside it.

## Sobelow

`mix sobelow` at an umbrella root finds nothing to scan. ExQuality runs it once
per child app that uses Phoenix, and tags each finding with the app it came
from.

## Configuration

`.quality.exs` is read from the project root. An umbrella child with no file of
its own reads the umbrella root's.
