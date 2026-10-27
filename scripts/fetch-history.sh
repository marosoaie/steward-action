#!/usr/bin/env bash
# Fetches the history Steward needs into the checkout in the current
# directory (swift-steward's docs/danger.md, section 3). A shallow checkout,
# such as actions/checkout's default depth of 1, gets the whole history of
# the pull request's base and head commits; a full clone is left alone.
# The commits are fetched by SHA, since a fork's head is on none of
# origin's branches.
#
# Usage: fetch-history.sh <base-sha> <head-sha>
set -euo pipefail

if [ "$(git rev-parse --is-shallow-repository)" != true ]; then
    echo "The checkout isn't shallow, so it has the history Steward needs."
    exit 0
fi
echo "Fetching the whole history of the base commit $1 and the head commit $2."
if ! git fetch --unshallow --no-tags --no-recurse-submodules --quiet origin "$1" "$2"; then
    echo "::error title=Steward::Couldn't fetch the base commit $1 and the head commit $2 from origin. \
actions/checkout's credentials are what the fetch uses: keep its persist-credentials default, \
or check out with fetch-depth: 0."
    exit 1
fi
