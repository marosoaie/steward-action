# Security policy

The Action builds and runs a Dangerfile, which is the pull request's own
code, with the token it's given. It's built so that its inputs can't run
anything the workflow didn't ask for.

## What the Action guarantees

- **Inputs are data, never script.** They reach the Action's scripts
  through `env:`, never expanded into a `run:` script. `swift-version`
  must be a version or a snapshot's name, starting with a letter or a
  digit, so it can't reach swiftly as an option.
- **What it runs is pinned.** Every action it uses is pinned to a full
  commit SHA, so a moved tag can't change it.
- **What it installs is verified.** It checks swiftly's download against
  swift.org's signing keys before running it, and swiftly verifies the
  toolchains it installs.
- **The token goes to one step.** Only the step that runs the
  Dangerfile gets `token` in its environment.

## What the Action doesn't protect against

The Dangerfile is the pull request's code, so a pull request can change
its own check and read the token it runs with. Steward's
[security model](https://github.com/marosoaie/swift-steward/blob/main/docs/quickstart.md#security-model)
says what that means for branch protection and tokens.

## Reporting a vulnerability

Report it through swift-steward's private vulnerability reporting: on
[swift-steward's **Security** tab](https://github.com/marosoaie/swift-steward/security),
choose **Report a vulnerability**, and say it's about the Action. The
report stays private between you and the maintainer until a fix is
published. Include the workflow and inputs that trigger the problem, and
the Action's version or commit.

## Supported versions

The Action is pre-1.0. Fixes land on `main` and ship in the next
release; earlier releases don't get backported fixes.
