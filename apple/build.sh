#!/usr/bin/env bash
# apple/build.sh - build an Xcode project/workspace (iOS or macOS app) or a
# Swift package (macOS command-line tools) on a macOS runner. Used by the
# build-apple.yml reusable workflow; runs only on a Mac with Xcode.
#
# Environment (all optional):
#   PLATFORM         ios (default) or macos
#   PROJECT          .xcworkspace, .xcodeproj, or a folder with one of them or a
#                    Package.swift (default: the current folder)
#   SCHEME           Xcode scheme (default: the one named like the project, else the first)
#   CONFIGURATION    Release (default)
#   EXPORT_METHOD    with a certificate: app-store-connect (default for iOS),
#                    release-testing, enterprise, debugging, developer-id (default
#                    for macOS) or mac-application
#   XCODEBUILD_ARGS  extra xcodebuild (or swift build) arguments
#   OUTPUT_DIR       where results go (default $RUNNER_TEMP/macbin-apple)
#   NAME, LABEL      file name parts: <NAME>-<LABEL>-<platform>.<ext>
# Signing (without a certificate the app is built unsigned / ad-hoc signed):
#   CERT_P12_BASE64, CERT_PASSWORD   signing certificate (.p12, base64)
#   PROFILES_BASE64  provisioning profile(s), base64, comma-separated
#   ASC_KEY_P8, ASC_KEY_ID, ASC_ISSUER_ID
#                    App Store Connect API key, for NOTARIZE and UPLOAD
#   NOTARIZE         1 = notarize and staple (macOS, developer-id)
#   UPLOAD           1 = upload to App Store Connect / TestFlight (app-store-connect)
set -Eeuo pipefail

# macOS ships bash 3.2; use Homebrew's bash (preinstalled on GitHub's runners).
if (( BASH_VERSINFO[0] < 4 )); then
  for b in /opt/homebrew/bin/bash /usr/local/bin/bash; do
    if [[ -x $b ]]; then exec "$b" "$0" "$@"; fi
  done
  echo "::error title=MacBin::apple/build.sh needs bash 4 or newer (brew install bash)" >&2
  exit 1
fi

log()  { printf '[macbin-apple] %s\n' "$*" >&2; }
die()  { printf '::error title=MacBin::%s\n' "$*" >&2; exit 1; }

[[ $(uname -s) == Darwin ]] || die "build-apple needs a macOS runner (runs-on: macos-latest or a self-hosted Mac)"

PLATFORM=${PLATFORM:-ios}
PROJECT=${PROJECT:-.}
SCHEME=${SCHEME:-}
CONFIGURATION=${CONFIGURATION:-Release}
XCODEBUILD_ARGS=${XCODEBUILD_ARGS:-}
OUTPUT_DIR=${OUTPUT_DIR:-${RUNNER_TEMP:-/tmp}/macbin-apple}
NAME=${NAME:-${GITHUB_REPOSITORY##*/}}
NOTARIZE=${NOTARIZE:-0} UPLOAD=${UPLOAD:-0}
CERT_P12_BASE64=${CERT_P12_BASE64:-} CERT_PASSWORD=${CERT_PASSWORD:-} PROFILES_BASE64=${PROFILES_BASE64:-}
ASC_KEY_P8=${ASC_KEY_P8:-} ASC_KEY_ID=${ASC_KEY_ID:-} ASC_ISSUER_ID=${ASC_ISSUER_ID:-}
case $PLATFORM in
  ios) DESTINATION='generic/platform=iOS' EXPORT_METHOD=${EXPORT_METHOD:-app-store-connect} ;;
  macos) DESTINATION='generic/platform=macOS' EXPORT_METHOD=${EXPORT_METHOD:-developer-id} ;;
  *) die "unsupported platform '$PLATFORM' (use ios or macos)" ;;
esac
if [[ -z ${LABEL:-} ]]; then
  if [[ ${GITHUB_REF_TYPE:-} == tag ]]; then
    LABEL=$GITHUB_REF_NAME
  else
    branch=${GITHUB_HEAD_REF:-${GITHUB_REF_NAME:-local}}
    LABEL="${branch//\//-}-$(git rev-parse --short=7 HEAD 2>/dev/null || echo build)"
  fi
fi
[[ -n $NAME ]] || NAME=$(basename "$PWD")
BASE="$NAME-$LABEL-$PLATFORM"
read -ra extra <<<"$XCODEBUILD_ARGS"

WORK=$(mktemp -d "${RUNNER_TEMP:-/tmp}/macbin-apple.XXXXXX")
KEYCHAIN=''
cleanup() {
  if [[ -n $KEYCHAIN ]]; then security delete-keychain "$KEYCHAIN" 2>/dev/null || true; fi
  rm -rf "$WORK"
}
trap cleanup EXIT
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR=$(cd "$OUTPUT_DIR" && pwd)

# Pipes xcodebuild through xcbeautify when the runner has it.
pretty() { if command -v xcbeautify >/dev/null; then xcbeautify; else cat; fi; }

# ------------------------------------------------------------------ project --
PROJ_ARGS=() KIND=''
find_project() {
  local p=$PROJECT found
  if [[ -d $p && $p != *.xcworkspace && $p != *.xcodeproj ]]; then
    found=$(find "$p" -maxdepth 1 -name '*.xcworkspace' | head -n1)
    [[ -n $found ]] || found=$(find "$p" -maxdepth 1 -name '*.xcodeproj' | head -n1)
    if [[ -z $found && -f $p/Package.swift ]]; then KIND=swiftpm PROJECT=$p; return; fi
    [[ -n $found ]] || die "no .xcworkspace, .xcodeproj or Package.swift in '$p' (set project)"
    p=$found
  fi
  case $p in
    *.xcworkspace) PROJ_ARGS=(-workspace "$p") ;;
    *.xcodeproj) PROJ_ARGS=(-project "$p") ;;
    *) die "project '$p' is not an .xcworkspace or .xcodeproj" ;;
  esac
  KIND=xcode PROJECT=$p
}

pick_scheme() {
  [[ -n $SCHEME ]] && return
  local want
  want=$(basename "${PROJECT%.*}")
  SCHEME=$(xcodebuild -list -json "${PROJ_ARGS[@]}" 2>/dev/null | python3 -c '
import json, sys
d = json.load(sys.stdin)
schemes = (d.get("workspace") or d.get("project") or {}).get("schemes", [])
want = sys.argv[1]
print(want if want in schemes else (schemes[0] if schemes else ""))
' "$want")
  [[ -n $SCHEME ]] || die "no shared scheme found in $PROJECT (set scheme)"
}

# ------------------------------------------------------------------ signing --
SIGNED=0 IDENTITY='' TEAM_ID='' PROFILE_MAP=() PROFILE_NAMES=()
setup_signing() {
  [[ -n $CERT_P12_BASE64 ]] || { log "no certificate given: building unsigned"; return 0; }
  SIGNED=1
  KEYCHAIN=$WORK/macbin.keychain-db
  local kpass p12=$WORK/cert.p12
  kpass=$(uuidgen)
  printf '%s' "$CERT_P12_BASE64" | base64 -D >"$p12" || die "the certificate is not valid base64"
  security create-keychain -p "$kpass" "$KEYCHAIN"
  security set-keychain-settings -lut 21600 "$KEYCHAIN"
  security unlock-keychain -p "$kpass" "$KEYCHAIN"
  security import "$p12" -P "$CERT_PASSWORD" -A -f pkcs12 -k "$KEYCHAIN" >/dev/null
  security set-key-partition-list -S apple-tool:,apple:,codesign: -k "$kpass" "$KEYCHAIN" >/dev/null
  # shellcheck disable=SC2046 # the existing keychain list is one path per word
  security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"')
  IDENTITY=$(security find-identity -v -p codesigning "$KEYCHAIN" | awk 'NR == 1 && $2 ~ /^[0-9A-F]{40}$/ { print $2 }')
  [[ -n $IDENTITY ]] || die "the certificate holds no code signing identity"
  log "signing identity: $(security find-identity -v -p codesigning "$KEYCHAIN" | sed -n '1s/^[^"]*//p')"

  local b64 i=0 prof plist uuid name team appid
  local dirs=("$HOME/Library/MobileDevice/Provisioning Profiles"
              "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles")
  mkdir -p "${dirs[@]}"
  IFS=',' read -ra profiles <<<"$PROFILES_BASE64"
  for b64 in "${profiles[@]}"; do
    b64=${b64//[[:space:]]/}
    [[ -n $b64 ]] || continue
    i=$((i + 1))
    prof=$WORK/profile$i.provisionprofile plist=$WORK/profile$i.plist
    printf '%s' "$b64" | base64 -D >"$prof" || die "provisioning profile $i is not valid base64"
    security cms -D -i "$prof" >"$plist" || die "provisioning profile $i cannot be read"
    uuid=$(/usr/libexec/PlistBuddy -c 'Print :UUID' "$plist")
    name=$(/usr/libexec/PlistBuddy -c 'Print :Name' "$plist")
    team=$(/usr/libexec/PlistBuddy -c 'Print :TeamIdentifier:0' "$plist")
    appid=$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' "$plist" 2>/dev/null \
            || /usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.application-identifier' "$plist")
    for d in "${dirs[@]}"; do cp "$prof" "$d/$uuid.mobileprovision"; cp "$prof" "$d/$uuid.provisionprofile"; done
    PROFILE_MAP+=("${appid#*.}" "$name")
    PROFILE_NAMES+=("$name")
    TEAM_ID=$team
    log "provisioning profile: $name (${appid#*.})"
  done
  if [[ -z $TEAM_ID ]]; then
    # Developer ID certificates name the team as "...(TEAMID)".
    TEAM_ID=$(security find-identity -v -p codesigning "$KEYCHAIN" | sed -n '1s/.*(\([A-Z0-9]\{10\}\))".*/\1/p')
  fi
}

write_export_options() {
  local plist=$1 i
  /usr/libexec/PlistBuddy -c "Add :method string $EXPORT_METHOD" "$plist" >/dev/null
  /usr/libexec/PlistBuddy -c 'Add :signingStyle string manual' "$plist"
  /usr/libexec/PlistBuddy -c "Add :signingCertificate string $IDENTITY" "$plist"
  if [[ -n $TEAM_ID ]]; then /usr/libexec/PlistBuddy -c "Add :teamID string $TEAM_ID" "$plist"; fi
  if (( UPLOAD )); then /usr/libexec/PlistBuddy -c 'Add :destination string upload' "$plist"; fi
  if (( ${#PROFILE_MAP[@]} )); then
    /usr/libexec/PlistBuddy -c 'Add :provisioningProfiles dict' "$plist"
    for (( i = 0; i < ${#PROFILE_MAP[@]}; i += 2 )); do
      /usr/libexec/PlistBuddy -c "Add :provisioningProfiles:${PROFILE_MAP[i]} string ${PROFILE_MAP[i+1]}" "$plist"
    done
  fi
}

ASC_ARGS=()
setup_api_key() {
  [[ -n $ASC_KEY_P8 ]] || return 0
  [[ -n $ASC_KEY_ID && -n $ASC_ISSUER_ID ]] || die "the App Store Connect key needs its key ID and issuer ID"
  printf '%s\n' "$ASC_KEY_P8" >"$WORK/AuthKey_$ASC_KEY_ID.p8"
  ASC_ARGS=(-authenticationKeyPath "$WORK/AuthKey_$ASC_KEY_ID.p8"
            -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
}

notarize() {
  local zip=$1 app=${2:-}
  [[ $SIGNED == 1 && $EXPORT_METHOD == developer-id ]] || die "notarizing needs a Developer ID certificate"
  [[ -n $ASC_KEY_P8 ]] || die "notarizing needs the App Store Connect API key"
  log "notarizing $(basename "$zip")"
  xcrun notarytool submit "$zip" --key "$WORK/AuthKey_$ASC_KEY_ID.p8" --key-id "$ASC_KEY_ID" \
    --issuer "$ASC_ISSUER_ID" --wait --timeout 1h
  if [[ -n $app ]]; then
    xcrun stapler staple "$app"
    rm -f "$zip"
    ditto -c -k --keepParent "$app" "$zip"
  fi
}

# -------------------------------------------------------------------- xcode --
build_xcode() {
  pick_scheme
  log "building scheme '$SCHEME' of $PROJECT for $PLATFORM ($CONFIGURATION)"
  local archive=$WORK/$SCHEME.xcarchive sign=()
  if (( SIGNED )); then
    sign=(CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=$IDENTITY" "OTHER_CODE_SIGN_FLAGS=--keychain $KEYCHAIN")
    if [[ -n $TEAM_ID ]]; then sign+=("DEVELOPMENT_TEAM=$TEAM_ID"); fi
    # One profile can be applied to the whole build; with several, the project
    # has to name them per target.
    if (( ${#PROFILE_NAMES[@]} == 1 )); then sign+=("PROVISIONING_PROFILE_SPECIFIER=${PROFILE_NAMES[0]}"); fi
  else
    sign=(CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=)
  fi
  xcodebuild archive "${PROJ_ARGS[@]}" -scheme "$SCHEME" -configuration "$CONFIGURATION" \
    -destination "$DESTINATION" -archivePath "$archive" "${sign[@]}" "${extra[@]}" | pretty

  local apps=("$archive"/Products/Applications/*.app)
  [[ -d ${apps[0]} ]] || die "the archive contains no app (is '$SCHEME' an application scheme?)"
  (cd "$archive" && zip -q -r -y "$OUTPUT_DIR/$BASE-dSYMs.zip" dSYMs) 2>/dev/null || true

  if (( ! SIGNED )); then
    if [[ $PLATFORM == ios ]]; then
      # Unsigned .ipa, for re-signing tools (AltStore, Sideloadly, ...).
      mkdir -p "$WORK/ipa/Payload"
      cp -R "${apps[0]}" "$WORK/ipa/Payload/"
      (cd "$WORK/ipa" && zip -q -r -y "$OUTPUT_DIR/$BASE-unsigned.ipa" Payload)
    else
      cp -R "${apps[0]}" "$WORK/"
      local app
      app=$WORK/$(basename "${apps[0]}")
      codesign --force --deep --sign - "$app" # Apple Silicon needs at least an ad-hoc signature
      ditto -c -k --keepParent "$app" "$OUTPUT_DIR/$BASE.zip"
    fi
    return
  fi

  local opts=$WORK/ExportOptions.plist export=$WORK/export f
  write_export_options "$opts"
  xcodebuild -exportArchive -archivePath "$archive" -exportPath "$export" \
    -exportOptionsPlist "$opts" "${ASC_ARGS[@]}" | pretty
  if (( UPLOAD )); then log "uploaded to App Store Connect"; fi
  for f in "$export"/*.ipa "$export"/*.pkg; do
    if [[ -f $f ]]; then cp "$f" "$OUTPUT_DIR/$BASE.${f##*.}"; fi
  done
  for f in "$export"/*.app; do
    [[ -d $f ]] || continue
    ditto -c -k --keepParent "$f" "$OUTPUT_DIR/$BASE.zip"
    if (( NOTARIZE )); then notarize "$OUTPUT_DIR/$BASE.zip" "$f"; fi
  done
}

# ------------------------------------------------------------ swift package --
build_swiftpm() {
  [[ $PLATFORM == macos ]] || die "Swift packages are built as macOS command-line tools (set platform: macos)"
  log "building Swift package $PROJECT (universal)"
  local args=(-c "${CONFIGURATION,,}" --arch arm64 --arch x86_64 --package-path "$PROJECT")
  swift build "${args[@]}" "${extra[@]}"
  local bin out=$WORK/$BASE p
  bin=$(swift build "${args[@]}" --show-bin-path)
  mkdir -p "$out"
  while IFS= read -r p; do
    [[ -f $bin/$p ]] && cp "$bin/$p" "$out/"
  done < <(swift package --package-path "$PROJECT" describe --type json | python3 -c '
import json, sys
for p in json.load(sys.stdin).get("products", []):
    if "executable" in p.get("type", {}): print(p["name"])
')
  [[ -n $(ls -A "$out") ]] || die "the package has no executable products"
  local f
  for f in "$out"/*; do
    if (( SIGNED )); then
      codesign --force --options runtime --timestamp --keychain "$KEYCHAIN" --sign "$IDENTITY" "$f"
    else
      codesign --force --sign - "$f"
    fi
  done
  for f in "$PROJECT"/LICENSE* "$PROJECT"/README*; do if [[ -f $f ]]; then cp "$f" "$out/"; fi; done
  (cd "$out" && zip -q -r -y "$OUTPUT_DIR/$BASE.zip" .)
  if (( NOTARIZE )); then notarize "$OUTPUT_DIR/$BASE.zip"; fi
}

# --------------------------------------------------------------------- main --
find_project
setup_signing
setup_api_key
if [[ $KIND == swiftpm ]]; then build_swiftpm; else build_xcode; fi

mapfile -t files < <(find "$OUTPUT_DIR" -maxdepth 1 -type f -name "$BASE*" | sort)
(( ${#files[@]} || UPLOAD )) || die "the build produced no files"
{
  echo "output-dir=$OUTPUT_DIR"
  echo "files<<MACBIN_EOF"
  printf '%s\n' "${files[@]}"
  echo "MACBIN_EOF"
} >>"${GITHUB_OUTPUT:-/dev/null}"
{
  echo "### MacBin ($PLATFORM): \`$BASE\`"
  echo
  echo "| File | Size |"
  echo "|---|---|"
  for f in "${files[@]}"; do echo "| \`$(basename "$f")\` | $(( $(stat -f %z "$f") / 1024 )) KiB |"; done
} >>"${GITHUB_STEP_SUMMARY:-/dev/null}"
log "output: ${files[*]}"
