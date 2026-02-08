# Ralph Wiggum Loop Command

Iterative refinement loop that keeps working until complete. The **stop hook** controls iteration and uses `osascript` (macOS) to bypass Cursor's 5-iteration limit.

## Usage

```
/ralph-loop "<task>" [--max-iterations <n>] [--completion-promise "<text>"]
/ralph-loop --continue <trace_id>
```

- **`<task>`** (required) — Task description
- **`--max-iterations <n>`** — Safety limit (default: 20)
- **`--completion-promise "<text>"`** — Completion signal (default: "COMPLETE")
- **`--continue <trace_id>`** — Resume from existing state (used by auto-continuation)

**If no prompt provided**: Print error with usage and stop.

## On Invocation

### New Loop

1. **Validate arguments** — Error if no prompt
2. **Create pending state file** at **`/tmp/cursor-ralph-pending.json`** (fixed path; agent does not have CURSOR_TRACE_ID). The stop hook will rename it to the trace-id file when it runs. Write this exact JSON (adjust prompt/max_iterations/completion_promise from args):

```json
{
  "prompt": "<task>",
  "max_iterations": 20,
  "completion_promise": "COMPLETE",
  "iterations": 0,
  "session_iterations": 0,
  "stop": false,
  "last_output": ""
}
```

Use a shell command, e.g.:
`echo '{"prompt":"<task>","max_iterations":20,"completion_promise":"COMPLETE","iterations":0,"session_iterations":0,"stop":false,"last_output":""}' > /tmp/cursor-ralph-pending.json`
(Replace `<task>` and options like max_iterations/completion_promise from the user's flags.)

3. Output brief confirmation and start working on the task.

### --continue

1. **Read state** from `/tmp/cursor-ralph-loop-<trace_id>.json` (use the trace_id argument, not CURSOR_TRACE_ID)
2. If state missing or invalid, error and exit
3. Resume working on the task from the state file

## During Work

- **Update state file** after meaningful progress: set `last_output` to a short summary (e.g. "Added 3 tests, coverage now 74%")
- **When done**: output the exact `completion_promise` string (default `COMPLETE`). The stop hook detects this and ends the loop.
- **Do not** implement your own loop or "continue" logic — the stop hook handles iteration.

## Stop Hook Behavior

After each agent response, the stop hook:

1. Reads state file
2. Increments iteration counters
3. If `stop: true` (user clicked Stop) → clean up and exit
4. If max iterations reached → clean up and exit
5. If `last_output` contains `completion_promise` → task done, clean up and exit
6. If session iterations < 5 → return `followup_message` to continue
7. If session = 5 (Cursor limit) → on macOS use osascript to type `/ralph-loop --continue <trace_id>` so a new "user message" resets Cursor's internal limit. On Linux, loop stops at 5 unless you manually run the continue command.

**User clicking Stop** sets `stop: true` in state file — hook detects this and exits.

## Key Rules

1. **Always create pending state file first** — Write to `/tmp/cursor-ralph-pending.json` so the hook can claim it (agent has no CURSOR_TRACE_ID)
2. **Update `last_output`** after meaningful work — Hook checks this for completion
3. **Output completion promise when done** — Exact match required
4. **Don't loop yourself** — The hook handles iteration automatically
5. **For `--continue`** — Read state from provided trace_id, not CURSOR_TRACE_ID

## Platform Notes

- **macOS**: osascript auto-continuation; grant Accessibility permissions; Cursor focused when session limit hits.
- **Linux (X11)**: xdotool auto-continuation; install `xdotool`; Cursor focused when limit hits.
- **Linux (Wayland)**: ydotool auto-continuation; install `ydotool` and run `ydotoold`; Cursor focused when limit hits.
- **WSL**: PowerShell SendKeys auto-continuation to Windows Cursor; keep Cursor focused when limit hits. If no tool works, run `/ralph-loop --continue <trace_id>` manually.
