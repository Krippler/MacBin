#!/usr/bin/env bash
# Runs the binaries tests/run-runner-tests.sh cross-compiled, on a real Mac:
# each must pass codesign --verify and print its "hello from ..." line.
#
# Usage: tests/run-on-mac.sh <zip-dir>
set -Eeuo pipefail

dir=${1:?zip dir}
rosetta=0
if arch -x86_64 /usr/bin/true 2>/dev/null; then rosetta=1; fi
[[ $(uname -m) == arm64 ]] || rosetta=1 # Intel Macs run x86_64 natively
fail=0 ran=0

for zip in "$dir"/*.zip; do
  x=$(mktemp -d)
  ditto -x -k "$zip" "$x"
  while IFS= read -r -d '' bin; do
    file "$bin" | grep -q 'Mach-O.*executable' || continue
    codesign --verify "$bin" || { echo "FAIL: $(basename "$zip"): ${bin#"$x"/} has no valid signature"; fail=1; }
    for a in arm64 x86_64; do
      lipo -archs "$bin" | grep -qw "$a" || continue
      [[ $a == x86_64 && $rosetta == 0 ]] && continue
      if out=$(arch "-$a" "$bin" 2>&1) && grep -q '^hello from' <<<"$out"; then
        echo "ok:   $(basename "$zip"): ${bin#"$x"/} ($a): $out"
        ran=$((ran + 1))
      else
        echo "FAIL: $(basename "$zip"): ${bin#"$x"/} ($a): $out"; fail=1
      fi
    done
  done < <(find "$x" -type f -perm -u+x -print0)
  rm -rf "$x"
done

(( ran > 0 )) || { echo "FAIL: nothing ran"; fail=1; }
(( rosetta )) || echo "note: Rosetta is not installed, x86_64 binaries were not run"
exit "$fail"
