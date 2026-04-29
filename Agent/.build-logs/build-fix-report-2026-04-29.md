# ArkPilot Agent HarmonyOS Build Fix Report

Date: 2026-04-29
Project: `D:\code\harmony\ArkPilot\Agent`

## Summary

The project now builds successfully.

Verified outputs:

- Rust static library (arm64): `D:\code\harmony\ArkPilot\Agent\.cargo-target\codex-ohos-host\aarch64-unknown-linux-ohos\debug\libcodex_ohos_host.a`
- Rust static library (x86_64): `D:\code\harmony\ArkPilot\Agent\.cargo-target\codex-ohos-host\x86_64-unknown-linux-ohos\debug\libcodex_ohos_host.a`
- HarmonyOS HAP: `D:\code\harmony\ArkPilot\Agent\entry\build\default\outputs\default\entry-default-unsigned.hap`

## Root Causes

1. `build_codex_ohos_host.cmd` hardcoded Cargo to `%USERPROFILE%\.cargo\bin\cargo.exe`.
   On this machine, Cargo is installed at `D:\.cargo\bin\cargo.exe`, so the native build failed immediately with `系统找不到指定的路径。`

2. The script only set hyphenated CMake target environment variables.
   Some Rust/CMake dependencies use underscore-style target keys such as `CMAKE_TOOLCHAIN_FILE_aarch64_unknown_linux_ohos`, causing them to fall back to stale OHOS SDK paths.

3. The script exported global `CC`, `AR`, `RANLIB`, `TARGET_CC`, and `TARGET_AR`.
   That polluted host-side Rust build dependencies and made Windows-host build steps incorrectly use the OHOS cross compiler.

4. Hvigor cache and daemon metadata still referenced the old SDK root:
   `D:/develop/deveco/DevEco Studio/sdk`
   This later caused:
   `00303217 Configuration Error: Invalid value of 'DEVECO_SDK_HOME' in the system environment path.`

## Changes Applied

File changed:

- `D:\code\harmony\ArkPilot\Agent\entry\src\main\cpp\build_codex_ohos_host.cmd`

Fixes in that script:

- Added flexible Cargo discovery:
  - `CARGO`
  - `CARGO_HOME\bin\cargo.exe`
  - `%USERPROFILE%\.cargo\bin\cargo.exe`
  - `where cargo`
- Added clear error messages when Cargo is missing.
- Exported OHOS SDK environment explicitly:
  - `OHOS_NDK_HOME`
  - `OHOS_SDK_NATIVE`
  - `SDK_NATIVE`
- Added underscore-style target-specific CMake variables for both OHOS targets.
- Removed global compiler variable pollution by clearing:
  - `CC`
  - `TARGET_CC`
  - `AR`
  - `TARGET_AR`
  - `RANLIB`
  and keeping compiler selection target-specific only.

Non-source cleanup performed:

- Removed stale project hvigor cache: `D:\code\harmony\ArkPilot\Agent\.hvigor`
- Stopped hvigor daemon before rebuild
- Rebuilt with:
  - `DEVECO_SDK_HOME=C:\Program Files\Huawei\DevEco Studio\sdk`

## Validation Performed

1. Built Rust OHOS host library for:
   - `aarch64-unknown-linux-ohos`
   - `x86_64-unknown-linux-ohos`

2. Ran full project build with bundled DevEco hvigor entry:

```text
node "C:\Program Files\Huawei\DevEco Studio\tools\hvigor\hvigor\bin\hvigor.js" assembleHap
```

with:

```text
DEVECO_SDK_HOME=C:\Program Files\Huawei\DevEco Studio\sdk
```

Final result:

```text
BUILD SUCCESSFUL in 3 min 31 s 122 ms
```

## Recommended Next Step

To avoid repeating the Hvigor SDK-path issue, set `DEVECO_SDK_HOME` permanently to:

`C:\Program Files\Huawei\DevEco Studio\sdk`

and clear/restart the hvigor daemon if the SDK location changes again.
