# Changelog

All notable changes to WMBin (called MacBin until 0.3.0). Versions follow [Semantic Versioning](https://semver.org/) and
roughly the [Keep a Changelog](https://keepachangelog.com/) format. The top section's heading is
what the release workflow reads: `## [X.Y.Z] — DATE` on `main` publishes that version,
`## [Unreleased]` publishes nothing. See RELEASING.md.

## [0.3.0] — 2026-10-09

### Changed
- **MacBin is now WMBin**, at [github.com/Krippler/WMBin](https://github.com/Krippler/WMBin). The
  runner image moves to `ghcr.io/krippler/wmbin:runner-base-0.3.0`, and workflows are referenced as
  `Krippler/WMBin/.github/workflows/…@v0.3.0`, `Krippler/WMBin@v0.3.0` and
  `Krippler/WMBin/windows@v0.3.0`. README → "Moving from MacBin or WinBin" lists what to switch.
  The old `ghcr.io/krippler/macbin` images stay available; the commands on the runner and the
  `MACBIN_*` settings keep their names.

## [0.2.0] — 2026-10-09

### Added
- **Windows binaries too, from the same runner image.** `runner-base-0.2.0` adds MinGW-w64 and
  the Windows Rust targets, and builds CMake, Meson, Autotools, Make, Cargo and Go projects into
  64-bit and 32-bit Windows `.exe`/`.dll` files with the DLLs they need. Projects use the new
  reusable workflow `build-windows.yml` next to `build-macos.yml`. This is WinBin's Windows
  support moved into MacBin (`windows/`): MacBin needs nothing from WinBin's repository or images,
  so WinBin can be shut down. README → "Moving from WinBin" lists what to switch over first. CI runs the Windows test builds on a real Windows machine before publishing.
- **Farm build for Windows**: repositories in `farm/windows-repos.txt` are built for Windows,
  next to the macOS list in `farm/repos.txt`.

### Changed
- Farm build results are written to `<output>/macos/` and `<output>/windows/`.

## [0.1.0] — 2026-10-07

### Added
- **macOS binaries from the CI Runner Farm.** The runner image
  `ghcr.io/krippler/macbin:runner-base-0.1.0` cross-compiles CMake, Meson, Autotools, Make, Cargo
  and Go projects for Apple Silicon, Intel or both in one universal binary, without a Mac or an
  Apple SDK. The project's own `.dylib`s are included and linked from the zip, and everything is
  signed: ad-hoc by default, or with a Developer ID certificate, with optional notarization.
- **`build-macos.yml`**, a reusable workflow that builds the calling repository on the farm and
  attaches the zips to tag releases, plus **Farm build** for nightly builds of the repositories in
  `farm/repos.txt`.
- **`build-apple.yml`**, a reusable workflow for iOS and macOS apps (Xcode projects) and Swift
  packages on GitHub's macOS runners or your own Mac: an unsigned `.ipa` or ad-hoc signed app
  without secrets, or a signed export with optional notarization and TestFlight upload.
