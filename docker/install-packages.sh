#!/bin/sh
# Installs the build tools MacBin uses into the runner base image (see
# Dockerfile): LLVM's Mach-O tools, CMake, Meson, Autotools and friends. The
# compilers themselves come from zig (docker/install-toolchain.sh).
set -eu

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates curl git openssh-client \
  build-essential pkg-config pkgconf \
  llvm-18 \
  cmake ninja-build meson \
  autoconf automake autopoint libtool gettext bison flex gperf texinfo \
  nasm yasm patch file \
  python3 python3-pip python3-venv \
  zip unzip xz-utils bzip2 zstd
rm -rf /var/lib/apt/lists/*
