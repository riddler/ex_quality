# Why the gate is one command

An Elixir project's quality gate is usually several tools: the formatter, the
compiler with warnings as errors, Credo, Dialyzer, the test suite with a
coverage threshold, perhaps Doctor, Sobelow and a dependency audit. Each of
them already has a mix task. ExQuality puts them behind one, `mix quality`,
and this page is about why that is worth a dependency, what else could have
been done, and what the choice costs.

## The gate is a question about all the tools at once

The question a gate answers is "may this change go in?", and it is a question
about every tool together. Asked of the tools one at a time, the answer has to
be assembled by whoever is reading: one wall of text per tool, each in its own
format and at its own length, and nothing at all from a tool that did not
execute. A missing Dialyzer section and a passing Dialyzer section look the
same when nobody wrote either of them down.

One command lets the gate be reported as a single thing. Every stage the
command considered appears in its output, a passing stage costs one line, a
skipped stage says why it was skipped, and a failing stage prints findings
that carry a `file:line`. The shape is the same for every stage, so it can
also be written as one [JSON report](../reports.md) that a script routes on,
rather than one parser per tool. Absence stops being something a reader has
to infer, which is the property the rest of the design protects.

## Alternatives considered

**A mix alias that chains the tools.** This is the usual starting point and
costs nothing to add. It keeps every tool's own output, though, so the reader
is back to several formats in one stream; it executes the tools one after
another, so the slow ones add up; and a tool that an earlier failure stopped
from starting, or that nobody added to the list, leaves no trace. An alias also
changes what a task name means. ExQuality shells out to the real `mix credo`,
`mix format` and the rest, and a stage whose task name is aliased in
`mix.exs` refuses to report rather than measuring a command it did not issue
(see [Aliased tasks](../stages.md#aliased-tasks)).

**One CI job per tool.** Separate jobs give parallelism and a separate red or
green mark per tool. They also put the gate where only CI can see it. The
developer before a commit and the coding agent between edits want the same
answer locally, and a gate defined as a pipeline's job list has no local form
that is guaranteed to agree with it. With one command the pipeline step is
that command, and the [CI guide](../ci.md) is short for that reason.

**A tool that reimplements the checks.** A single analyser could own its rules
and its output format outright. ExQuality instead runs the project's own
dependencies at the versions the project pins and reads what they print. The
cost is parsing work inside each stage, and a stage prints a tool's output
verbatim whenever its parser cannot account for something. The benefit is
that `mix quality` and `mix credo` cannot disagree about a finding, and a
project adopts ExQuality without changing a single tool's configuration.

**Thresholds configured in the gate.** Coverage and security thresholds could
have lived in `.quality.exs` beside everything else. They are read from the
tool that owns them instead - `coveralls.json`, `test_coverage` in `mix.exs`,
`.sobelow-conf` - so a project has one place that defines "passing" for each
tool, and changing it shows as a change to that file.

## One command, many speeds

A single command that always did everything would be one that people and
agents stop invoking. On a large suite the tests are most of the wall clock,
and an aggregate command that always executes the whole suite is either paid
for or quietly replaced by the individual tool calls it was meant to collect.
The switches that narrow the command (`--quick`, `--test-scope`, `--profile`,
`--skip`, `--until-first-failure`) exist so that the inner loop and the gate
can stay one command with one output shape.

Two things make an agent loop cheap, and they pull in opposite directions. The
output properties above are one: a passing invocation costs a line per stage
of context instead of several tool reports, and a failing one gives
`file:line` targets without a second command. The other is that the command
has to be quick enough to be worth repeating. `--test-scope changed` serves
that, by executing only the tests that cover the changed files.

The price of many speeds is that a narrowed invocation and the full gate both
exit 0 with an "ok" status, and nobody watched an unattended agent choose
between them. The report therefore records how it was narrowed - its `scope`,
its profile, and a `skip_kind` on every skipped stage saying whether the skip
belongs to this invocation or to the project - and
[`mix quality.verify`](../ci.md#attesting-a-full-run) turns that record into
an attestation that the full gate was the one that executed. The attestation
says the gate was not narrowed; it cannot say the gate is strong, because a
project can weaken its own configuration and then attest honestly against the
weaker gate.

## What the choice costs

Putting the tools behind one command makes ExQuality a dependency of every
gate that uses it, and a defect in it can turn those gates red, or green when
they should be red. Two conventions follow from that. The report's shape is a
contract: fields are added and never repurposed, so a consumer routing on a
field keeps its meaning across versions. And nobody's gate changes on
upgrade: a new stage ships off by default and says in the
[changelog](../../CHANGELOG.md) how to enable it.

Concurrency is the other cost. The analysis stages share one build, so every
stage in that phase has to be a reader; the formatter and the compiler go
first, on their own, and a custom stage that writes under `_build` declares
itself a writer and is serialized the same way (see
[Custom stages](../stages.md#custom-stages)). A gate made of separate commands
never had to make that distinction, because nothing in it executed at the same
time.

Related: [Configuration](../configuration.md) for every switch named here,
[Stages](../stages.md) for what each stage executes and when it is enabled,
and [Usage rules](../../usage-rules.md) for the rules a coding agent reads.
