# Changelog

All notable changes to MacBin. Versions follow [Semantic Versioning](https://semver.org/) and
roughly the [Keep a Changelog](https://keepachangelog.com/) format. The top section's heading is
what the release workflow reads: `## [X.Y.Z] — DATE` on `main` publishes that version,
`## [Unreleased]` publishes nothing. See RELEASING.md.

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
