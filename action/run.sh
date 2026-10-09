#!/usr/bin/env bash
# Implementation of the WMBin GitHub Action (see action.yml). It runs on
# CI Runner Farm runners that use the WMBin runner image.
set -Eeuo pipefail

err() { printf '::error title=WMBin::%s\n' "$*" >&2; exit 1; }

command -v macbin-build >/dev/null \
  || err "macbin-build is not installed on this runner - run this job on a CI Runner Farm runner using the WMBin runner image"

# --- settings for macbin-build ---------------------------------------------
# The named inputs arrive as environment variables (see action.yml).
case ${IN_STATIC,,} in true|1|yes) export STATIC=1 ;; esac

# Signing material from secrets goes into private files only rcodesign reads.
mkdir -p "${RUNNER_TEMP:-/tmp}"
secrets_dir=$(mktemp -d "${RUNNER_TEMP:-/tmp}/macbin-secrets.XXXXXX")
trap 'rm -rf "$secrets_dir"' EXIT
if [[ -n ${IN_SIGN_P12_BASE64:-} ]]; then
  printf '%s' "$IN_SIGN_P12_BASE64" | base64 -d >"$secrets_dir/sign.p12" \
    || err "the signing certificate is not valid base64"
  export SIGN_P12=$secrets_dir/sign.p12 SIGN_P12_PASSWORD=${IN_SIGN_P12_PASSWORD:-}
fi
if [[ -n ${IN_NOTARY_API_KEY:-} ]]; then
  printf '%s' "$IN_NOTARY_API_KEY" >"$secrets_dir/notary.json"
  export NOTARY_API_KEY=$secrets_dir/notary.json
fi

while IFS= read -r line; do
  line=${line%$'\r'}
  [[ -z ${line//[[:space:]]/} || $line =~ ^[[:space:]]*# ]] && continue
  [[ $line =~ ^([A-Z_][A-Z0-9_]*)=(.*)$ ]] || err "invalid env line: $line (expected KEY=VALUE)"
  export "${BASH_REMATCH[1]}=${BASH_REMATCH[2]}"
done <<<"$IN_ENV"

OUTPUT_DIR=${IN_OUTPUT_DIR:-${RUNNER_TEMP:-/tmp}/macbin/output}
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR=$(cd "$OUTPUT_DIR" && pwd)
export OUTPUT_DIR

# --- what to build -------------------------------------------------------
src=${IN_SOURCE:-.}
ref=$IN_REF
if [[ $src == . || -d $src ]]; then
  src=$(cd "${src/#./${GITHUB_WORKSPACE:-.}}" && pwd)
  # Name after the repository and label after the tag/branch being built.
  export OUTPUT_NAME=${IN_NAME:-${GITHUB_REPOSITORY#*/}}
  if [[ -z $IN_LABEL ]]; then
    if [[ ${GITHUB_REF_TYPE:-} == tag ]]; then
      IN_LABEL=$GITHUB_REF_NAME
    else
      branch=${GITHUB_HEAD_REF:-${GITHUB_REF_NAME:-local}}
      IN_LABEL="${branch//\//-}-${GITHUB_SHA:0:7}"
    fi
  fi
  export OUTPUT_LABEL=$IN_LABEL
else
  if [[ -n $IN_NAME ]]; then export OUTPUT_NAME=$IN_NAME; fi
  if [[ -n $IN_LABEL ]]; then export OUTPUT_LABEL=$IN_LABEL; fi
fi
if [[ -n $IN_TOKEN ]]; then export GITHUB_TOKEN=$IN_TOKEN; fi

rm -f "$OUTPUT_DIR/.macbin-last"
rc=0
macbin-build "$src" "$ref" || rc=$?
(( rc == 0 )) || err "build failed (exit $rc)"

rel=$(cat "$OUTPUT_DIR/.macbin-last" 2>/dev/null) || err "build finished without reporting its output folder"
dest=$OUTPUT_DIR/$rel
mapfile -t zips < <(find "$dest" -maxdepth 1 -name '*.zip' | sort)
{
  echo "output-dir=$dest"
  echo "zips<<MACBIN_EOF"
  printf '%s\n' "${zips[@]}"
  echo "MACBIN_EOF"
} >>"${GITHUB_OUTPUT:-/dev/null}"

{
  echo "### WMBin: \`$rel\`"
  echo
  echo "| File | Size |"
  echo "|---|---|"
  find "$dest" -maxdepth 1 -type f -name '*.zip' -printf '%P\t%s\n' | sort \
    | while IFS=$'\t' read -r f size; do echo "| \`$f\` | $((size / 1024)) KiB |"; done
} >>"${GITHUB_STEP_SUMMARY:-/dev/null}"
echo "WMBin output: $dest"
