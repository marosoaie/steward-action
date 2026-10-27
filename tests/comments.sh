#!/usr/bin/env bash
# Checks what GITHUB_TOKEN may do with the pull request's issue comments,
# for this repository's CI.
#
#   comments.sh probe allowed|forbidden
#       Creates, updates and deletes a comment, and checks GitHub's answers:
#       201, 200 and 204, or a creation refused with 403.
#   comments.sh plant
#       Posts two summary comments, as racing runs would, so the newer is a
#       duplicate even when the pull request has no summary yet, and writes
#       the newer one's id to GITHUB_OUTPUT as `id`.
#   comments.sh gone <id>
#       Checks that the comment is deleted and one summary comment is left.
#
# Needs GITHUB_TOKEN, PULL_REQUEST, the variables Actions sets, and gh.
set -euo pipefail

marker='<!-- steward-summary -->'
response=$(mktemp)

# Prints the status of a request to the repository's API, and keeps the
# response's body in $response.
api() {
    local method=$1 path=$2
    shift 2
    curl -sS -o "$response" -w '%{http_code}' -X "$method" \
        -H "Authorization: Bearer $GITHUB_TOKEN" \
        -H 'Accept: application/vnd.github+json' \
        -H 'X-GitHub-Api-Version: 2022-11-28' \
        "$GITHUB_API_URL/repos/$GITHUB_REPOSITORY/$path" "$@"
}

expect() {
    local what=$1 expected=$2 status=$3
    echo "$what: $status"
    if [ "$status" != "$expected" ]; then
        echo "::error::$what answered $status, not $expected: $(cat "$response")"
        exit 1
    fi
}

body() {
    jq -n --arg body "$1" '{body: $body}'
}

case $1 in
probe)
    status=$(api POST "issues/$PULL_REQUEST/comments" --data "$(body "A permissions probe, deleted right away.")")
    if [ "$2" = forbidden ]; then
        expect "Creating a comment" 403 "$status"
        exit 0
    fi
    expect "Creating a comment" 201 "$status"
    id=$(jq -r .id "$response")
    expect "Updating it" 200 "$(api PATCH "issues/comments/$id" --data "$(body "A permissions probe, updated.")")"
    expect "Deleting it" 204 "$(api DELETE "issues/comments/$id")"
    ;;
plant)
    for which in older newer; do
        status=$(api POST "issues/$PULL_REQUEST/comments" \
            --data "$(body "$marker
A summary comment planted for Steward to keep, if it's the oldest, or delete.")")
        expect "Planting the $which summary" 201 "$status"
    done
    echo "id=$(jq -r .id "$response")" >>"$GITHUB_OUTPUT"
    ;;
gone)
    expect "Reading the planted summary" 404 "$(api GET "issues/comments/$2")"
    # Every page, as Steward reads them.
    summaries=$(GH_TOKEN=$GITHUB_TOKEN gh api --paginate "repos/$GITHUB_REPOSITORY/issues/$PULL_REQUEST/comments?per_page=100" \
        --jq ".[] | select(.user.login == \"github-actions[bot]\" and (.body | startswith(\"$marker\"))) | .id" | wc -l)
    expect "Summary comments left" 1 "$((summaries))"
    ;;
*)
    echo "Usage: comments.sh probe allowed|forbidden | plant | gone <id>" >&2
    exit 2
    ;;
esac
