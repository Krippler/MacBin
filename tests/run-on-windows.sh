#!/usr/bin/env bash
# Runs the executables tests/run-windows-tests.sh cross-compiled, on a real
# Windows machine (Git Bash on GitHub's windows runner): each must print its
# "hello from ..." line. Bundled DLLs have to be found next to the .exe.
#
# Usage: tests/run-on-windows.sh <zip-dir>
set -Eeuo pipefail

dir=${1:?zip dir}
fail=0 ran=0

for zip in "$dir"/*.zip; do
  x=$(mktemp -d)
  powershell -NoProfile -Command \
    "Expand-Archive -LiteralPath '$(cygpath -w "$zip")' -DestinationPath '$(cygpath -w "$x")'"
  while IFS= read -r -d '' exe; do
    if out=$("$exe" 2>&1) && grep -q '^hello from' <<<"${out//$'\r'/}"; then
      echo "ok:   $(basename "$zip"): ${exe#"$x"/}: ${out//$'\r'/}"
      ran=$((ran + 1))
    else
      echo "FAIL: $(basename "$zip"): ${exe#"$x"/}: $out"; fail=1
    fi
  done < <(find "$x" -type f -iname '*.exe' -print0)
  rm -rf "$x"
done

(( ran > 0 )) || { echo "FAIL: nothing ran"; fail=1; }
exit "$fail"
