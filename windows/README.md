# Windows support

MacBin builds Windows binaries with the tools in this folder, taken over from
[WinBin](https://github.com/Krippler/WinBin) at commit `9492858` (WinBin 0.1.0, GPL-2.0) so that
MacBin needs nothing from WinBin's repository or images. `lib/` and `scripts/` are unchanged copies
and install to `/opt/winbin` in the runner image, where `winbin-build` and `winbin-batch` are on
`PATH`. `action.yml` and `action/run.sh` are WinBin's action with MacBin's names; it's used as
`Krippler/MacBin/windows@vX.Y.Z` by `.github/workflows/build-windows.yml`.

To take later WinBin changes, copy the same files again and note the new commit here.
