#!/usr/bin/env bash
# Trusts the workspace for git: in a container job the checkout belongs to
# the runner's user, not the container's, and git refuses to read it
# ("dubious ownership"). Steward leaves that check to the workflow
# (swift-steward's docs/danger.md, section 3). Adds the workspace to the
# global safe.directory list once, so a self-hosted runner's list doesn't
# grow with every run.
set -euo pipefail

listed=$(git config --global --get-all safe.directory || true)
if ! grep -Fqx -- "$GITHUB_WORKSPACE" <<<"$listed"; then
    git config --global --add safe.directory "$GITHUB_WORKSPACE"
fi
