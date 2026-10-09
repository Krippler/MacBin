#!/bin/sh
# Installs the build tools WMBin uses into the runner base image (see
# Dockerfile): LLVM's Mach-O tools and the MinGW-w64 cross toolchain for
# Windows, CMake, Meson, Autotools and friends. The macOS compilers come from
# zig (docker/install-toolchain.sh).
set -eu

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates curl git openssh-client \
  build-essential pkg-config pkgconf \
  llvm-18 \
  mingw-w64 mingw-w64-tools gcc-mingw-w64 g++-mingw-w64 binutils-mingw-w64 libz-mingw-w64-dev \
  cmake ninja-build meson \
  autoconf automake autopoint libtool gettext bison flex gperf texinfo \
  nasm yasm patch file \
  python3 python3-pip python3-venv \
  zip unzip xz-utils bzip2 zstd
rm -rf /var/lib/apt/lists/*

# The "posix" thread model is needed for std::thread / std::mutex etc.
for t in x86_64 i686; do
  for c in gcc g++ gfortran gnat; do
    if [ -e "/usr/bin/$t-w64-mingw32-$c-posix" ]; then
      update-alternatives --set "$t-w64-mingw32-$c" "/usr/bin/$t-w64-mingw32-$c-posix"
    fi
  done
done
