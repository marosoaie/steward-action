#!/usr/bin/env bash
# Runs the Dangerfile package's product, already built, with the Action's
# inputs as Steward's options. Unless REPORT_ARTIFACT is empty, writes
# `report`, the path of the report it asks Steward for, to GITHUB_OUTPUT
# first, so a failing run's report is still uploaded. The path is new for
# every run, so a second run in the job never uploads the first one's.
# Then writes `started`, the time it starts the product in seconds since
# the epoch, and once it's done, `status`, its exit status, which tells a
# run that reported (0 or 1) from one that ended first.
set -euo pipefail

arguments=()
if [ -n "$REPORT_ARTIFACT" ]; then
    report=$(mktemp -d "${RUNNER_TEMP:?}/steward.XXXXXX")/report.json
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

echo "started=$(date -u +%s)" >>"$GITHUB_OUTPUT"
# Not `exec`, so the status can be written. A cancelled job's signal goes to
# the step's own shell, whose child this script is, either way.
status=0
# The `+` form: bash 3.2, macOS's own, calls an empty array unbound.
swift run --skip-build --package-path "$PACKAGE_PATH" "$PRODUCT" ${arguments[@]+"${arguments[@]}"} || status=$?
echo "status=$status" >>"$GITHUB_OUTPUT"
exit "$status"
