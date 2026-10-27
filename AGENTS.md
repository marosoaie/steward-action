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
| `scripts/` | The steps' logic, one script each, so ShellCheck sees it |
| `Dangerfile/` | This repository's own checks, and the fixture CI runs the Action on |
| `tests/` | Scripts the CI's checks use |
| `.github/workflows/steward.yml` | The README's usage with `uses: ./`; posts the summary comment |
| `.github/workflows/ci.yml` | Lint, the fixture's tests, and the Action in a container, on macOS, with swiftly, and unable to post |

## Rules

- **Pin every action by full commit SHA**, with its version in a comment
  (`uses: actions/cache/restore@<sha> # v6.1.0`), in `action.yml` and the
  workflows. The fixture Dangerfile fails a pull request that doesn't.
- **Inputs reach scripts through `env:`**, never as `${{ }}` inside a
  `run:` script, so a value can't inject shell.
- **Every input is documented in the README's table**, as `` `name` ``;
  the fixture Dangerfile checks that too. Input names and defaults are the
  Action's API: the `v1` tag promises them, so renaming or removing one
  needs a new major.
- **Scripts** are bash with `set -euo pipefail`, run on macOS's bash 3.2
  too, and pass `shellcheck` with no exceptions. Mind the traps: a function
  called on the right of `||` runs with errexit off, and `cmd | grep -q`
  under pipefail can fail on SIGPIPE.
- **The Action doesn't pin Steward.** Each Dangerfile's `Package.resolved`
  does; the fixture follows swift-steward's `main` until a release has
  Steward, as swift-steward's template does.
- **Only one job per pull request posts at a time.** `steward.yml`'s
  `steward` job owns the summary comment, and the label-gated
  `pull-requests-write` check posts only after it, in the same run. Every
  other run of the Action in CI uses `token: ''` or a read-only token, and
  each has its own `report-artifact` name.

## Checks

```sh
actionlint                       # the workflows, and `uses: ./` inputs against action.yml
shellcheck scripts/*.sh tests/*.sh
swift test --package-path Dangerfile
```

The Action itself is only tested by running it: open a pull request, and
CI runs it in every configuration. The permission checks run on pull
requests with the `check-permissions` label, from the next push or edit of
the description on (adding the label alone starts nothing); they post and
delete comments, which notify.

## Releases

The maintainer tags releases. `v1` is a moving major tag, as GitHub
recommends for actions, and it means "these inputs": it's independent of
swift-steward's versions.
