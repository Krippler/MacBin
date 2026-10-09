# Windows support

WMBin builds Windows binaries with the tools in this folder. They started out as a separate
project, WinBin (its 0.1.0 release, GPL-2.0), and now live here: WMBin needs nothing from WinBin,
and this folder is where they're maintained.

- `lib/` and `scripts/`: `winbin-build` and `winbin-batch`, installed to `/opt/winbin` in the
  runner image with `winbin-build` and `winbin-batch` on `PATH`. The names stay the same so build
  scripts written for WinBin keep working.
- `action.yml` and `action/run.sh`: the Windows GitHub Action, used as
  `Krippler/WMBin/windows@vX.Y.Z` by `.github/workflows/build-windows.yml`.

The tests are `tests/run-windows-tests.sh` (in the runner image) and `tests/run-on-windows.sh`
(runs the built executables on a Windows machine in CI).
