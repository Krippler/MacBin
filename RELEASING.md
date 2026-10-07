# Releasing

A release is a `vX.Y.Z` tag. Its version appears in five places, which must match:

- `MACBIN_VERSION` in `lib/common.sh`
- `uses: Krippler/MacBin@vX.Y.Z` in `.github/workflows/build-macos.yml`
- `ref: vX.Y.Z` in `.github/workflows/build-apple.yml`
- the `@vX.Y.Z` workflow references and the `runner-base-X.Y.Z` image tag in `README.md`

Bump them all in one commit, then tag that commit and push the tag:

```sh
git tag -a vX.Y.Z -m "MacBin X.Y.Z"
git push origin vX.Y.Z
```

The Image workflow then builds and tests the image, runs the binaries on a Mac, and publishes
`ghcr.io/krippler/macbin:runner-base-X.Y.Z` and `:runner-X.Y.Z`.
