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

## Design

### New Prompt Template

Replace `templates/compact/prompt.md` with:

```markdown
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

### Updated Summary Prefix

Replace `templates/compact/summary_prefix.md` with:

```markdown
Another language model was working on this task and produced a structured context checkpoint.
Use the information below to continue the work without duplicating effort.
```

### Integration

No changes to `compact.rs` logic. The prompt is loaded via `include_str!` at compile time:

```rust
pub const SUMMARIZATION_PROMPT: &str = include_str!("../templates/compact/prompt.md");
pub const SUMMARY_PREFIX: &str = include_str!("../templates/compact/summary_prefix.md");
```

The summary flows through the existing pipeline:

1. `run_compact_task_inner` sends history + `SUMMARIZATION_PROMPT` to the model
2. Model outputs structured markdown
3. `get_last_assistant_message_from_turn` extracts the summary
4. `build_compacted_history` wraps it as: `[SUMMARY_PREFIX\nsummary]` user message
5. History is replaced

### Error Handling

- **Model partially follows format**: Accepted as-is. No programmatic parsing.
- **Model ignores format entirely**: Accepted as-is. Equivalent to current behavior — no regression.
- **Empty sections in output**: The consuming LLM handles this naturally.

## Files Changed

| File | Change |
|---|---|
| `codex-main/codex-rs/core/templates/compact/prompt.md` | Replace with structured prompt |
| `codex-main/codex-rs/core/templates/compact/summary_prefix.md` | Update preamble text |

No Rust code changes. Two template files only.

## Verification

1. `cd codex-main && cargo test` — all existing tests pass
2. Manual: grep for `SUMMARY_PREFIX` in `compact.rs` to confirm `is_summary_message()` still detects the prefix (the new prefix starts with the same "Another language model" substring)
3. Run a long conversation in the app, trigger auto-compaction, verify the summary in the UI shows structured markdown sections
