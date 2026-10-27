# Decisions

The Action's design decisions, with the alternatives they were chosen
over. The first twelve are the questions of
[#1](https://github.com/marosoaie/steward-action/pull/1), answered by the
maintainer on 2026-10-27; all but 6 went as recommended. Swift-steward's
[docs/danger.md](https://github.com/marosoaie/swift-steward/blob/main/docs/danger.md)
section 8 holds the decisions this repository started from (decision 3: a
separate repository).

| # | Topic | Decision | Alternatives |
|---|---|---|---|
| 1 | Toolchain | The runner's Swift; swiftly when the runner has none or `swift-version` asks for another | Always install with swiftly, pinned in the Action; swift-actions/setup-swift; a `swift:<version>` container through `docker run` |
| 2 | `swift-version` | An input, Linux only; on macOS it's an error naming `xcode-select` and `DEVELOPER_DIR`, since swift.org toolchains there still need Xcode's SDK | No input: the runner image's Swift only |
| 3 | macOS | Supported with Xcode's Swift, and tested in CI | Ubuntu only, with build logs from other jobs |
| 4 | `product` | An input, defaulting to the template's `Dangerfile`, since Steward's options go after the product's name | Read it from `swift package describe --type json` |
| 5 | Report | Always `--report`, uploaded as `steward-report`; `report-artifact` renames it, and empty turns it off | No artifact, so a cut-short summary's pointer to it would be false |
| 6 | History | **Changed from the recommendation:** a shallow checkout gets the base and head commits' whole history (`git fetch --unshallow`, by SHA); a full clone fetches nothing. In the maintainer's words: "just fetch the whole history simpler and less error prone. We should avoid writing code if we can when the performance impact is not that big." | Deepening until the history passes a shell copy of Steward's `requireUncut` check (the recommendation); documenting `fetch-depth: 0` and fetching nothing |
| 7 | Event check | Any event but `pull_request` stops with exit 2 before the build | Leave it to Steward, a build later |
| 8 | `safe.directory` | The workspace is added to the global git config once, and stays for the job's later steps | `GIT_CONFIG_*` variables for the Action's steps only, which git reads for `safe.directory` only from 2.38 |
| 9 | Cache warming | Not now; a later `build-only` input could warm a `push` workflow's cache | Build it now |
| 10 | Fixture | This repository's own `Dangerfile/`, on swift-steward's `main` at the revision its `Package.resolved` pins, until a release has Steward; then `from:` | A separate test fixture; a revision pin in the manifest |
| 11 | Permission checks | Behind the `check-permissions` label, since every probe's comment notifies | On every pull request |
| 12 | Marketplace name | Decided later (step 5.3). `name: Steward` can't be listed, since `steward` is a GitHub user, and the name shouldn't say Swift: Steward checks projects in other languages too. The name doesn't affect `uses:` | |
