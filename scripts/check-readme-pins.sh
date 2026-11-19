#!/usr/bin/env bash
# Checks that every `marosoaie/steward-action@…` pin in the file $2
# (README.md if not given) names the tag v$1, and that there's at least
# one. A release moves the README's pins to its own tag before it's tagged,
# so that each tag's README names that tag; the release workflow runs this
# just before tagging. Locally:
#   scripts/check-readme-pins.sh 0.1.2
#
# Like check-release-version.sh, it runs nothing but bash, so no program's
# failure can read as "no pin there".
set -euo pipefail
export LC_ALL=C

version=${1-}
file=${2-README.md}
if [[ -z $version ]]; then
  echo "Usage: $0 VERSION [FILE]" >&2
  exit 1
fi
tag=v$version

# The ref runs to the first space, quote, backtick, `#` or `)`, so a ref
# that only starts with the tag, such as v0.1.20 for v0.1.2, doesn't pass.
pattern='marosoaie/steward-action@([^[:space:]`"'\''#)]*)'

count=0 wrong=0 number=0
while IFS= read -r line || [[ -n $line ]]; do
  number=$((number + 1))
  # Each pass removes the pin it matched, so a line with two is read twice.
  while [[ $line =~ $pattern ]]; do
    count=$((count + 1))
    if [[ ${BASH_REMATCH[1]} != "$tag" ]]; then
      printf '%s:%d pins @%s, not @%s\n' "$file" "$number" "${BASH_REMATCH[1]}" "$tag" >&2
      wrong=$((wrong + 1))
    fi
    line=${line#*"${BASH_REMATCH[0]}"}
  done
done <"$file"

if ((count == 0)); then
  echo "$file has no marosoaie/steward-action@ pin" >&2
  exit 1
fi
if ((wrong > 0)); then
  echo "Not every pin in $file names $tag ($wrong of $count): a release moves them to its own tag before it's tagged" >&2
  exit 1
fi
echo "Each of the $count pins in $file names $tag."
