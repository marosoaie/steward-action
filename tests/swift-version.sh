#!/usr/bin/env bash
# Checks which swift-version values setup-swift.sh accepts. A value that
# starts with `-` would reach swiftly as an option, so it's refused.
#
# The script runs with a `uname` that names an unsupported OS, so an
# accepted value stops at the OS check, before it installs anything.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
bin=$(mktemp -d)
trap 'rm -rf "$bin"' EXIT
printf '#!/bin/sh\necho Plan9\n' >"$bin/uname"
chmod +x "$bin/uname"

refused="swift-version is a version such as"
unsupported="this one runs Plan9"
failures=0

# Expects setup-swift.sh, given SWIFT_VERSION=$1, to fail with $2 in its
# output.
check() {
    local version=$1 expected=$2 output
    if output=$(PATH="$bin:$PATH" SWIFT_VERSION=$version GITHUB_OUTPUT=/dev/null "$root/scripts/setup-swift.sh" 2>&1); then
        echo "FAIL \"$version\": succeeded"
        failures=$((failures + 1))
    elif [[ $output != *"$expected"* ]]; then
        echo "FAIL \"$version\": $output"
        failures=$((failures + 1))
    else
        echo "ok   \"$version\""
    fi
}

for version in "" 6.2 6.2.1 6.3-snapshot main-snapshot-2026-11-01 latest; do
    check "$version" "$unsupported"
done
for version in - -h --help --post-install-file=x -6.2 "6.2 -h" "6.2;true" "\$(true)" ../6.2/x; do
    check "$version" "$refused"
done

[ "$failures" = 0 ]
