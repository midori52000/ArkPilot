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

## Critical Preservation
- <exact error messages, stack traces, or diagnostic output>
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
- Be thorough. Each bullet should capture the essential detail, not just a one-line abstraction.
- Include all relevant context that a model would need to continue the work.
- Preserve exact file paths, function names, variable names, and error messages verbatim.
- When text contains Chinese/CJK characters, preserve the original text exactly — do not translate or summarize CJK content.
- Error messages and stack traces must be copied verbatim, never paraphrased.
- For file changes, include the specific functions or methods modified, not just the file path.
- If a previous context checkpoint is provided, build upon it — preserve its key information while adding new context.
- Omit empty sections entirely.
