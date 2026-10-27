#!/usr/bin/env bash
# Checks what GITHUB_TOKEN may do with the pull request's issue comments,
# for this repository's CI.
#
#   comments.sh probe allowed|forbidden
#       Creates, updates and deletes a comment, and checks GitHub's answers:
#       201, 200 and 204, or a creation refused with 403.
#   comments.sh plant
#       Posts a second summary comment, as a run racing another would, and
#       writes its id to GITHUB_OUTPUT as `id`.
#   comments.sh gone <id>
#       Checks that the comment is deleted and one summary comment is left.
#
# Needs GITHUB_TOKEN, PULL_REQUEST, and the variables Actions sets.
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
    status=$(api POST "issues/$PULL_REQUEST/comments" \
        --data "$(body "$marker
A second summary comment, planted for Steward to delete.")")
    expect "Planting a second summary" 201 "$status"
    echo "id=$(jq -r .id "$response")" >>"$GITHUB_OUTPUT"
    ;;
gone)
    expect "Reading the planted summary" 404 "$(api GET "issues/comments/$2")"
    expect "Listing the comments" 200 "$(api GET "issues/$PULL_REQUEST/comments?per_page=100")"
    summaries=$(jq --arg marker "$marker" \
        '[.[] | select(.user.login == "github-actions[bot]" and (.body | startswith($marker)))] | length' \
        "$response")
    expect "Summary comments left" 1 "$summaries"
    ;;
*)
    echo "Usage: comments.sh probe allowed|forbidden | plant | gone <id>" >&2
    exit 2
    ;;
esac
