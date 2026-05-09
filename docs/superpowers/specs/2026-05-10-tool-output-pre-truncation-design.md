# Tool Output Pre-Truncation (A1)

## Problem

During inline compaction, tool outputs (file reads, shell commands, search results) are sent to the compression model at full size. A single file read can be 8k+ tokens, a build log 6k+ tokens. These dominate the compression input, waste model tokens, and dilute the summary's information density.

## Goal

Truncate tool outputs to a fixed token budget before sending history to the compression model. The truncation is local (no model call), fast, and only affects the compression input — the original history is replaced after compaction completes.

## Scope

- **In scope**: `compact.rs` — add pre-truncation function, call it before compression
- **Out of scope**: `compact_remote.rs`, template changes (done in A2), new data structures

## Implementation Steps

### Step 1: Add imports to `compact.rs`

**File**: `codex-main/codex-rs/core/src/compact.rs`

Add to the existing imports:

```rust
use std::collections::HashMap;
use codex_utils_output_truncation::truncate_function_output_items_with_policy;
```

`truncate_text` and `TruncationPolicy` are already imported.

### Step 2: Add constant

**File**: `codex-main/codex-rs/core/src/compact.rs`

Add after the existing `COMPACT_USER_MESSAGE_MAX_TOKENS` constant (line 33):

```rust
const COMPACT_TOOL_OUTPUT_MAX_TOKENS: usize = 500;
```

### Step 3: Add `truncate_payload` helper function

**File**: `codex-main/codex-rs/core/src/compact.rs`

Add after the `is_summary_message` function (around line 271):

```rust
fn truncate_payload(body: &mut FunctionCallOutputBody, policy: &TruncationPolicy) {
    match body {
        FunctionCallOutputBody::Text(text) => {
            let truncated = truncate_text(text, *policy);
            if truncated.len() < text.len() {
                *text = truncated;
            }
        }
        FunctionCallOutputBody::ContentItems(items) => {
            let truncated = truncate_function_output_items_with_policy(items, *policy);
            *items = truncated;
        }
    }
}
```

### Step 4: Add `pre_compress_tool_outputs` function

**File**: `codex-main/codex-rs/core/src/compact.rs`

Add after `truncate_payload`:

```rust
fn pre_compress_tool_outputs(items: &mut [ResponseItem], max_tokens: usize) {
    let policy = TruncationPolicy::Tokens(max_tokens);
    for item in items.iter_mut() {
        match item {
            ResponseItem::FunctionCallOutput { output, .. } => {
                truncate_payload(&mut output.body, &policy);
            }
            ResponseItem::CustomToolCallOutput { output, .. } => {
                truncate_payload(&mut output.body, &policy);
            }
            _ => {}
        }
    }
}
```

### Step 5: Call `pre_compress_tool_outputs` in the compaction loop

**File**: `codex-main/codex-rs/core/src/compact.rs`

In `run_compact_task_inner`, after line 120 (`for_prompt()` call), insert:

```rust
pre_compress_tool_outputs(&mut turn_input, COMPACT_TOOL_OUTPUT_MAX_TOKENS);
```

The result:

```rust
let turn_input = history
    .clone()
    .for_prompt(&turn_context.model_info.input_modalities);
pre_compress_tool_outputs(&mut turn_input, COMPACT_TOOL_OUTPUT_MAX_TOKENS);
let turn_input_len = turn_input.len();
```

## Why 500 tokens

- Tool outputs contribute **metadata** to the summary (which file was read, whether a command succeeded), not full content
- 500 tokens ≈ first 15-20 lines + truncation marker, enough to capture errors, function signatures, file headers
- The full output is still visible in the pre-compaction history; the compression model has enough context to write a good summary
- After compaction, the summary preserves key findings; downstream models never need the raw output

## Files Changed

| File | Change |
|---|---|
| `codex-main/codex-rs/core/src/compact.rs` | Add 2 functions (~25 lines), 1 constant, 2 imports, 1 call site |

## Verification

1. `cd codex-main/codex-rs && cargo test --package codex-core compact` — existing tests pass
2. Manual: trigger compaction in a conversation with heavy tool usage (file reads, shell commands). Compare the token usage before/after compaction — should see significantly lower compression input tokens
