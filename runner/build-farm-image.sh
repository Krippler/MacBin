#!/usr/bin/env bash
# Builds a CI Runner Farm runner image with MacBin's toolchains.
#
# The farm's starter Dockerfile (cgroup/DinD bootstrap, KVM group handling,
# cache directories, dockerd supervisor, health check) is fetched from
# unraid/ci-runner-farm and only its FROM line is replaced with the MacBin
# runner base, so the farm-specific parts are never copied into this repo.
#
# Usage: runner/build-farm-image.sh [tag]
#   FARM_REF      ci-runner-farm git ref to take the starter from (default: main)
#   BASE_IMAGE    runner base to put under it (default: ghcr.io/krippler/macbin:runner-base)
#   FARM_DOCKERFILE  use a local starter file instead of downloading it
#   Extra arguments for "docker build" can be passed in DOCKER_BUILD_ARGS.
set -Eeuo pipefail

TAG=${1:-macbin:runner}
FARM_REF=${FARM_REF:-main}
BASE_IMAGE=${BASE_IMAGE:-ghcr.io/krippler/macbin:runner-base}
STARTER_PATH=src/usr/local/emhttp/plugins/ci-runner-farm/default.github.Dockerfile

ctx=$(mktemp -d)
trap 'rm -rf "$ctx"' EXIT

if [[ -n ${FARM_DOCKERFILE:-} ]]; then
  cp "$FARM_DOCKERFILE" "$ctx/starter.Dockerfile"
else
  curl -fsSL "https://raw.githubusercontent.com/unraid/ci-runner-farm/$FARM_REF/$STARTER_PATH" \
    -o "$ctx/starter.Dockerfile"
fi

# Exactly one FROM is expected; refuse to guess if upstream changes shape.
n=$(grep -c '^FROM ' "$ctx/starter.Dockerfile" || true)
[[ $n == 1 ]] || { echo "expected one FROM line in the farm starter, found $n" >&2; exit 1; }
sed "s|^FROM .*|FROM $BASE_IMAGE|" "$ctx/starter.Dockerfile" >"$ctx/Dockerfile"
{
  echo
  echo "LABEL org.opencontainers.image.title=\"MacBin CI Runner Farm image\" \\"
  echo "      org.opencontainers.image.source=\"https://github.com/Krippler/MacBin\" \\"
  echo "      net.unraid.ci-runner-farm.starter-ref=\"$FARM_REF\""
} >>"$ctx/Dockerfile"

read -ra extra <<<"${DOCKER_BUILD_ARGS:-}"
docker build "${extra[@]}" -t "$TAG" -f "$ctx/Dockerfile" "$ctx"
