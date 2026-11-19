# steward-action — contributor & agent guide

The composite GitHub Action that runs a
[Steward](https://github.com/marosoaie/swift-steward) Dangerfile on a pull
request. It's glue: Swift, `safe.directory`, the history, the build cache,
and `swift run`. Steward itself, and what the Action must provide for it,
are designed in swift-steward's
[docs/danger.md](https://github.com/marosoaie/swift-steward/blob/main/docs/danger.md)
(sections 3, 5, 6 and 8). Follow swift-steward's
[AGENTS.md](https://github.com/marosoaie/swift-steward/blob/main/AGENTS.md)
for everything it covers that applies here: commit messages, oracles over
hand-computed expectations, a regression test with every fix, no large
binaries or Git LFS, and the maintainer choosing versions.

## Layout

| Path | What it is |
|---|---|
| `action.yml` | The Action: inputs, outputs, and the steps |
| `scripts/` | The steps' logic, one script each, and the release workflow's checks, so ShellCheck sees them |
| `Dangerfile/` | This repository's own checks, and the fixture CI runs the Action on |
| `tests/` | Scripts the CI's checks use |
| `docs/decisions.md` | The design decisions and their alternatives; add a row with each new one |
| `.github/workflows/steward.yml` | The README's usage with `uses: ./`; posts the summary comment |
| `.github/workflows/ci.yml` | Lint, the fixture's tests, and the Action in a container, on macOS, with swiftly, and unable to post |
| `.github/workflows/release.yml` | Run by hand to tag and publish a release |

## Rules

- **Pin every action by full commit SHA**, with its version in a comment
  (`uses: actions/cache/restore@<sha> # v6.1.0`), in `action.yml` and the
  workflows. The fixture Dangerfile fails a pull request that doesn't.
  Dependabot proposes new pins monthly, in one pull request.
- **Inputs reach scripts through `env:`**, never as `${{ }}` inside a
  `run:` script, so a value can't inject shell.
- **Every input is documented in the README's table**, as `` `name` ``;
  the fixture Dangerfile checks that too. Input names and defaults are the
  Action's API: renaming or removing one needs a new minor under 0.x, and
  a new major from 1.0.
- **Scripts** are bash with `set -euo pipefail`, run on macOS's bash 3.2
  too, and pass `shellcheck` with no exceptions. Mind the traps: a function
  called on the right of `||` runs with errexit off, and `cmd | grep -q`
  under pipefail can fail on SIGPIPE.
- **Less code over a small speed gain.** The maintainer's rule (decision
  6): don't write code to save time unless the time is large. The history
  step fetches everything rather than just enough.
- **The Action doesn't pin Steward.** Each Dangerfile's `Package.resolved`
  does; the fixture depends on Steward 0.2.x, as swift-steward's template
  does.
- **Only one job per pull request posts at a time.** `steward.yml`'s
  `steward` job owns the summary comment, and the label-gated
  `pull-requests-write` check posts only after it, in the same run. Every
  other run of the Action in CI uses `token: ''` or a read-only token, and
  each has its own `report-artifact` name.

## Checks

```sh
actionlint                       # the workflows, and `uses: ./` inputs against action.yml
shellcheck scripts/*.sh tests/*.sh
tests/swift-version.sh           # the swift-version values setup-swift.sh accepts
swift test --package-path Dangerfile
```

The Action itself is only tested by running it: open a pull request, and
CI runs it in every configuration. The permission checks run on pull
requests with the `check-permissions` label, from the next push or edit of
the description on (adding the label alone starts nothing); they post and
delete comments, which notify.

## Releases

Releases are tagged `vX.Y.Z`, starting at `v0.1.0`, and are immutable
once published; their versions are independent of swift-steward's. The
maintainer drives version numbers and releases; never tag or release
unprompted. Under 0.x a minor release may break, so workflows pin an
exact tag such as `@v0.1.1`, or a SHA. A moving major tag, `v1`, as
GitHub recommends for actions, waits for 1.0; it will mean "these
inputs".
The README's two pins name the latest release's tag. A release moves them
to its own tag, in a pull request merged before it's tagged, so each
tag's README names that tag.

A release is made by the Release workflow
(`.github/workflows/release.yml`), run by hand from `main` with the
version, `MAJOR.MINOR.PATCH` without the `v`, and optional notes, which
GitHub generates when none are given:
`gh workflow run release.yml --ref main -f version=0.1.2 -F notes=@notes.md`.
It refuses a version that's already tagged, or isn't greater than every
version tagged so far, with or without the `v`
(`scripts/check-release-version.sh`, as steward-lang-swift's), and a
README with a pin that doesn't name the new tag
(`scripts/check-readme-pins.sh`); then, with the only token in this
repository's workflows that can push (`contents: write`), it tags the
commit `vX.Y.Z`, publishes the release, and checks that the tag is that
commit. It runs no tests. The ruleset requires CI's checks on pull
requests into `main`, but merges go through the maintainer's bypass,
since it also requires a review and there's no second reviewer, so green
checks at merge are the maintainer's practice, not a guarantee. The pins'
pull request is the last one merged before a release, and up to date
with `main` when its checks run, so they ran on the tree that's tagged.
A published release's tag can't be moved, nor deleted while the release
exists, and its name can't be used again; its title and notes can still
be edited.
