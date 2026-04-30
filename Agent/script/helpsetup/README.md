# Agent Bootstrap Scripts

These scripts are the supported Windows bootstrap path for a fresh clone.

## Files

- `setup_env.bat`
  - Finds the `Agent` project root automatically
  - Finds the DevEco Studio SDK automatically
  - Generates `Agent\local.properties`
  - Installs `oh_modules` only when they are missing
  - Ensures the Rust OHOS targets are installed
  - Clears stale user hvigor workspace cache and stops the hvigor daemon

- `build.bat`
  - Calls `setup_env.bat`
  - Verifies a prebuilt `libcodexhost.so` is already installed
  - Builds an unsigned debug HAP
  - Cleans project-local build artifacts with `build.bat clean`

## Expected Layout

```text
OpenHarmony/
|-- Agent/
|   |-- oh-package.json5
|   |-- entry/
|   `-- script/helpsetup/
|-- libcodexhost-builder/
|   `-- build.bat
`-- codex-main/
    `-- codex-rs/
```

Only `codex-main/codex-rs` is required for the current native build flow. The
other upstream top-level folders are not needed by `Agent` or
`libcodexhost-builder`.

## Usage

From anywhere:

```bat
libcodexhost-builder\build.bat debug x86_64
Agent\script\helpsetup\build.bat debug
```

Or inside this folder:

```bat
setup_env.bat
build.bat debug
build.bat clean
```

## Output

```text
Agent\entry\build\default\outputs\default\entry-default-unsigned.hap
```

## Notes

- These scripts intentionally target an unsigned debug HAP.
- Signed packages still require local signing material on each machine.
- If DevEco Studio is installed in a non-default location, set `DEVECO_SDK_HOME` first and rerun `build.bat debug`.
- The scripts call DevEco's `hvigorw.bat` wrapper instead of invoking the internal `hvigor.js` entry directly.
- `Agent` no longer builds `libcodexhost.so` itself; the standalone `libcodexhost-builder` project owns that step.
- `libcodexhost-builder\build.bat` now installs the built `.so` into `Agent` by default.
