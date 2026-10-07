#!/usr/bin/env bash
# Tests the GitHub Action (action/run.sh) the way CI Runner Farm runs it:
# inside the MacBin runner image, as the non-root "runner" user.
#
# Usage: tests/run-runner-tests.sh <runner-image> [zip-dir]
# The produced zips are copied to zip-dir (if given) so tests/run-on-mac.sh can
# run the binaries on a real Mac.
set -Eeuo pipefail

RUNNER_IMAGE=${1:?runner image}
ZIP_DIR=${2:-}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
fail=0
out=$(mktemp -d)
chmod 777 "$out"
# A throwaway self-signed certificate for the Developer ID signing path.
cert=$(mktemp -d)
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$cert/key.pem" -out "$cert/cert.pem" \
  -days 1 -subj "/CN=Developer ID Application: MacBin Test (TEST000000)" 2>/dev/null
openssl pkcs12 -export -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 -inkey "$cert/key.pem" -in "$cert/cert.pem" -passout pass:secret \
  -out "$cert/test.p12" 2>/dev/null
chmod 755 "$cert" && chmod 644 "$cert"/*

echo "::group::action in runner image ($RUNNER_IMAGE)"
docker run --rm -u runner --entrypoint bash \
  -v "$ROOT/tests/fixtures:/fixtures:ro" -v "$ROOT/action:/action:ro" -v "$out:/out" -v "$cert:/cert:ro" \
  "$RUNNER_IMAGE" -c '
set -euo pipefail
export GITHUB_ACTIONS=true RUNNER_TEMP=/tmp/rt GITHUB_REF_TYPE=branch GITHUB_REF_NAME=main
export GITHUB_SHA=0123456789abcdef GITHUB_OUTPUT=/tmp/gh-output GITHUB_STEP_SUMMARY=/tmp/gh-summary
export IN_SOURCE=. IN_REF= IN_ENV= IN_OUTPUT_DIR= IN_NAME= IN_LABEL= IN_TOKEN= IN_STATIC=false
export IN_SIGN_P12_BASE64= IN_SIGN_P12_PASSWORD= IN_NOTARY_API_KEY= CODESIGN= MACOS_MIN=
export ARCH=all BUILD_SYSTEM=auto BUILD_CMD= SUBDIR= CMAKE_ARGS= MESON_ARGS= CONFIGURE_ARGS= MAKE_ARGS= CARGO_ARGS= GO_PACKAGES= ARTIFACTS=
[ "$(id -un)" = runner ] || { echo "FAIL: not running as runner"; exit 1; }

# signed FILE - true when every slice of FILE carries a code signature.
signed() {
  local n s
  n=$(lipo -archs "$1" | wc -w)
  s=$(rcodesign print-signature-info "$1" 2>/dev/null | grep -c "^ *flags: CodeSignatureFlags" || true)
  [ "$n" -ge 1 ] && [ "$s" -ge "$n" ]
}

rc=0
for fx in c-cmake cpp-meson c-autotools c-make rust-cargo go-mod; do
  rm -rf "/tmp/ws/$fx" && mkdir -p /tmp/ws && cp -r "/fixtures/$fx" "/tmp/ws/$fx"
  : >"$GITHUB_OUTPUT"
  if ! (cd "/tmp/ws/$fx" && GITHUB_WORKSPACE=$PWD GITHUB_REPOSITORY=test/$fx /action/run.sh) >"/tmp/$fx.log" 2>&1; then
    tail -40 "/tmp/$fx.log"; echo "FAIL: $fx"; rc=1; continue
  fi
  dir=$(sed -n "s/^output-dir=//p" "$GITHUB_OUTPUT")
  [ "$dir" = "/tmp/rt/macbin/output/$fx/main-0123456" ] || { echo "FAIL: $fx: unexpected output-dir $dir"; rc=1; }
  for plat in macos-arm64 macos-x86_64 macos-universal; do
    zip=$(sed -n "/^zips<</,/^MACBIN_EOF/p" "$GITHUB_OUTPUT" | grep -- "-$plat.zip" || true)
    [ -f "$zip" ] || { echo "FAIL: $fx: missing $plat zip"; rc=1; continue; }
    cp "$zip" /out/
  done
  n=0
  for f in $(find "$dir/macos-universal" -type f ! -name "*.txt"); do
    file "$f" | grep -q "Mach-O universal binary with 2 architectures" || continue
    signed "$f" || { echo "FAIL: $fx: ${f#$dir/} is not signed"; rc=1; }
    n=$((n + 1))
  done
  arm=$(find "$dir/macos-arm64" -type f | xargs -r file | grep -c "Mach-O 64-bit arm64" || true)
  x86=$(find "$dir/macos-x86_64" -type f | xargs -r file | grep -c "Mach-O 64-bit x86_64" || true)
  if [ "$n" -ge 1 ] && [ "$arm" = "$n" ] && [ "$x86" = "$n" ]; then
    echo "ok:   $fx ($n universal Mach-O files, as $(id -un))"
  else
    echo "FAIL: $fx: $n universal, $arm arm64, $x86 x86_64 Mach-O files"; rc=1
  fi
done
grep -q "MacBin" "$GITHUB_STEP_SUMMARY" || { echo "FAIL: no step summary"; rc=1; }

# The CMake fixture links its executable against its own dylib: the
# reference must point inside the output, with no build-machine rpaths left.
d=/tmp/rt/macbin/output/c-cmake/main-0123456/macos-arm64
deps=$(otool -L "$d/bin/hello_cmake" 2>/dev/null || true)
if echo "$deps" | grep -q "@loader_path/../lib/libgreet.dylib" && [ -f "$d/lib/libgreet.dylib" ] \
   && ! otool -l "$d/bin/hello_cmake" | grep -A2 LC_RPATH | grep -q /tmp/; then
  echo "ok:   dylib references rewritten"
else
  echo "FAIL: dylib references: $deps"; rc=1
fi

# Tag build: label from the tag, one architecture, options via the env input.
rm -rf /tmp/ws/tagged && cp -r /fixtures/cpp-meson /tmp/ws/tagged
: >"$GITHUB_OUTPUT"
if (cd /tmp/ws/tagged && GITHUB_WORKSPACE=$PWD GITHUB_REPOSITORY=test/tagged GITHUB_REF_TYPE=tag \
      GITHUB_REF_NAME=v1.0 ARCH=arm64 IN_ENV="$(printf "# comment\nCODESIGN=none\nMACOS_MIN=13.0")" \
      /action/run.sh) >/tmp/tagged.log 2>&1; then
  dir=$(sed -n "s/^output-dir=//p" "$GITHUB_OUTPUT")
  f=$dir/macos-arm64/bin/hello_meson
  if [ "$dir" = /tmp/rt/macbin/output/tagged/v1.0 ] && file "$f" | grep -q "Mach-O 64-bit arm64" \
     && [ ! -e "$dir/macos-universal" ] && grep -q "codesign:   none" "$dir/macos-arm64/BUILDINFO.txt" \
     && otool -l "$f" | grep -A4 LC_BUILD_VERSION | grep -q "minos 13.0"; then
    echo "ok:   tag label, single arch, env input"
  else
    echo "FAIL: tagged build output: $dir"; ls -R "$dir" || true; rc=1
  fi
else
  tail -30 /tmp/tagged.log; echo "FAIL: tagged build"; rc=1
fi

# Developer ID signing path, with a throwaway self-signed certificate.
rm -rf /tmp/ws/signed && cp -r /fixtures/c-make /tmp/ws/signed
: >"$GITHUB_OUTPUT"
if (cd /tmp/ws/signed && GITHUB_WORKSPACE=$PWD GITHUB_REPOSITORY=test/signed ARCH=universal \
      IN_SIGN_P12_BASE64=$(base64 -w0 /cert/test.p12) IN_SIGN_P12_PASSWORD=secret \
      IN_ENV=SIGN_TIMESTAMP_URL=none \
      /action/run.sh) >/tmp/signed.log 2>&1; then
  dir=$(sed -n "s/^output-dir=//p" "$GITHUB_OUTPUT")
  if rcodesign print-signature-info "$dir/macos-universal/hello_make" 2>/dev/null | grep -q "MacBin Test" \
     && grep -q "developer-id" "$dir/macos-universal/BUILDINFO.txt" \
     && ! find /tmp/rt -name "macbin-secrets.*" | grep -q .; then
    echo "ok:   Developer ID signing"
  else
    echo "FAIL: Developer ID signing"; tail -20 /tmp/signed.log; rc=1
  fi
else
  tail -30 /tmp/signed.log; echo "FAIL: signed build"; rc=1
fi
exit $rc
' || fail=1
echo "::endgroup::"

if [[ -n $ZIP_DIR ]]; then
  mkdir -p "$ZIP_DIR"
  cp "$out"/*.zip "$ZIP_DIR"/ 2>/dev/null || true
fi
rm -rf "$out" "$cert" 2>/dev/null || true
(( fail == 0 )) && echo "runner tests passed"
exit "$fail"
