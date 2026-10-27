# Steward Action

Runs a [Steward](https://github.com/marosoaie/swift-steward) Dangerfile on a
pull request and posts what its rules find as one comment, kept up to date
on every push. Steward is a pure-Swift Danger: the rules are Swift, in a
`Dangerfile/` package beside your own, and there's no Node or separate
binary. The [quickstart](https://github.com/marosoaie/swift-steward/blob/main/docs/quickstart.md)
sets up the package; this Action runs it.

**Not released yet.** No swift-steward release has Steward yet, so there's
no `v1` tag here either. Until there is, use the quickstart's workflow
without the Action.

## Usage

Save this as `.github/workflows/steward.yml`:

```yaml
name: Steward

on:
  pull_request:
    types: [opened, synchronize, reopened, edited, ready_for_review]

permissions:
  contents: read
  pull-requests: write

concurrency:
  group: ${{ github.workflow }}-${{ github.event.pull_request.number }}
  cancel-in-progress: true

jobs:
  steward:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - uses: marosoaie/steward-action@v1
```

With the package at `Dangerfile/` and its executable called `Dangerfile`,
as the template has them, it needs no `with:`. The Action:

1. Stops with an error on any event but `pull_request`.
2. Uses the runner's Swift, or installs one with
   [swiftly](https://github.com/swiftlang/swiftly) (see
   [Runners](#runners)).
3. Trusts the workspace for git (`safe.directory`), which a container job
   needs.
4. Fetches the history Steward needs (see [History](#history)).
5. Restores the package's `.build` from the cache, builds the executable,
   and saves the build when the cache didn't have it.
6. Runs it with `swift run`. Steward posts or updates the summary comment,
   writes the job summary, and exits with 1 when a rule finds a failure,
   which fails the step.
7. Uploads Steward's JSON report as an artifact, which a summary too long
   for the comment points at.

## Inputs

| Input | Default | What it does |
|---|---|---|
| `package-path` | `Dangerfile` | The Dangerfile package's directory, relative to the repository's root |
| `product` | `Dangerfile` | The package's executable product, which runs the rules |
| `token` | `${{ github.token }}` | The token Steward posts with. Empty posts nothing, with a warning |
| `summary-author` | Steward's, `github-actions[bot]` | The login the token posts as, whose summary comments Steward updates (`--summary-author`) |
| `fail-on-post-error` | `false` | `true` fails the step when the summary can't be posted (`--fail-on-post-error`) |
| `report-artifact` | `steward-report` | The name of the report's artifact; empty writes no report |
| `swift-version` | runner's | On Linux, the Swift version to install with swiftly, such as `6.2` or `6.2.1`, unless the runner's Swift is that version already |

The output `report` is the report's path, empty when `report-artifact` is.

**Another token.** With a personal access token or a GitHub App's
installation token as `token`, set `summary-author` to the account it
posts as (a user's login, or `<app-slug>[bot]` for an app). Steward only
updates summaries that account wrote, so without it, it finds none and
posts a new one on every run; the Action warns when `token` isn't the
workflow's and `summary-author` is empty.

**Posting failures.** When posting fails, for a missing permission, an
outage or a rate limit, Steward warns, and the findings alone decide the
step's outcome; the job summary and the report have them either way.
`fail-on-post-error: true` makes a failed post fail the step instead.

## Permissions

```yaml
permissions:
  contents: read
  pull-requests: write
```

`pull-requests: write` is the only permission Steward needs for its
comment: with it alone, the workflow's token creates, updates and deletes
a pull request's comments. GitHub's REST documentation lists
`issues: write` as enough too, but on a pull request it isn't: the token
gets 403, "Resource not accessible by integration". This repository's CI
checks all three, and that `pull-requests: read` can't post (see
[Development](#development)).
`contents: read` lets the job check out a private repository. Set both
explicitly: new repositories give `GITHUB_TOKEN` read-only permissions by
default.

A pull request from a fork gets a read-only token: the rules run, the job
summary has the findings, and Steward posts nothing, with a notice. A
Dependabot pull request gets a read-only token too, and posting fails
with a warning.

## One run per pull request

The `concurrency` group is part of the usage, and the Action can't set it
itself: GitHub reads `concurrency` from the workflow, not from an action.
It cancels a pull request's running Steward job when a newer one starts.
GitHub's comment API has no locking, so two runs posting to one pull
request at the same time can leave a duplicate summary, or none until the
next run; without the group, that's unsupported. The group's name starts
with the workflow's, because the names are shared by every workflow in the
repository. For the same reason, several Dangerfiles, workflows, jobs or
matrix entries posting to one pull request are unsupported: they'd
overwrite each other's summary.

## Events

`pull_request` with the default activity types (`opened`, `synchronize`,
`reopened`) and two more: `edited`, so rules about the title and
description run again when those change, and `ready_for_review`, for rules
that treat drafts differently. Steward refuses every other activity type
and event, `push` and `pull_request_target` included.

## History

Steward reads the pull request as GitHub's Files changed tab shows it,
from the merge base to the head, and maps build logs from the merge
commit `actions/checkout` checks out to the head. So it needs the base and
head commits, with their history back to the merge base on every path.
The Action fetches them itself:

- With `actions/checkout`'s default `fetch-depth: 1`, it fetches the base
  and head commits at a depth of the pull request's commits plus 50, and
  doubles the depth until the history passes Steward's check, or fetches
  their whole history past 10,000. It never shortens history the checkout
  already has, and never fetches the merge commit itself, whose presence
  tells Steward which commit the build logs come from.
- With `fetch-depth: 0`, or any history that's already enough, it fetches
  nothing.

The fetch uses the credentials `actions/checkout` keeps by default. In a
private repository checked out with `persist-credentials: false`, use
`fetch-depth: 0` instead.

## Runners

- **Ubuntu.** GitHub's Ubuntu images have Swift preinstalled (6.4 in
  October 2026), which the Action uses unless `swift-version` asks for
  another. A runner without Swift gets the latest release from swiftly,
  which needs `curl`, `gpg` and the toolchain's system packages (the
  Action installs those with `sudo` when it can). The Action puts that
  toolchain itself on `PATH`, for the rest of the job too, so a
  `.swift-version` file in the repository doesn't send swiftly's `swift`
  to another one.
- **A container job** (`container: swift:6.2`) uses the image's Swift. The
  image needs `git`, so that `actions/checkout` makes a real checkout.
- **macOS** (`macos-26`, as Steward needs macOS 26) uses the selected
  Xcode's Swift; `swift-version` is an error there.

Steward needs Swift 6.2 or later.

## Build logs

Steward's built-in rule, `Rule.diagnosticsOnChangedLines(in:)`, reads
build and lint logs that earlier steps of the same job wrote. Build before
the Action, without colours, which Swift 6.4 writes even into a pipe and
Steward can't read, and run the Action even when the build fails, so it
reports a broken build's errors:

```yaml
steps:
  - uses: actions/checkout@v7
  - name: Build
    shell: bash
    run: swift build --no-color-diagnostics 2>&1 | tee build.log
  - uses: marosoaie/steward-action@v1
    if: ${{ !cancelled() }}
```

## Caching

The package's `.build` is cached under a key made of the runner's OS and
architecture, a hash of the toolchain's version, the OS release and the
workspace's path, and a hash of `Package.resolved`. Commit
`Package.resolved`: it pins the Steward revision the rules run with, and
the cache follows it. A key that misses restores the newest build for the
same toolchain, and SwiftPM rebuilds what changed. GitHub scopes a pull
request's caches to that pull request, so each pull request's first run
builds from scratch, or from a cache saved on its base branch.

## Development

This repository's own pull requests run the Action from their checkout
(`uses: ./`), on the fixture `Dangerfile/` package at the root, which is
also this repository's own checks: actions pinned to commit SHAs, and every
input documented here.

- **Steward** (`.github/workflows/steward.yml`) is the usage above, and
  posts the pull request's summary comment. With the `check-permissions`
  label, from the next push or edit on, it also checks what the workflow's token can do with comments
  under `pull-requests: write` alone (create, update and delete, and
  Steward deleting a planted second summary), and that `issues: write`
  alone and `pull-requests: read` can't create one.
- **CI** (`.github/workflows/ci.yml`) lints the workflows and scripts with
  actionlint and ShellCheck, runs the fixture's tests, and runs the Action
  in a `swift:6.2` container, on macOS, with Swift 6.2 from swiftly, and
  with a token that can't post, with and without `fail-on-post-error`.

[AGENTS.md](AGENTS.md) has the conventions.
