#!/usr/bin/env bash
# Fetches the history Steward needs into the checkout in the current
# directory: the pull request's base and head commits, and enough of their
# history that Steward reads `base..head` and their merge base exactly as a
# full clone has them (swift-steward's docs/danger.md, section 3).
#
# A full clone is left alone. A shallow one, such as actions/checkout's
# default depth of 1, is deepened from the two commits, doubling the depth
# until the history passes the check Steward makes, and fetched whole once
# the depth passes MAX_DEPTH. Every depth reaches past the history the
# checkout already has, since a fetch with a smaller one would cut it
# short. It never fetches GITHUB_SHA: whether the checkout has it decides
# which commit Steward maps build logs from.
#
# Usage: fetch-history.sh <base-sha> <head-sha> [<commits in the pull request>]
set -euo pipefail

base=$1
head=$2
commits=${3:-0}
max_depth=${MAX_DEPTH:-10000}

has_commit() {
    git cat-file -e "$1^{commit}" 2>/dev/null
}

# How many commits the checkout has below a commit, itself included: 0
# without it, and more than the distance to any of them.
count() {
    if has_commit "$1"; then git rev-list --count "$1" --; else echo 0; fi
}

is_shallow() {
    [ "$(git rev-parse --is-shallow-repository)" = true ]
}

# Whether a list of `rev-list --parents` lines has a commit without parents:
# a root, or a shallow clone's cut.
has_parentless() {
    awk 'NF == 1 { found = 1 } END { exit !found }'
}

# Whether the checkout has what Steward needs: both commits and, in a
# shallow clone, a merge base and history that passes Steward's own check
# (Sources/Steward/GitChanges+Git.swift, `requireUncut`). No commit in
# `base..head` may be a cut, and every cut the base reaches must lie below
# each commit the range starts from, or the base's commits would join it.
has_history() {
    has_commit "$base" && has_commit "$head" || return 1
    is_shallow || return 0
    git merge-base "$base" "$head" >/dev/null || return 1
    local range starts start below
    range=$(git rev-list --parents "$base..$head" --) || return 1
    if has_parentless <<<"$range"; then return 1; fi
    # The parents of the range's commits that aren't in it.
    starts=$(awk '
        { commit[$1] = 1; for (i = 2; i <= NF; i++) parent[$i] = 1 }
        END { for (p in parent) if (!(p in commit)) print p }
    ' <<<"$range")
    for start in $starts; do
        below=$(git rev-list --parents "$base" "^$start" --) || return 1
        if has_parentless <<<"$below"; then return 1; fi
    done
}

fetch() {
    if ! git fetch --no-tags --no-recurse-submodules --quiet "$@" origin "$base" "$head"; then
        echo "::error title=Steward::Couldn't fetch the base commit $base and the head commit $head from origin. \
actions/checkout's credentials are what the fetch uses: keep its persist-credentials default, \
or check out with fetch-depth: 0."
        exit 1
    fi
}

if has_history; then
    echo "The checkout has the history Steward needs."
    exit 0
fi

if ! is_shallow; then
    fetch
else
    # The head's side needs a depth one more than the pull request's
    # commits; the base's side, however far the base moved since the
    # branch was cut, which only the history can tell.
    depth=$((commits + 50))
    for present in $(count "$base") $(count "$head"); do
        depth=$((present + 1 > depth ? present + 1 : depth))
    done
    until has_history; do
        if ((depth > max_depth)); then
            echo "Fetching the whole history: a depth of $max_depth wasn't enough."
            fetch --unshallow
            break
        fi
        echo "Fetching the base and head commits with a depth of $depth."
        fetch --depth="$depth"
        depth=$((depth * 2))
    done
fi

if ! has_history; then
    echo "::error title=Steward::Couldn't fetch the history of the base commit $base and the head commit $head from origin."
    exit 1
fi
echo "The checkout has the history Steward needs."
