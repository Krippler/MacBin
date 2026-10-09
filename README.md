# MacBin

MacBin builds macOS and Windows binaries for your GitHub projects on
[CI Runner Farm](https://github.com/unraid/ci-runner-farm) runners on Unraid, with no Mac, no
Windows machine and no Apple SDK. One runner image covers both:

- **macOS**: zig (as the macOS cross compiler), LLVM's Mach-O tools and
  [rcodesign](https://github.com/indygreg/apple-platform-rs) build for Apple Silicon (arm64), Intel
  (x86_64), or both in one universal binary. MacBin bundles the project's own `.dylib`s, signs
  everything (ad-hoc, or with your Developer ID) and zips the results.
- **Windows**: MinGW-w64 builds 64-bit and/or 32-bit `.exe`/`.dll` files, with the DLLs they need
  copied next to them. See [Windows binaries](#windows-binaries).

Both build CMake, Meson, Autotools, Make, Cargo (Rust) and Go projects. The Windows support used
to be a separate project, WinBin, and now lives entirely in MacBin; see
[Moving from WinBin](#moving-from-winbin).

What the farm can't build for macOS:

- **iOS apps, and macOS apps that use Apple frameworks or Swift** (Cocoa, SwiftUI, Metal, ...).
  These need Xcode and Apple's SDKs, which only run on a Mac. MacBin has a second workflow for them
  that runs on a Mac instead; see [iOS and macOS apps](#ios-and-macos-apps).
- Command-line programs that link an Apple framework, unless you supply an SDK (see `MACOS_SDK`
  under [Options](#options)).

## Setup

In **Settings → Utilities → CI Runner Farm → Runner image**, change the first line of
`Dockerfile.github` to:

```dockerfile
FROM ghcr.io/krippler/macbin:runner-base-0.2.0
```

Leave the rest of the file as it is. Click **Build**, then **Restart** on the Fleet tab. If the
farm's image auto-update is on, the runners pick up the new image on their own.

To update MacBin later, change the version number to a newer `runner-base-X.Y.Z` tag from the
[package page](https://github.com/Krippler/MacBin/pkgs/container/macbin), then Build and Restart
again. Use the same version in the workflow references below (`@vX.Y.Z`).

## Building a project for macOS

Add this workflow to a project the farm runs jobs for:

```yaml
# .github/workflows/macos.yml
on:
  push:
    tags: ["v*"]
  workflow_dispatch:
jobs:
  macos:
    uses: Krippler/MacBin/.github/workflows/build-macos.yml@v0.2.0
    permissions:
      contents: write   # to attach the zips to the release
    with:
      arch: universal
```

The workflow builds the project and uploads the zips as an artifact. When you push a tag, it also
attaches them to that release.

It runs on any `self-hosted` runner. If some of your runners don't use the MacBin image, add a label
that only the MacBin runners have and pass it as `runs-on: '["self-hosted", "your-label"]'`.

### Options

| Input | Default | Description |
|---|---|---|
| `arch` | `universal` | `universal` (one binary for arm64 + x86_64), `arm64`, `x86_64`, `both` (separate zips) or `all` (all three) |
| `macos-min` | `11.0` | Oldest macOS version the binaries run on |
| `static` | `false` | `true` prefers static libraries over `.dylib`s |
| `build-system` | `auto` | Force `cmake`, `meson`, `autotools`, `make`, `cargo` or `go` |
| `build-cmd` | | Your own build command, for projects that need one |
| `subdir` | | Build from a subfolder of the repository |
| `cmake-args`, `meson-args`, `configure-args`, `cargo-args` | | Extra build arguments |
| `artifacts` | | Files to collect (globs), if the automatic detection misses them |
| `codesign` | `adhoc` | `adhoc`, `none`, or `developer-id` (the default when a certificate is given) |
| `env` | | Other settings as `KEY=VALUE` lines, for example `PRE_BUILD_CMD=...`, `MAKE_ARGS=...` or `MACOS_SDK=...` |
| `release` | `true` | Attach the zips to the release on tag builds |

Each architecture gets a zip with the binaries, the project's `.dylib`s, its license and README,
and a `BUILDINFO.txt`. Binaries that load the project's own libraries are pointed at the copies in
the zip (`@loader_path/...`), so the folder can be moved anywhere.

`MACOS_SDK=/path/to/MacOSX.sdk` (through `env`, with the SDK mounted into the runners) lets
programs link Apple frameworks. You have to extract the SDK from Xcode yourself. Apple's license
only allows using it on Apple-branded computers, so check that your setup qualifies.

### Signing and notarization

Apple Silicon Macs only run signed code, so MacBin always signs at least ad-hoc. That's enough for
binaries installed with Homebrew, `curl` or a package manager. Files downloaded in a browser get
quarantined, though: macOS refuses to open them until you run `xattr -d com.apple.quarantine <file>`
or allow them in **System Settings → Privacy & Security**.

To avoid that, sign with a **Developer ID Application** certificate and notarize. This needs a paid
Apple Developer account, but not a Mac. Add these secrets to the calling repository and pass them
on:

| Secret | Content |
|---|---|
| `MACOS_CERTIFICATE` | The certificate exported as `.p12`, base64-encoded (`base64 -w0 cert.p12`) |
| `MACOS_CERTIFICATE_PASSWORD` | The `.p12` password |
| `NOTARY_API_KEY` | Optional: an App Store Connect API key, converted with `rcodesign encode-app-store-connect-api-key -o key.json <issuer-id> <key-id> AuthKey_XXXX.p8`. Its content notarizes the zips. |

```yaml
    uses: Krippler/MacBin/.github/workflows/build-macos.yml@v0.2.0
    secrets: inherit
```

If rcodesign reports a wrong password for a `.p12` exported with OpenSSL 3, export it again with
`openssl pkcs12 -export -legacy ...`.

## Windows binaries

Projects that need Windows builds use `build-windows.yml` on the same runners, in its own workflow
or next to the macOS job:

```yaml
# .github/workflows/binaries.yml
on:
  push:
    tags: ["v*"]
  workflow_dispatch:
jobs:
  macos:
    uses: Krippler/MacBin/.github/workflows/build-macos.yml@v0.2.0
    permissions:
      contents: write
  windows:
    uses: Krippler/MacBin/.github/workflows/build-windows.yml@v0.2.0
    permissions:
      contents: write
    with:
      arch: both
```

Each architecture gets a zip with the binaries, any DLLs they need, the project's license and
README, and a `BUILDINFO.txt`. Projects that need MSVC (`.sln`/MSBuild) or .NET can't be built.

| Input | Default | Description |
|---|---|---|
| `arch` | `x86_64` | `x86_64` (64-bit), `i686` (32-bit) or `both` |
| `static` | `false` | `true` builds executables that don't need the MinGW runtime DLLs |
| `build-system` | `auto` | Force `cmake`, `meson`, `autotools`, `make`, `cargo` or `go` |
| `build-cmd` | | Your own build command, for projects that need one |
| `subdir` | | Build from a subfolder of the repository |
| `cmake-args`, `meson-args`, `configure-args`, `cargo-args` | | Extra build arguments |
| `artifacts` | | Files to collect (globs), if the automatic detection misses them |
| `env` | | Other settings as `KEY=VALUE` lines (see `winbin-build --help`) |
| `release` | `true` | Attach the zips to the release on tag builds |
| `artifact-name` | `windows-binaries` | Name of the uploaded artifact |

On the runner the Windows tools are `winbin-build` and `winbin-batch`, the same commands as in
WinBin, so build scripts written for WinBin keep working.

### Moving from WinBin

MacBin doesn't use anything from WinBin's repository or images, but anything that still points at
WinBin stops working once WinBin is gone. Before shutting it down:

| Where | Change |
|---|---|
| Farm `Dockerfile.github` | `FROM ghcr.io/krippler/winbin:runner-base-…` → `FROM ghcr.io/krippler/macbin:runner-base-0.2.0` |
| Project workflows | `uses: Krippler/WinBin/.github/workflows/build-windows.yml@…` → `uses: Krippler/MacBin/.github/workflows/build-windows.yml@v0.2.0` (same inputs) |
| Workflows using the action directly | `uses: Krippler/WinBin@…` → `uses: Krippler/MacBin/windows@v0.2.0` (same inputs) |
| WinBin's `farm/repos.txt` | Move the lines to MacBin's `farm/windows-repos.txt`, and any `farm/patches/` folders too |
| Farm build output share | Results now go to `windows/` under `MACBIN_OUTPUT_DIR` (see below) |

## Scheduled builds of other repositories

The **Farm build** workflow in this repository builds everything listed in `farm/repos.txt` for
macOS, and everything in `farm/windows-repos.txt` for Windows, every night:

```text
BurntSushi/ripgrep @latest-tag
junegunn/fzf @latest-tag ARCH=both
https://github.com/madler/zlib.git v1.3.1 CMAKE_ARGS="-DZLIB_BUILD_EXAMPLES=OFF"
```

Each line is a repository, then optionally a ref (a branch, tag, commit, or `@latest-tag` for the
newest version tag), then any `KEY=VALUE` options. A repository can be in both lists; `ARCH`
means different things in each (see the option tables above).

To turn it on, set the repository variable `MACBIN_FARM=true`. The results are uploaded as workflow
artifacts.

To have them written to an Unraid share instead, set the farm's `USER_SHARE_MOUNTS` to
`/mnt/user/macbin/output:/mnt/macbin:rw` and the repository variable `MACBIN_OUTPUT_DIR` to
`/mnt/macbin`. The builds land in `macos/` and `windows/` there, and commits that were already
built are skipped.

## Optional: faster builds

To share downloaded crates, Go modules and zig's compiled C++ library between jobs, add this to
the farm's `CACHE_MOUNTS`:

```text
cargo-registry:/home/runner/.cargo/registry cargo-git:/home/runner/.cargo/git go-mod:/home/runner/go/pkg/mod go-build:/home/runner/.cache/go-build zig-cache:/home/runner/.cache/zig
```

## iOS and macOS apps

Xcode projects (iOS and macOS apps) and Swift packages are built by a second reusable workflow.
It runs on a Mac: GitHub's macOS runners (free for public repositories) or a self-hosted runner on
your own Mac.

```yaml
# .github/workflows/apple.yml
on:
  push:
    tags: ["v*"]
  workflow_dispatch:
jobs:
  ios:
    uses: Krippler/MacBin/.github/workflows/build-apple.yml@v0.2.0
    permissions:
      contents: write
    with:
      platform: ios       # or macos
    secrets: inherit      # only needed for signing
```

Without a certificate, it builds an **unsigned `.ipa`** for iOS (for sideloading tools such as
AltStore or Sideloadly, which sign it themselves), or an ad-hoc signed `.app` in a zip for macOS. A
Swift package with executable products (with `platform: macos`) becomes a zip of universal
command-line tools.

| Input | Default | Description |
|---|---|---|
| `platform` | `ios` | `ios` or `macos` |
| `project` | `.` | `.xcworkspace`, `.xcodeproj`, or a folder with one of them or a `Package.swift` |
| `scheme` | | Defaults to the scheme named like the project, otherwise the first |
| `configuration` | `Release` | Build configuration |
| `xcode-version` | | For example `26.0`, otherwise the runner's default Xcode |
| `export-method` | | With a certificate: `app-store-connect` (iOS default), `release-testing`, `enterprise`, `debugging`, `developer-id` (macOS default) or `mac-application` |
| `notarize` | `false` | Notarize and staple a Developer ID macOS app or tool |
| `upload` | `false` | Upload to App Store Connect / TestFlight |
| `xcodebuild-args` | | Extra `xcodebuild` (or `swift build`) arguments |
| `runs-on` | `["macos-latest"]` | For example `'["self-hosted", "macOS"]'` for your own Mac |

Secrets for signed builds:

| Secret | Content |
|---|---|
| `APPLE_CERTIFICATE` | Signing certificate (`.p12`), base64-encoded: Apple Distribution, Apple Development or Developer ID Application |
| `APPLE_CERTIFICATE_PASSWORD` | The `.p12` password |
| `APPLE_PROVISIONING_PROFILES` | iOS: the provisioning profile(s), base64-encoded. Separate several with commas. |
| `APP_STORE_CONNECT_KEY`, `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID` | An App Store Connect API key (the `.p8` file's content and its IDs), for `notarize` and `upload` |

With a single provisioning profile, it's applied to the whole build. Apps with extensions need one
profile per target, and the project must name them in its signing settings.

Building a project runs its build scripts on your server or Mac, so only build repositories you
trust.
