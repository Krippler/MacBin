# syntax=docker/dockerfile:1
# MacBin runner base: a GitHub Actions self-hosted runner image
# (myoung34/github-runner, Ubuntu 24.04) with zig (as an SDK-free macOS cross
# compiler), LLVM's Mach-O tools, rcodesign, Rust (macOS targets), Go and the
# MacBin build scripts.
#
# Use it as the FROM line of the CI Runner Farm's Dockerfile.github
# (https://github.com/unraid/ci-runner-farm), pinned to a release:
#   FROM ghcr.io/krippler/macbin:runner-base-<version>
ARG GO_VERSION=1.27
ARG RUST_IMAGE=rust:1-bookworm
ARG RUNNER_BASE=myoung34/github-runner:ubuntu-noble

FROM golang:${GO_VERSION} AS go

# rcodesign signs (and notarizes) Mach-O files without a Mac.
FROM ${RUST_IMAGE} AS rcodesign
ARG APPLE_CODESIGN_VERSION=0.29.0
RUN cargo install --locked --root /out apple-codesign --version "$APPLE_CODESIGN_VERSION"

FROM ${RUNNER_BASE}
ARG RUST_TOOLCHAIN=stable
ARG ZIG_VERSION=0.16.0
ARG CARGO_ZIGBUILD_VERSION=0.23.4
USER root

COPY docker/install-packages.sh /tmp/install-packages.sh
RUN /tmp/install-packages.sh && rm /tmp/install-packages.sh

ENV MACBIN_HOME=/opt/macbin \
    RUSTUP_HOME=/usr/local/rustup \
    GOTOOLCHAIN=auto \
    ZIG_GLOBAL_CACHE_DIR=/home/runner/.cache/zig \
    PATH=/opt/macbin/bin:/opt/macbin/toolchain/bin:/usr/local/cargo/bin:/usr/local/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# zig + cargo-zigbuild, the <triple>-cc/c++/... tools, and a warm libc++ cache.
COPY docker/install-toolchain.sh docker/macbin-tool /tmp/
RUN ZIG_VERSION=$ZIG_VERSION CARGO_ZIGBUILD_VERSION=$CARGO_ZIGBUILD_VERSION \
      /tmp/install-toolchain.sh \
 && rm /tmp/install-toolchain.sh /tmp/macbin-tool

COPY --from=rcodesign /out/bin/rcodesign /usr/local/bin/rcodesign

# Rust with the macOS targets. World-writable so the non-root runner user can
# add targets requested by a project's rust-toolchain file.
RUN curl --proto '=https' --tlsv1.2 -sSfo /tmp/rustup-init \
      https://static.rust-lang.org/rustup/dist/x86_64-unknown-linux-gnu/rustup-init \
 && chmod +x /tmp/rustup-init \
 && CARGO_HOME=/usr/local/cargo /tmp/rustup-init -y --no-modify-path --profile minimal \
      --default-toolchain "$RUST_TOOLCHAIN" \
      --target aarch64-apple-darwin --target x86_64-apple-darwin \
 && rm /tmp/rustup-init \
 && chmod -R a+rwX /usr/local/rustup /usr/local/cargo

# Go (cross-compiles to macOS natively).
COPY --from=go /usr/local/go /usr/local/go

COPY lib/ /opt/macbin/lib/
COPY scripts/ /opt/macbin/bin/

# Caches live under the runner's home so the farm's CACHE_MOUNTS can persist
# them (cargo-registry, cargo-git, go-mod, go-build, zig). Pre-created
# runner-owned because Docker creates missing bind-mount parents as root.
ENV CARGO_CACHE=/home/runner/.cargo \
    GOMODCACHE=/home/runner/go/pkg/mod \
    GOCACHE=/home/runner/.cache/go-build
RUN mkdir -p /home/runner/.cargo/registry /home/runner/.cargo/git \
      /home/runner/go/pkg/mod /home/runner/.cache/go-build /home/runner/.cache/zig \
 && chown -R runner:runner /home/runner/.cargo /home/runner/go /home/runner/.cache

LABEL org.opencontainers.image.title="MacBin runner base" \
      org.opencontainers.image.description="GitHub Actions runner with zig, LLVM, rcodesign, Rust and Go for building macOS binaries" \
      org.opencontainers.image.source="https://github.com/Krippler/MacBin" \
      org.opencontainers.image.licenses="GPL-2.0"
