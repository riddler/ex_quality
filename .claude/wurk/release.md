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

`CHANGELOG.md` ends with a Keep a Changelog link-reference block: one
`[Unreleased]: .../compare/vNEWEST...HEAD` line, then one `[X.Y.Z]:` line per
version heading, newest first, each
`.../compare/vPREV...vX.Y.Z`; the oldest, `[0.1.0]`, links its release tag
page. It is maintained. It was repaired on 2026-10-18 (the operator's answer
to whether to repair and resume it was "Repair, add it"): every version
heading has a line, no key repeats, and every range ends at its own version.
One version has no tag: the 0.14.1 prep was never tagged, so its two ranges
use the prep commit `f649263` (an ancestor of `main`) in place of `v0.14.1`.

A release prep keeps the block current, inside `CHANGELOG.md`, in the same
commit as the promotion above:

1. Move `[Unreleased]`'s base to the new tag: `compare/vX.Y.Z...HEAD`.
2. Add the new version's line directly below `[Unreleased]`:
   `[X.Y.Z]: https://github.com/riddler/ex_quality/compare/vPREV...vX.Y.Z`,
   where `vPREV` is the version heading just below the new one.

The new tag does not exist when the prep is cut (it is pushed after the prep
merges), so the new lines resolve once the tag is pushed. Check the block
before committing: one line per version heading plus `[Unreleased]`, in
heading order, and every `vA` or `vB` it names is a tag in `git tag -l 'v*'`
or the new version.

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
does not either. What it produces is the release prep: the version bump and
the changelog promotion above, on a release bead the operator has named (in
the campaign plan or their own words), landing through the rows of
`CLAUDE.md`'s authority table. Tagging that prep is the family norm, not a
grant a campaign consent has to name: once the prep is merged to
`origin/main`, the conductor or the session that owns the release bead tags
the merged commit `vX.Y.Z` and pushes the tag. An agent or a session never
runs `mix hex.publish` (a docs republish included): the release workflow
(`.github/workflows/release.yml`) publishes on that tag push, and a failed
workflow is re-run from its Actions page, never worked round by a local
publish. `CLAUDE.md`'s release-prep row and its Release preps paragraph say
so.
