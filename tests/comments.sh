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
#   comments.sh says <text>...
#       Checks that the oldest summary comment holds each text, and, when
#       ID or UPDATED is set, that its id or the time it was last written is
#       that. Writes both to GITHUB_OUTPUT, as `id` and `updated`.
#   comments.sh clear
#       Deletes every summary comment, so the next one is created.
#   comments.sh touch
#       Rewrites the oldest summary comment, or posts one, as Steward posting
#       would; run by the Dangerfile tests/unfinished's STOP=touch.
#   comments.sh kept <id>
#       Checks that one summary comment is left, the one with this id, and
#       that it no longer says Steward didn't finish.
#
# Needs GITHUB_TOKEN, PULL_REQUEST, the variables Actions sets, and gh.
set -euo pipefail

marker='<!-- steward-summary -->'
response=$(mktemp)
list=$(mktemp)

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

# Lists the summary comments in $list, oldest first, one JSON object a line,
# from every page, as Steward reads them. A file, not a pipe into `head`,
# which under pipefail can fail on SIGPIPE.
summaries() {
    GH_TOKEN=$GITHUB_TOKEN gh api --paginate "repos/$GITHUB_REPOSITORY/issues/$PULL_REQUEST/comments?per_page=100" \
        --jq ".[] | select(.user.login == \"github-actions[bot]\" and (.body | startswith(\"$marker\"))) | {id, body, updated_at}" \
        >"$list"
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
    summaries
    expect "Summary comments left" 1 "$(($(wc -l <"$list")))"
    ;;
says)
    shift
    summaries
    oldest=$(head -n 1 "$list")
    if [ -z "$oldest" ]; then
        echo "::error::The pull request has no summary comment."
        exit 1
    fi
    text=$(jq -r .body <<<"$oldest")
    echo "$text"
    for expected in "$@"; do
        if [[ $text != *"$expected"* ]]; then
            echo "::error::The summary comment doesn't say \"$expected\"."
            exit 1
        fi
    done
    id=$(jq -r .id <<<"$oldest")
    updated=$(jq -r .updated_at <<<"$oldest")
    expect "The summary comment's id" "${ID:-$id}" "$id"
    expect "When it was last written" "${UPDATED:-$updated}" "$updated"
    printf 'id=%s\nupdated=%s\n' "$id" "$updated" >>"$GITHUB_OUTPUT"
    ;;
clear)
    summaries
    while read -r id; do
        expect "Deleting the summary $id" 204 "$(api DELETE "issues/comments/$id")"
    done < <(jq -r .id <"$list")
    ;;
touch)
    summaries
    planted="$marker
Planted by a Dangerfile that then exits with 2, as Steward does when it posts and then can't finish."
    id=$(head -n 1 "$list" | jq -r .id)
    if [ -n "$id" ]; then
        expect "Rewriting the summary" 200 "$(api PATCH "issues/comments/$id" --data "$(body "$planted")")"
    else
        expect "Posting a summary" 201 "$(api POST "issues/$PULL_REQUEST/comments" --data "$(body "$planted")")"
    fi
    ;;
kept)
    summaries
    expect "Summary comments left" 1 "$(($(wc -l <"$list")))"
    expect "The summary comment's id" "$2" "$(jq -r .id <"$list")"
    text=$(jq -r .body <"$list")
    echo "$text"
    if [[ $text == *"Steward didn't finish"* ]]; then
        echo "::error::The summary comment still says Steward didn't finish."
        exit 1
    fi
    ;;
*)
    echo "Usage: comments.sh probe allowed|forbidden | plant | gone <id> | says <text>... | clear | touch | kept <id>" >&2
    exit 2
    ;;
esac
