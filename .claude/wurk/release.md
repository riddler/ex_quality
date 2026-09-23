# Release extension

Additional required steps for `/wurk:release` in this repo. The skill reads
this file before step 1 of its `kind: "hex"` recipe and treats what is here as
required steps placed where this file says. Extensions add; they never
override, and nothing below rewrites a step the skill already performs.

Read this together with `.claude/wurk.json`'s `release` block. Between them
they name every file a release commit here touches, and no others.

The reference for every shape below is **the most recent release-prep commit
on `main`**, resolved when you read this rather than named here:

```bash
git log --oneline --no-patch -L '/@version/,+1:mix.exs'
```

The first line is the last commit that moved `@version`, and that is the last
release prep. Its subject has the form `Releases vX.Y.Z (#NN)`. Where this file
and the reference commit disagree, the commit is the evidence and this file is
the defect. This file names no SHA and no current version on purpose: a
hard-coded reference stops being the most recent the moment the next release
lands, and a release commit does not touch this file.

## Why the recipe names no changelog

The skill's changelog step renames `## [Unreleased]` to the new version and
forbids adding a fresh `## [Unreleased]` above it. This repo does the
opposite: `## [Unreleased]` is permanent, and a release inserts the new
version heading directly **below** it, so the entries that were unreleased
now sit under the version and the unreleased section is left empty. An
extension cannot override the skill's step, so `release.changelog` is
deliberately absent from the manifest, and the promotion is the required step
below.

The unreleased-work check still applies: if nothing sits between
`## [Unreleased]` and the previous version's heading, there is nothing to
release, and the run stops.

## The required step: promote the unreleased section

Placed where the skill's changelog step would have been.

1. In `CHANGELOG.md`, insert `## [X.Y.Z] - YYYY-MM-DD` and a blank line on the
   line after `## [Unreleased]` and its blank line. The heading form is the one
   the file already uses: bracketed version, space, hyphen, space, date.
2. **The date is the operator's local date, not UTC**: take it from `date +%F`
   on the machine cutting the prep.
3. **Carry every entry over byte for byte.** Leave every line under the new
   heading untouched. Rewording, reordering or consolidating entries is an
   editorial pass a human does separately, before the release.
4. `## [Unreleased]` stays, now followed directly by the new heading.

### The link-reference block

`CHANGELOG.md` ends with a Keep a Changelog link-reference block
(`[Unreleased]: .../compare/vA...HEAD`, one `[X.Y.Z]:` line per version). It
was last maintained by a release prep at 0.13.0; later preps did not touch it,
and some of its older lines are misnumbered. Whether to repair and resume it
is the operator's call. Until that is decided, a release prep leaves it
alone: repairing it is a change to the file, not a release step.

## The README install pin

`release.readme_pin` is `true`. `README.md` carries
`{:ex_quality, "~> X.Y", only: :dev, runtime: false}` in its install snippet,
and the form is major/minor with the patch dropped, which is the skill's own
default. A minor or major release moves it; a patch release leaves it as it
is, because the major/minor has not changed. Check it against the version
file:

```bash
grep 'ex_quality, "~>' README.md   # the pin
grep '@version "' mix.exs          # the version it should track
```

## No second version carrier

`mix.exs` is the only place the version is written. `docs: [source_ref:
"v#{@version}"]` derives from it, which is why the tag must be named
`vX.Y.Z`: HexDocs source links point at that tag. If a second carrier is ever
added, it gets a step in this file on the same day.

## The files a release commit touches

Exactly these, and a release commit that touches anything else is wrong:

| File | Moved by |
|---|---|
| `mix.exs` | the recipe's `version_file` |
| `CHANGELOG.md` | the promotion step |
| `README.md` | the recipe's `readme_pin`, minor and major releases only |

## What a release here still is not

The skill does not tag, push, open a request or publish, and this extension
does not either. The `vX.Y.Z` tag and `mix hex.publish` are the operator's,
in every campaign and outside every campaign. `CLAUDE.md`'s authority table
says so, and the one exception it names is a release-prep request: the
version bump and the changelog promotion above, no tag, under a campaign
consent clause that names it.
