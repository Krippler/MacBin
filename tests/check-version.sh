#!/usr/bin/env bash
# Checks that every place carrying MacBin's version agrees with
# MACBIN_VERSION in lib/common.sh (see RELEASING.md).
set -Eeuo pipefail

cd "$(dirname "$0")/.."
v=$(sed -n 's/^MACBIN_VERSION="\(.*\)"$/\1/p' lib/common.sh)
[[ $v =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "::error::MACBIN_VERSION is not X.Y.Z: '$v'"; exit 1; }
fail=0
bad() { echo "::error file=$1::$2"; fail=1; }

grep -q "uses: Krippler/MacBin@v$v\$" .github/workflows/build-macos.yml \
  || bad .github/workflows/build-macos.yml "the action must be Krippler/MacBin@v$v"
grep -q "ref: v$v\$" .github/workflows/build-apple.yml \
  || bad .github/workflows/build-apple.yml "the script checkout must be ref: v$v"
# shellcheck disable=SC2016 # the backtick is a literal markdown character here
while IFS= read -r ref; do
  [[ $ref == "@v$v" ]] || bad README.md "workflow reference $ref should be @v$v"
done < <(grep -o 'Krippler/MacBin/[^ `)]*@[^ `)]*' README.md | grep -o '@.*$')
grep -q "runner-base-$v\$" README.md || bad README.md "the setup FROM line should use runner-base-$v"
grep -q "uses: Krippler/MacBin/windows@v$v\$" .github/workflows/build-windows.yml \
  || bad .github/workflows/build-windows.yml "the action must be Krippler/MacBin/windows@v$v"

# The newest version in the changelog is MACBIN_VERSION ([Unreleased] may sit above it).
top=$(sed -nE 's/^## \[([0-9]+\.[0-9]+\.[0-9]+)\].*/\1/p' CHANGELOG.md | head -n1)
[[ $top == "$v" ]] || bad CHANGELOG.md "the newest version section is [$top], MACBIN_VERSION is $v"

(( fail == 0 )) && echo "version $v is consistent"
exit "$fail"
