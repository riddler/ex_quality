# CI and pre-commit

## In a pipeline

```yaml
- name: Run quality checks
  run: mix quality
```

That is the whole integration. The run exits non-zero if any stage failed, and
prints detail only for the stages that did.

To have the pipeline act on the result rather than just fail, write a report
alongside the human output and read it in a later step:

```yaml
- name: Run quality checks
  run: mix quality --report quality.json

- name: Upload report
  if: always()
  uses: actions/upload-artifact@v4
  with:
    name: quality-report
    path: quality.json
```

See [reports.md](reports.md) for the schema.

## Attesting a full run

A green run is not by itself evidence of a green gate. `--profile`,
`--test-scope`, `--quick`, `--skip` and `--until-first-failure` all exit 0
and produce `"status": "ok"`, and each of them checks less. When a person runs
the gate they saw which one they ran; when an agent runs it unattended and
reports "gate green" into a pull request or a commit message, nobody observed
the run, and the narrow one and the full one produce the same three words.

`mix quality.verify` is the check nobody has to remember to make:

```
$ mix quality.verify
...the usual mix quality output...

Full gate green: scope all, no profile, 9 stages considered.
Not checked by this project at all: Sobelow (:sobelow not installed)
```

It runs the gate and attests over the report: every stage green, no profile,
scope `"all"`, no quick mode, no stage skipped for a reason that names the run
(`skip_kind: "run"` - see [reports.md](reports.md#stage)), and coverage
measured when the project measures coverage at all. It exits 0 when the run
attests and non-zero when it does not, naming every reason at once:

```
** (Mix) Not a full gate: run used profile :loop and Dialyzer was skipped (--quick).
```

A stage skipped for a project-level reason - the tool is not installed, the
stage is disabled in `.quality.exs` - does not fail the attestation, because a
fuller run cannot close that gap. It is named in the passing output instead:
"full gate green" and "here is what this project never checks" are two
different facts, and the reader needs both.

Point unattended tooling - an agent pipeline's attestation command, a merge
gate - at `mix quality.verify` rather than at `mix quality`'s exit code.

**What this does not prove.** The attestation says the run was not narrowed.
It cannot say the gate is *strong*: a project can weaken `.quality.exs` - drop
a stage, add a permissive profile - or lower a coverage threshold, and then
attest honestly against the weakened gate. Guarding the gate's own
configuration is a different mechanism (a diff of the config against a base
ref), and a caller that treats this attestation as proof of it is claiming
more than was checked.

## Warming the Dialyzer PLT

Dialyzer analyses against a PLT, a cache of every module it has already seen.
Building one takes minutes; analysing against a warm one takes seconds. On a
fresh container that cost lands inside a check whose only output is one line at
the end, so the job looks hung.

`mix quality.plt` is the warm-up target. It is the same work `mix quality`
would otherwise do, moved somewhere it can be cached:

```yaml
- name: Restore PLT cache
  uses: actions/cache@v4
  with:
    path: |
      _build
      ~/.mix
    key: ${{ runner.os }}-plt-${{ hashFiles('**/mix.lock') }}

- name: Build PLT
  run: mix quality.plt

- name: Run quality checks
  run: mix quality
```

Cache both `_build` and `~/.mix`: dialyxir keeps the core PLTs in the Mix home
and the project's own under `_build`.

Unlike a check, this task's whole point is the progress, so dialyxir's output
is passed through as it arrives rather than summarised.

Skipping the warm-up breaks nothing. The run builds the PLT itself, says so
while it happens, and reports it afterwards:

```
⋯ Dialyzer: building PLT (this is a one-time cost)
✓ Dialyzer: No warnings (PLT built this run) (252.4s)
```

That is a normal pass: the analysis is as trustworthy as any other.

`mix quality.plt` requires `:dialyxir`. A project without it has no PLT to
build, and the task says so rather than doing nothing quietly.

## In a container image

Same idea, one layer earlier. Run it after `mix deps.get` and before any check,
so the PLT is baked into the image instead of built on every run:

```dockerfile
RUN mix deps.get
RUN mix quality.plt
```

## Pre-commit hook

`.git/hooks/pre-commit`:

```bash
#!/bin/sh
mix quality --quick
```

Quick mode skips Dialyzer and coverage enforcement, which keeps the hook fast
enough to live with. Leave the full run to CI.
