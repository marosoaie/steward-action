#!/usr/bin/env bash
# Runs the Dangerfile package's product, already built, with the Action's
# inputs as Steward's options. Unless REPORT_ARTIFACT is empty, writes
# `report`, the path of the report it asks Steward for, to GITHUB_OUTPUT
# first, so a failing run's report is still uploaded.
set -euo pipefail

arguments=()
if [ -n "$REPORT_ARTIFACT" ]; then
    report=${RUNNER_TEMP:?}/steward/report.json
    mkdir -p "$(dirname "$report")"
    echo "report=$report" >>"$GITHUB_OUTPUT"
    arguments+=("--report=$report")
fi
case "$FAIL_ON_POST_ERROR" in
true) arguments+=(--fail-on-post-error) ;;
false) ;;
*)
    echo "::error title=Steward::fail-on-post-error is true or false, not \"$FAIL_ON_POST_ERROR\"."
    exit 2
    ;;
esac
if [ -n "$SUMMARY_AUTHOR" ]; then
    arguments+=("--summary-author=$SUMMARY_AUTHOR")
elif [ -n "${GITHUB_TOKEN:-}" ] && [ "$DEFAULT_TOKEN" != true ]; then
    echo "::warning title=Steward::The token isn't the workflow's own, so set summary-author to the login \
it posts as. Without it, Steward looks for summaries by github-actions[bot], finds none, and posts a new \
one on every run."
fi

# The `+` form: bash 3.2, macOS's own, calls an empty array unbound.
exec swift run --skip-build --package-path "$PACKAGE_PATH" "$PRODUCT" ${arguments[@]+"${arguments[@]}"}
