# OpenHarmony Codex Handoff Context

## 1. Current Goal

The long-term goal is to make the `Agent` HarmonyOS window app use a real backend derived from `codex-main`, ideally a full `codex-rs app-server` port, and then adapt the frontend to that backend.

This is **not done yet**.

What is done so far:

- A first ArkTS-side backend skeleton was added to the `Agent` project.
- The HarmonyOS frontend was changed to call that backend skeleton instead of generating local fake replies inline.
- The app still does **not** run a real Rust `codex-rs app-server`.

This distinction is important. Any follow-up AI should not assume the Rust backend has already been ported.

## 2. Workspace Layout

Workspace root:

- `C:\Users\asus\Desktop\OpenHarmony`

Key directories:

- `C:\Users\asus\Desktop\OpenHarmony\Agent`
  - HarmonyOS window application project built with DevEco / Hvigor
- `C:\Users\asus\Desktop\OpenHarmony\codex-main`
  - upstream Codex source tree

## 3. What `codex-main` Is

`codex-main` is the source tree for Codex CLI.

Important split:

- `codex-cli`
  - npm / Node launcher and distribution wrapper
  - not the real core logic
- `codex-rs`
  - actual maintained implementation
  - contains `core`, `state`, `rollout`, `app-server`, `app-server-client`, `exec`, `tui`, `cli`

Useful architecture document already written:

- `C:\Users\asus\Desktop\OpenHarmony\codex-main\docs\architecture_zh.md`

Important architecture facts from that analysis:

- `app-server` is the protocol convergence layer.
- TUI and `exec` are clients over the same app-server semantics.
- Core runtime is in `codex-rs/core`.
- Persistence is split across JSONL rollout files and SQLite state.
- For a HarmonyOS port, `app-server` is the right backend target, not TUI.

## 4. Important `codex-rs` Paths

These are the main code entry points relevant to a future real port:

- `C:\Users\asus\Desktop\OpenHarmony\codex-main\codex-rs\app-server`
- `C:\Users\asus\Desktop\OpenHarmony\codex-main\codex-rs\app-server-client`
- `C:\Users\asus\Desktop\OpenHarmony\codex-main\codex-rs\core`
- `C:\Users\asus\Desktop\OpenHarmony\codex-main\codex-rs\state`
- `C:\Users\asus\Desktop\OpenHarmony\codex-main\codex-rs\rollout`
- `C:\Users\asus\Desktop\OpenHarmony\codex-main\codex-rs\cli`

Useful source files:

- `C:\Users\asus\Desktop\OpenHarmony\codex-main\codex-rs\app-server\src\lib.rs`
- `C:\Users\asus\Desktop\OpenHarmony\codex-main\codex-rs\app-server\src\codex_message_processor.rs`
- `C:\Users\asus\Desktop\OpenHarmony\codex-main\codex-rs\app-server-protocol\src\protocol\v2.rs`
- `C:\Users\asus\Desktop\OpenHarmony\codex-main\codex-rs\core\src\thread_manager.rs`
- `C:\Users\asus\Desktop\OpenHarmony\codex-main\codex-rs\core\src\codex_thread.rs`
- `C:\Users\asus\Desktop\OpenHarmony\codex-main\codex-rs\core\src\codex.rs`

## 5. Current HarmonyOS App State

The app project is here:

- `C:\Users\asus\Desktop\OpenHarmony\Agent`

Relevant frontend files:

- `C:\Users\asus\Desktop\OpenHarmony\Agent\entry\src\main\ets\pages\Index.ets`
- `C:\Users\asus\Desktop\OpenHarmony\Agent\entry\src\main\ets\entryability\EntryAbility.ets`
- `C:\Users\asus\Desktop\OpenHarmony\Agent\entry\src\main\module.json5`

The UI is a three-column Codex-like window layout.

Before the recent change, the "send" interaction only appended fake local messages inside `Index.ets`.

## 6. Backend Work Already Added

A new ArkTS backend layer was added here:

- `C:\Users\asus\Desktop\OpenHarmony\Agent\entry\src\main\ets\backend\CodexBackend.ets`

What it contains:

- `CodexTurnRequest`
- `CodexTurnResult`
- `CodexChatMessage`
- `CodexDiffLine`
- `CodexBackend`
- `LocalCodexProvider`
- exported singleton `codexBackend`

Relevant lines:

- request model starts around `CodexTurnRequest`: line 37
- local provider starts around `LocalCodexProvider`: line 118
- backend class starts around `CodexBackend`: line 156

Design intent:

- mimic Codex's `Thread / Turn / Item` style at a lightweight ArkTS level
- keep the frontend talking to a backend object instead of embedding reply logic in the page
- leave a single provider seam that can later be replaced by:
  - a Rust NAPI binding
  - a stdio-launched Rust subprocess
  - a websocket / RPC bridge to a real app-server

Current limitation:

- `LocalCodexProvider` is still mock behavior
- it does not call Rust
- it does not speak the real `app-server` protocol

## 7. Frontend Changes Already Made

`Index.ets` was changed to consume the backend:

- import added at line 1
- `runBackendTurn()` added around line 108
- `applyBackendResult()` added around line 133
- summary title / changed files / diff stat are now state-backed
- send button shows `...` while a request is running

Relevant UI bindings:

- `Text(this.summaryTitle)` around line 564
- `Text(this.changedFiles)` around line 579
- `Text(this.diffStat)` around line 586
- `Button(this.isRunning ? '...' : '发')` around line 680

Important note:

- The file contents displayed in PowerShell showed mojibake for Chinese text, but ArkTS build still succeeded.
- This looks like terminal encoding noise, not a compile blocker.

## 8. Build Verification

The HarmonyOS app was built successfully after the backend skeleton and frontend integration.

Command used:

```powershell
$env:DEVECO_SDK_HOME='C:\Program Files\Huawei\DevEco Studio\sdk'
& 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat' assembleApp
```

Observed result:

- build succeeded

Output artifacts:

- `C:\Users\asus\Desktop\OpenHarmony\Agent\build\outputs\default\Agent-default-unsigned.app`
- `C:\Users\asus\Desktop\OpenHarmony\Agent\entry\build\default\outputs\default\entry-default-unsigned.hap`

Warnings that appeared but did not block build:

- no signing config configured
- symbol packaging warning related to existing symlink / missing symbol folder

## 9. What Is Not Done Yet

The following is still pending:

1. Real Rust `codex-rs app-server` port to HarmonyOS
2. Decision on integration path between HarmonyOS frontend and Rust backend
3. Real protocol mapping from HarmonyOS app to app-server requests / notifications
4. Real persistence, auth, filesystem, and command execution behavior on HarmonyOS
5. Replacement of `LocalCodexProvider` with a non-mock backend

## 10. Recommended Next Step For Another AI

The next AI should not try to jump straight into TUI or full CLI parity.

Recommended order:

1. Port or isolate a minimal Rust backend target around `codex-rs app-server`
2. Choose one transport for HarmonyOS:
   - NAPI bridge into Rust
   - spawn a local Rust binary and use stdio JSON-RPC
   - remote websocket app-server
3. Replace `LocalCodexProvider` with a real provider that converts UI actions into app-server calls
4. Expand the frontend state model from the current simplified summary into real thread / turn / item rendering

## 11. Ready-To-Use Prompt For Another AI

You can paste the following into another AI:

```text
Workspace root: C:\Users\asus\Desktop\OpenHarmony

There are two projects:
1. Agent = HarmonyOS window app
2. codex-main = upstream Codex source

Current objective:
Port a real Rust codex-rs app-server backend for HarmonyOS and adapt the Agent frontend to it.

Important current status:
- This is NOT done yet.
- A temporary ArkTS backend skeleton already exists.
- The frontend already calls that ArkTS backend instead of generating fake replies inline.
- Build currently succeeds.

Relevant files:
- Agent\entry\src\main\ets\backend\CodexBackend.ets
- Agent\entry\src\main\ets\pages\Index.ets
- codex-main\docs\architecture_zh.md
- codex-main\codex-rs\app-server
- codex-main\codex-rs\app-server-protocol
- codex-main\codex-rs\core

What has been implemented:
- CodexBackend.ets with CodexTurnRequest / CodexTurnResult / LocalCodexProvider / CodexBackend
- Index.ets wired to runBackendTurn() and applyBackendResult()

What is still needed:
- real Rust app-server port
- real HarmonyOS-to-Rust integration path
- replace LocalCodexProvider with real backend calls

Build command:
$env:DEVECO_SDK_HOME='C:\Program Files\Huawei\DevEco Studio\sdk'
& 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat' assembleApp
```

