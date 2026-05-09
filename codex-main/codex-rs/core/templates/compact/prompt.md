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
