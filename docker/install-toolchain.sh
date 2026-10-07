#!/usr/bin/env bash
# Installs zig and cargo-zigbuild (pinned, from PyPI) and links the macOS cross
# tools (docker/macbin-tool) into /opt/macbin/toolchain/bin. Then builds zig's
# libc++ for both targets once, so jobs don't start with a long compile.
#   ZIG_VERSION, CARGO_ZIGBUILD_VERSION  package versions to install
set -euo pipefail

tc=/opt/macbin/toolchain
python3 -m venv "$tc/venv"
"$tc/venv/bin/pip" install --no-cache-dir -q \
  "ziglang==$ZIG_VERSION" "cargo-zigbuild==$CARGO_ZIGBUILD_VERSION"

mkdir -p "$tc/bin"
zig=$(echo "$tc"/venv/lib/python3*/site-packages/ziglang/zig)
ln -s "$zig" "$tc/bin/zig"
ln -s "$tc/venv/bin/cargo-zigbuild" "$tc/bin/cargo-zigbuild"
install -m 755 /tmp/macbin-tool "$tc/bin/macbin-tool"
for triple in aarch64-apple-darwin arm64-apple-darwin x86_64-apple-darwin; do
  for t in cc gcc clang c++ g++ clang++ ar ranlib nm strip otool lipo objdump \
           install_name_tool dsymutil; do
    ln -s macbin-tool "$tc/bin/$triple-$t"
  done
done
for t in lipo otool install_name_tool; do ln -s macbin-tool "$tc/bin/$t"; done
"$tc/bin/zig" version

# Warm the zig cache (the runner user's, see Dockerfile) with libc++.
export PATH=$tc/bin:$PATH
w=$(mktemp -d)
printf '#include <iostream>\n#include <thread>\nint main(){std::thread t([]{std::cout<<1;});t.join();}\n' >"$w/w.cpp"
for triple in aarch64-apple-darwin x86_64-apple-darwin; do
  "$triple-c++" -O2 "$w/w.cpp" -o "$w/w" 2>/dev/null
  "$triple-c++" -O2 -shared "$w/w.cpp" -o "$w/w.dylib" 2>/dev/null
done
rm -rf "$w"
