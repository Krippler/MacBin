#!/usr/bin/env bash
# Tests the Windows GitHub Action (windows/action/run.sh) the way CI Runner
# Farm runs it: inside the MacBin runner image, as the non-root "runner" user.
# Ported from WinBin's tests/run-runner-tests.sh.
#
# Usage: tests/run-windows-tests.sh <runner-image> [zip-dir]
# The produced zips are copied to zip-dir (if given) so tests/run-on-windows.sh
# can run the executables on Windows.
set -Eeuo pipefail

RUNNER_IMAGE=${1:?runner image}
ZIP_DIR=${2:-}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
fail=0
out=$(mktemp -d)
chmod 777 "$out"

echo "::group::Windows action in runner image ($RUNNER_IMAGE)"
docker run --rm -u runner --entrypoint bash \
  -v "$ROOT/tests/fixtures:/fixtures:ro" -v "$ROOT/windows/action:/action:ro" -v "$out:/out" \
  "$RUNNER_IMAGE" -c '
set -euo pipefail
export GITHUB_ACTIONS=true RUNNER_TEMP=/tmp/rt GITHUB_REF_TYPE=branch GITHUB_REF_NAME=main
export GITHUB_SHA=0123456789abcdef GITHUB_OUTPUT=/tmp/gh-output GITHUB_STEP_SUMMARY=/tmp/gh-summary
export IN_SOURCE=. IN_REF= IN_ENV= IN_OUTPUT_DIR= IN_NAME= IN_LABEL= IN_TOKEN= IN_STATIC=false
export ARCH=both BUILD_SYSTEM=auto BUILD_CMD= SUBDIR= CMAKE_ARGS= MESON_ARGS= CONFIGURE_ARGS= MAKE_ARGS= CARGO_ARGS= GO_PACKAGES= ARTIFACTS=
[ "$(id -un)" = runner ] || { echo "FAIL: not running as runner"; exit 1; }
rc=0
for fx in c-cmake cpp-meson c-autotools c-make rust-cargo go-mod; do
  rm -rf "/tmp/ws/$fx" && mkdir -p /tmp/ws && cp -r "/fixtures/$fx" "/tmp/ws/$fx"
  : >"$GITHUB_OUTPUT"
  if ! (cd "/tmp/ws/$fx" && GITHUB_WORKSPACE=$PWD GITHUB_REPOSITORY=test/$fx /action/run.sh) >"/tmp/$fx.log" 2>&1; then
    tail -30 "/tmp/$fx.log"; echo "FAIL: $fx"; rc=1; continue
  fi
  dir=$(sed -n "s/^output-dir=//p" "$GITHUB_OUTPUT")
  [ "$dir" = "/tmp/rt/winbin/output/$fx/main-0123456" ] || { echo "FAIL: $fx: unexpected output-dir $dir"; rc=1; }
  for win in win64 win32; do
    zip=$(sed -n "/^zips<</,/^WINBIN_EOF/p" "$GITHUB_OUTPUT" | grep -- "-$win.zip" || true)
    [ -f "$zip" ] || { echo "FAIL: $fx: missing $win zip"; rc=1; continue; }
    cp "$zip" /out/
  done
  n=$(find "$dir" -name "*.exe" | xargs -r file | grep -c "PE32" || true)
  [ "$n" -ge 2 ] && echo "ok:   $fx ($n exe, as $(id -un))" || { echo "FAIL: $fx: no PE executables"; rc=1; }
done
grep -q "MacBin (Windows)" "$GITHUB_STEP_SUMMARY" || { echo "FAIL: no step summary"; rc=1; }

# Tag build: label from the tag, static linking, options via the env input.
rm -rf /tmp/ws/tagged && cp -r /fixtures/cpp-meson /tmp/ws/tagged
: >"$GITHUB_OUTPUT"
if (cd /tmp/ws/tagged && GITHUB_WORKSPACE=$PWD GITHUB_REPOSITORY=test/tagged GITHUB_REF_TYPE=tag \
      GITHUB_REF_NAME=v1.0 IN_STATIC=true ARCH=x86_64 IN_ENV="$(printf "# comment\nSTRIP_BINARIES=0")" \
      /action/run.sh) >/tmp/tagged.log 2>&1; then
  dir=$(sed -n "s/^output-dir=//p" "$GITHUB_OUTPUT")
  if [ "$dir" = /tmp/rt/winbin/output/tagged/v1.0 ] && file "$dir/win64/bin/hello_meson.exe" | grep -q "PE32+" \
     && [ ! -e "$dir/win64/bin/libwinpthread-1.dll" ]; then
    echo "ok:   tag label, static build, env input"
  else
    echo "FAIL: tagged build output: $dir"; ls -R "$dir" || true; rc=1
  fi
else
  tail -30 /tmp/tagged.log; echo "FAIL: tagged build"; rc=1
fi
exit $rc
' || fail=1
echo "::endgroup::"

if [[ -n $ZIP_DIR ]]; then
  mkdir -p "$ZIP_DIR"
  cp "$out"/*.zip "$ZIP_DIR"/ 2>/dev/null || true
fi
rm -rf "$out" 2>/dev/null || true
(( fail == 0 )) && echo "windows tests passed"
exit "$fail"
