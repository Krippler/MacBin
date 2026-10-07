# Releasing MacBin

Merging a release PR into `main` is all it takes. No tag needs to be pushed from anyone's machine.

## The flow

| Trigger | What happens |
|---|---|
| merge to `main`, `MACBIN_VERSION` already tagged | `:runner-base` and `:runner` are updated; nothing is released |
| **release-PR merge**: a new `MACBIN_VERSION` | the image is built, tested and run on a Mac, then `:runner-base-X.Y.Z` and `:runner-X.Y.Z` are published, `vX.Y.Z` is tagged, and a GitHub Release is published with that version's `CHANGELOG.md` section as notes |
| manual `git push origin vX.Y.Z` | the image is published as `:runner-base-X.Y.Z` and `:runner-X.Y.Z` (no GitHub Release) |

All of it is the **Image** workflow (`.github/workflows/image.yml`). Its `publish` job runs only
after the binaries passed on a Mac, and it tags the release last, so a tag always has a published
image.

## Cutting a release

Open a release PR (branch name like `release-v0.2.0`) that sets the new version in every place
it appears:

- `MACBIN_VERSION` in `lib/common.sh`
- `uses: Krippler/MacBin@vX.Y.Z` in `.github/workflows/build-macos.yml`
- `ref: vX.Y.Z` in `.github/workflows/build-apple.yml`
- the `@vX.Y.Z` workflow references and the `runner-base-X.Y.Z` image in `README.md`
- `CHANGELOG.md`: retitle `## [Unreleased]` to `## [X.Y.Z] — YYYY-MM-DD`

`tests/check-version.sh` runs in CI and fails the PR if any of them disagree. Merge it, and the
release appears once the Image workflow finishes. The next ordinary PR adds `## [Unreleased]`
back on top of the changelog for its notes.
