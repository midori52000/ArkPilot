# Structured Compression Prompt (A2)

## Problem

Current inline compaction (`compact.rs`) uses a free-text summarization prompt. The output format is uncontrolled — the model may produce verbose narrative, miss critical details, or bury key data in paragraphs. This leads to:

- Inconsistent information density across compactions
- Downstream models struggling to extract specific facts from prose
- No guarantee that file paths, function names, or error messages are preserved exactly

## Goal

Replace the free-text compression prompt with a structured markdown template that guides the model to produce a predictable, high-density handoff summary. No code-level parsing is needed — the structure serves the consuming LLM, not the program.

## Scope

- **In scope**: `templates/compact/prompt.md`, `templates/compact/summary_prefix.md`, verification steps
- **Out of scope**: `compact.rs` logic changes, `compact_remote.rs`, tool output pre-truncation (A1), hierarchical memory (A3), new data structures

## Implementation Steps

### Step 1: Replace `templates/compact/prompt.md`

**File**: `codex-main/codex-rs/core/templates/compact/prompt.md`

**Current content** (entire file):
```
You are performing a CONTEXT CHECKPOINT COMPACTION. Create a handoff summary for another LLM that will resume the task.

Include:
- Current progress and key decisions made
- Important context, constraints, or user preferences
- What remains to be done (clear next steps)
- Any critical data, examples, or references needed to continue

Be concise, structured, and focused on helping the next LLM seamlessly continue the work.
```

**New content** (replace entire file):
```
You are performing a CONTEXT CHECKPOINT COMPACTION. Another language model will resume
this task using only your output. Produce a structured handoff summary.

Respond in this exact markdown format:

## Task State
Goal: <one-line task description>
Status: <in_progress | blocked | nearly_done>

## Decisions Made
- <decision>: <reason>
- ...

## File Changes
- <path>: <what changed and why>
- ...

## Active Constraints
- <constraint or preference>
- ...

## Errors & Warnings
- <error/status>: <resolution or current state>
- ...

## Next Steps
- [ ] <next action>
- [ ] ...

## Key Data
- <variable names, config values, API endpoints, or other data needed to continue>
- ...

Rules:
- Be concise. Each bullet should be one sentence.
- Omit empty sections entirely.
- If no decisions were made, omit "Decisions Made".
- Focus on information the next model needs to continue work, not narrative.
- Preserve exact file paths, function names, and error messages.
```

**Why this works**:
- The opening sentence preserves the original intent ("handoff summary for another LLM")
- The markdown template gives the model a skeleton to fill in, reducing variance
- "Omit empty sections" prevents wasted tokens on `## Decisions Made\n(none)`
- "Each bullet should be one sentence" caps verbosity per item
- "Preserve exact file paths, function names, and error messages" prevents the model from paraphrasing critical identifiers

### Step 2: Replace `templates/compact/summary_prefix.md`

**File**: `codex-main/codex-rs/core/templates/compact/summary_prefix.md`

**Current content** (entire file):
```
Another language model started to solve this problem and produced a summary of its thinking process. You also have access to the state of the tools that were used by that language model. Use this to build on the work that has already been done and avoid duplicating work. Here is the summary produced by the other language model, use the information in this summary to assist with your own analysis:
```

**New content** (replace entire file):
```
Another language model was working on this task and produced a structured context checkpoint.
Use the information below to continue the work without duplicating effort.
```

**Why this change**:
- Shorter — saves ~40 tokens per compaction
- "structured context checkpoint" accurately describes the new format
- Removes "You also have access to the state of the tools" which is no longer true after compaction (tool outputs are discarded)
- Retains the "Another language model" prefix so `is_summary_message()` detection still works

### Step 3: Verify `is_summary_message()` compatibility

**File**: `codex-main/codex-rs/core/src/compact.rs` (read-only, no changes)

The function at line 269:
```rust
pub(crate) fn is_summary_message(message: &str) -> bool {
    message.starts_with(format!("{SUMMARY_PREFIX}\n").as_str())
}
```

This checks if a message starts with `SUMMARY_PREFIX + "\n"`. The new prefix begins with "Another language model" (same as old), so detection continues to work. The `build_compacted_history` function at line 381 constructs:
```rust
history.push(ResponseItem::Message {
    content: vec![ContentItem::InputText { text: summary_text }],
    ...
});
```
where `summary_text = format!("{SUMMARY_PREFIX}\n{summary_suffix}")`. This flow is unchanged.

**Verification**: After editing, confirm the new prefix text starts with "Another language model" — the first two words are the detection anchor.

### Step 4: Run existing tests

```bash
cd codex-main && cargo test
```

All existing tests in `compact_tests.rs` should pass unchanged because:
- `build_compacted_history` logic is untouched
- `collect_user_messages` / `is_summary_message` logic is untouched
- The only change is the content of two string constants loaded via `include_str!`
- No test asserts on the literal prompt content

### Step 5: Manual verification in app

1. Build the Rust library: `build.bat debug x86_64`
2. Install and run the ArkPilot app in emulator
3. Start a long conversation that will trigger auto-compaction (token usage >= 244,800)
4. After compaction triggers, check the conversation UI — the summary should show structured markdown sections (## Task State, ## Decisions Made, etc.)
5. Continue the conversation after compaction — the model should reference specific sections from the summary, confirming it parsed the structure

## Error Handling

- **Model partially follows format**: Accepted as-is. Some sections may be missing or formatted slightly differently. The consuming LLM can still parse partial structure better than pure prose.
- **Model ignores format entirely**: Accepted as-is. Equivalent to current behavior — no regression.
- **Empty sections in output**: The "Omit empty sections" rule should prevent this, but if the model produces empty headers anyway, the consuming LLM handles them naturally.

## Files Changed

| File | Change Type | Lines Changed |
|---|---|---|
| `codex-main/codex-rs/core/templates/compact/prompt.md` | Full rewrite | ~9 → ~25 |
| `codex-main/codex-rs/core/templates/compact/summary_prefix.md` | Full rewrite | 1 → 2 |

No Rust code changes. Two template files only.
