# Auto Compaction Visibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expose existing auto-compaction configuration and compaction history in the current token/context card without changing backend core compaction semantics.

**Architecture:** Reuse the existing Rust transfer layer in `codex-main/codex-rs/ohos-host/src/lib.rs` to surface the effective `contextManagement` snapshot plus `model_auto_compact_token_limit` to ArkTS. Keep ArkTS responsible for parsing the raw native fields, deriving display-only auto-compaction state, and rendering it in the existing `Index.ets` token/context card alongside the current history metrics.

**Tech Stack:** Rust (`ohos-host` transfer layer), ArkTS, HarmonyOS UI, existing NAPI/native payload bridge

---

## File map

- Modify: `codex-main/codex-rs/ohos-host/src/lib.rs`
  - Keep `contextManagement` output unified across `threadRead` and `turnPoll`
  - Surface `model_auto_compact_token_limit` in both payloads from existing effective config
- Modify: `Agent/entry/src/main/ets/backend/ConsoleModels.ets`
  - Extend native/derived models with the raw auto-compaction threshold and UI-facing derived fields
- Modify: `Agent/entry/src/main/ets/backend/CodexBackend.ets`
  - Parse the new raw threshold field and derive `autoCompactEnabled`, `remainingToAutoCompact`, and `autoCompactNearThreshold`
- Modify if needed: `Agent/entry/src/main/ets/backend/CodexNative.ets`
  - Only if bridge typing needs to acknowledge the new payload field
- Modify: `Agent/entry/src/main/ets/pages/Index.ets`
  - Render auto-compaction status in the existing token/context card with conservative wording
- Test manually: existing app flow in `Agent/`
  - Read thread → inspect token card → trigger/observe compaction history → reopen thread/app

## Task 1: Surface auto-compaction threshold from Rust transfer layer

**Files:**
- Modify: `codex-main/codex-rs/ohos-host/src/lib.rs`

- [ ] **Step 1: Locate the existing payload builders and config source**

Read and confirm the code paths for:
- `resolve_thread_context_management(...)`
- `build_context_management_payload(...)`
- `build_turn_poll_payload(...)`
- `build_thread_read_payload(...)`
- current reads of `model_auto_compact_token_limit`

Expected outcome:
- Identify the exact payload objects returned to ArkTS for both `threadRead` and `turnPoll`
- Confirm where the effective config value already exists so the plan does not invent new backend state

- [ ] **Step 2: Add the raw threshold field to the native payload shape**

Update the Rust payload assembly so both thread snapshot and poll result include the same raw field:

```rust
"modelAutoCompactTokenLimit": model_auto_compact_token_limit,
```

Implementation rules:
- Read from the current effective config already used by the host
- Preserve current `contextManagement` shape; do not stuff the threshold into the history snapshot
- Keep absent/invalid values as null-or-disabled semantics instead of fabricating fallback numbers

- [ ] **Step 3: Keep `threadRead` and `turnPoll` semantics aligned**

Ensure both payload builders use the same effective config source and the same naming for the new field.

Checklist:
- `threadRead.contextManagement` and `turnPoll.contextManagement` still come from the same effective snapshot path
- `threadRead.modelAutoCompactTokenLimit` and `turnPoll.modelAutoCompactTokenLimit` are populated the same way
- No changes to `core/src/*.rs` or other non-`lib.rs` files under `codex-main`

- [ ] **Step 4: Sanity-check serialization shape locally in code review**

Inspect the edited Rust code and verify:
- camelCase field name matches ArkTS conventions
- the new field is present in both payloads
- no existing history fields were removed or renamed

Expected outcome:
- ArkTS can consume one raw threshold field from either chain without branch-specific parsing

## Task 2: Extend ArkTS models for raw and derived auto-compaction state

**Files:**
- Modify: `Agent/entry/src/main/ets/backend/ConsoleModels.ets`
- Modify if needed: `Agent/entry/src/main/ets/backend/CodexNative.ets`

- [ ] **Step 1: Add the raw native field to the relevant payload/model types**

Extend the native-facing snapshot/result interfaces to carry:

```ts
modelAutoCompactTokenLimit?: number | null
```

Use the same optional/nullability pattern already used by nearby payload fields.

- [ ] **Step 2: Add derived display fields to the backend state model**

Extend the ArkTS state model used by the UI with:

```ts
modelAutoCompactTokenLimit: number | null
autoCompactEnabled: boolean
remainingToAutoCompact: number | null
autoCompactNearThreshold: boolean
```

Rules:
- `modelAutoCompactTokenLimit` is raw passthrough state
- the other fields are ArkTS-derived display helpers
- do not add fields for a fake “auto-compaction is running” state machine

- [ ] **Step 3: Preserve clone/default behavior**

If `CodexContextManagementSnapshot` or adjacent state has clone/default helpers, update them so the new fields survive:
- initial state creation
- snapshot replacement
- thread reopen / app reload flows

Expected outcome:
- The backend can store the raw threshold plus derived display state without losing values during state copies

## Task 3: Derive auto-compaction display state in CodexBackend

**Files:**
- Modify: `Agent/entry/src/main/ets/backend/CodexBackend.ets`

- [ ] **Step 1: Parse the raw threshold in both read and poll flows**

Update the payload application path so both snapshot load and poll updates capture the new raw field from native results.

Touch the existing parsing entry points referenced by the spec:
- `readThreadSnapshot(...)`
- `applyTurnPollResult(...)`
- `applyContextManagementPayload(...)` or adjacent helpers

- [ ] **Step 2: Add a single derivation helper for auto-compaction UI state**

Create or extend one backend helper that computes:

```ts
private deriveAutoCompactionState(): void {
  const limit = this.modelAutoCompactTokenLimit
  const used = this.tokenUsage.total?.totalTokens ?? 0

  this.autoCompactEnabled = typeof limit === 'number' && isFinite(limit) && limit > 0
  if (!this.autoCompactEnabled) {
    this.remainingToAutoCompact = null
    this.autoCompactNearThreshold = false
    return
  }

  if (!(used > 0)) {
    this.remainingToAutoCompact = null
    this.autoCompactNearThreshold = false
    return
  }

  this.remainingToAutoCompact = used >= limit ? 0 : limit - used
  this.autoCompactNearThreshold = this.remainingToAutoCompact === 0 || this.contextRemainingPercent() <= 15
}
```

Adjust exact method/field references to the file’s existing structure. Preserve the spec’s semantics:
- `limit <= 0` → disabled
- no usable token count → show threshold only
- `used >= limit` → remaining `0`

- [ ] **Step 3: Re-run derivation whenever either threshold or token usage changes**

Hook the derivation helper into the existing update flow after:
- token usage payload application
- thread snapshot load
- poll result application
- any path that replaces context state during compaction completion/failure reconciliation

Expected outcome:
- UI-visible auto-compaction state stays in sync even if token usage changes after the threshold arrives, or vice versa

- [ ] **Step 4: Preserve conservative backend semantics**

Review the final ArkTS logic and verify:
- no guessed history values are written back into `contextManagement`
- no backend raw fields are overwritten by inferred UI values
- no dedicated auto-compaction runtime state is invented

## Task 4: Render auto-compaction visibility in the existing token/context card

**Files:**
- Modify: `Agent/entry/src/main/ets/pages/Index.ets`

- [ ] **Step 1: Add focused UI text helpers**

Add or extend helper methods for:
- formatting threshold value
- formatting remaining-to-threshold value
- building the final auto-compaction line

Target outputs from the spec:
- `未启用`
- `阈值 96k`
- `阈值 96k（还差 8k）`
- `阈值 96k（已到达）`

Keep formatting consistent with the existing token-count display helpers already in `Index.ets`.

- [ ] **Step 2: Insert the auto-compaction metric into the existing card**

Add one metric row inside `tokenUsageCard()` near the current context-window usage rows so the current-state threshold information sits with current context usage, not with historical compaction records.

Use the existing row renderer pattern, for example:

```ts
this.contextManagementMetricRow('自动压缩', this.autoCompactionText())
```

Do not add a new standalone section unless the existing card structure makes a single row impossible.

- [ ] **Step 3: Keep current-state and history-state visually separated**

Review the card ordering so it reads like:
1. context window / used / remaining
2. auto-compaction threshold current state
3. full compaction / micro compaction / circuit breaker history

Expected outcome:
- users can distinguish “what is configured now” from “what happened before” at a glance

- [ ] **Step 4: Preserve conservative history wording**

Keep the earlier weak-history behavior in place:
- if only the trigger exists, show a weak historical hint
- if details are incomplete, do not imply a full successful record
- failure history and circuit breaker copy stays neutral

## Task 5: Verify consistency and user-visible behavior

**Files:**
- Modify if needed: the files above only
- Manual verification target: `Agent/` app flow

- [ ] **Step 1: Review threadRead/turnPoll field parity in code**

Check that the same fields are exposed and consumed on both paths:
- `modelAutoCompactTokenLimit`
- `contextManagement.lastFullCompactionTrigger`
- `compactionFailureCount`
- `compactionCircuitOpen`

Expected outcome:
- no path-specific parsing or naming drift remains

- [ ] **Step 2: Manually verify token-card scenarios in the running app**

Exercise or inspect these cases:
- auto-compaction disabled
- enabled and far from threshold
- enabled and near threshold
- enabled and already at threshold

Record what to check:
- token/context card shows the expected auto-compaction copy
- existing context window / used / remaining values still render normally
- no layout regression in the card

- [ ] **Step 3: Manually verify history wording scenarios**

Check:
- full detail available → full history copy appears
- only trigger available → weak hint only
- no record → neutral/default wording
- failure record / circuit open → neutral failure wording remains accurate

- [ ] **Step 4: Reopen thread and relaunch app to verify persistence semantics**

Verify after reopening the same thread or restarting the app:
- threshold still displays correctly
- `threadRead` does not drift from prior `turnPoll` state
- history fields do not disappear or become stronger/weaker incorrectly

- [ ] **Step 5: Run only the minimum validation needed after implementation**

Because the user preference for this planning phase is minimal churn, keep validation focused on the paths touched by the feature:
- inspect diff for forbidden `codex-main` edits outside `lib.rs`
- run the smallest relevant checks once implementation begins
- if UI cannot be exercised in this environment, explicitly report that gap instead of claiming success

## Implementation notes

- Do not modify `codex-main/codex-rs/core/src/compact.rs`
- Do not modify `codex-main/codex-rs/core/src/compact_remote.rs`
- Do not modify `codex-main/codex-rs/core/src/codex.rs`
- Do not introduce a fake auto-compaction event stream or runtime notice system
- Prefer minimal edits that reuse existing helpers and payload structures
- Keep current copy conservative whenever backend history detail is incomplete

## Suggested commit boundaries

1. `feat: expose auto compaction threshold to ArkTS payloads`
2. `feat: derive auto compaction visibility in backend state`
3. `feat: show auto compaction status in token context card`

## Done criteria

The work is complete when all of the following are true:
- `threadRead` and `turnPoll` both expose `modelAutoCompactTokenLimit`
- ArkTS derives enabled/remaining/near-threshold state without altering backend semantics
- the existing token/context card shows auto-compaction status with conservative wording
- full/micro/failure/circuit-breaker history still renders and is not overstated
- no `codex-main` file outside `lib.rs` was modified
