# libcodexhost-builder

This standalone project builds the OpenHarmony native bridge library `libcodexhost.so` from `codex-main/codex-rs` without involving the `Agent` HAP build.

For the current OpenHarmony flow, only `codex-main/codex-rs` is required. The
other top-level upstream folders are not needed for packaging or rebuilding
`libcodexhost.so`.

## Expected Layout

```text
OpenHarmony/
|-- Agent/
|-- codex-main/
|   `-- codex-rs/
`-- libcodexhost-builder/
```

## Usage

Build and install into `Agent` by default:

```bat
build.bat debug x86_64
```

Build only without copying into `Agent`:

```bat
build.bat debug x86_64 --no-install
```

If you already have a compiled Rust static library and only want to link the
final `.so`, set `PREBUILT_RUST_STATIC_LIB` first:

```bat
set PREBUILT_RUST_STATIC_LIB=C:\path\to\libcodex_ohos_host.a
build.bat debug x86_64
```

The installed target path is:

```text
Agent\entry\src\main\libs\x86_64\libcodexhost.so
```

## Notes

- `Agent` now treats `libcodexhost.so` as a prebuilt native dependency.
- Rebuild and reinstall this library whenever `codex-main/codex-rs/ohos-host` or the bridge code changes.
- The builder supports `x86_64` and `arm64-v8a`.
- `PREBUILT_RUST_STATIC_LIB` lets you skip the Rust compile step and only link the final `libcodexhost.so`.
- The builder now copies the resulting `.so` into `Agent\entry\src\main\libs\<abi>\` by default.
- `codex-rs` itself is still a large Rust workspace. Do not delete crates from
  inside `codex-rs` unless you also update the Rust workspace and dependency
  graph for `codex-ohos-host`.
