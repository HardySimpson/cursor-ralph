# Ralph Wiggum Loop Command

Iterative refinement loop that keeps working until complete. The **stop hook** controls iteration and uses `osascript` (macOS) to bypass Cursor's 5-iteration limit.

## Usage

```
/ralph-loop "<task>" [--max-iterations <n>] [--completion-promise "<text>"]
/ralph-loop --continue <conversation_id>
```

- **`<task>`** (required) — Task description
- **`--max-iterations <n>`** — Safety limit (default: 20)
- **`--completion-promise "<text>"`** — Completion signal (default: "COMPLETE")
- **`--continue <conversation_id>`** — Resume from existing state (used by auto-continuation)

**If no prompt provided**: Print error with usage and stop.

## On Invocation

### New Loop

1. **Validate arguments** — Error if no prompt
2. **Create pending state file** in **`/tmp/cursor-ralph-pending/`**. To **guarantee** the hook claims the right file, use the same id the hook has: if **`CURSOR_CONVERSATION_ID`** is set, write to **`/tmp/cursor-ralph-pending/${CURSOR_CONVERSATION_ID}.json`** (exact match). Otherwise use a **unique filename** (e.g. `$(date +%s%3N)-$$.json`); the hook will then claim by newest mtime (best-effort; avoid multiple concurrent loops). Write this exact JSON (adjust prompt/max_iterations/completion_promise from args):

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

Use a shell command, e.g. (prefer conversation_id for exact match):
`PEND_DIR=/tmp/cursor-ralph-pending; PEND_NAME="${CURSOR_CONVERSATION_ID:-$(date +%s%3N)-$$}.json"; mkdir -p "$PEND_DIR" && echo '{"prompt":"<task>","max_iterations":20,"completion_promise":"COMPLETE","iterations":0,"session_iterations":0,"stop":false,"last_output":""}' > "$PEND_DIR/$PEND_NAME"`
(Replace `<task>` and options from the user's flags. When `CURSOR_CONVERSATION_ID` is set, the hook will claim that file; otherwise it uses newest-by-mtime.)

3. Output brief confirmation and start working on the task.

### --continue

1. **Read state** from `/tmp/cursor-ralph-loop-<conversation_id>.json` (use the conversation_id argument, not CURSOR_CONVERSATION_ID)
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
7. If session = 5 (Cursor limit) → on macOS use osascript to type `/ralph-loop --continue <conversation_id>` so a new "user message" resets Cursor's internal limit. On Linux, loop stops at 5 unless you manually run the continue command.

**User clicking Stop** sets `stop: true` in state file — hook detects this and exits.

## Key Rules

1. **Always create pending state file first** — Prefer **`/tmp/cursor-ralph-pending/${CURSOR_CONVERSATION_ID}.json`** when `CURSOR_CONVERSATION_ID` is set (guarantees hook claims the right file); else use a unique name under `/tmp/cursor-ralph-pending/` so the hook can claim by newest (best-effort)
2. **Update `last_output`** after meaningful work — Hook checks this for completion
3. **Output completion promise when done** — Exact match required
4. **Don't loop yourself** — The hook handles iteration automatically
5. **For `--continue`** — Read state from provided conversation_id, not CURSOR_CONVERSATION_ID

## Platform Notes

- **macOS**: osascript auto-continuation; grant Accessibility permissions; Cursor focused when session limit hits.
- **Linux (X11)**: xdotool auto-continuation; install `xdotool`; Cursor focused when limit hits.
- **Linux (Wayland)**: ydotool auto-continuation; install `ydotool` and run `ydotoold`; Cursor focused when limit hits.
- **WSL**: PowerShell SendKeys auto-continuation to Windows Cursor; keep Cursor focused when limit hits. If no tool works, run `/ralph-loop --continue <conversation_id>` manually.
