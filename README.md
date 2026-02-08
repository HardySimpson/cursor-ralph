# cursor-ralph

Agentic looping for Cursor IDE. Keeps the agent working on a task until it's done (or hits a safety limit).

This is a quick port of the "Not-quite-Ralph" loop from the [ralph-wiggum plugin](https://github.com/anthropics/claude-code/tree/main/plugins/ralph-wiggum) for Claude Code. Uses `osascript` on macOS to work around Cursor's 5-iteration stop hook limit.

> **macOS**: full auto-continuation (osascript). **Linux**: auto-continuation via `xdotool` (X11) or `ydotool` (Wayland). **WSL**: auto-continuation via PowerShell SendKeys to the Windows Cursor window. If no tool is available, you can still run `/ralph-loop --continue <trace_id>` manually.

## What's a Ralph Loop?

The [Ralph Wiggum technique](https://ghuntley.com/ralph/) is an agentic pattern where you let the AI keep working in a loop until it declares the task complete. Instead of back-and-forth prompting, you give it a goal and let it run.

This implementation isn't the "true" Ralph loop (which uses more sophisticated state management) — it's a pragmatic version that works within Cursor's constraints.

## Installation

1. Clone this repo somewhere:
   ```bash
   git clone https://github.com/youruser/cursor-ralph.git ~/.cursor-ralph
   ```

2. Symlink the command into your Cursor commands directory (use `ralph-loop.md` so the slash command is `/ralph-loop`):
   ```bash
   mkdir -p ~/.cursor/commands
   ln -s ~/.cursor-ralph/commands/ralph-loop.md ~/.cursor/commands/ralph-loop.md
   ```

3. Add the stop hook to your Cursor config. Either `~/.cursor/hooks.json` (Cursor native) or `~/.cursor/settings.json`:
   ```json
   {
     "hooks": {
       "stop": [
         {
           "command": "~/.cursor-ralph/hooks/ralph-loop-stop.sh"
         }
       ]
     }
   }
   ```
   Or in `~/.cursor/hooks.json`: `{"version":1,"hooks":{"stop":[{"command":"/path/to/cursor-ralph/hooks/ralph-loop-stop.sh"}]}}`

4. **macOS only**: Grant Accessibility permissions to Cursor (System Settings → Privacy & Security → Accessibility). Required for the `osascript` auto-continuation.

## Usage

```
/ralph-loop "your task description"
```

### Options

| Flag | Default | Description |
|------|---------|-------------|
| `--max-iterations <n>` | 20 | Safety limit to prevent runaway loops |
| `--completion-promise "<text>"` | `COMPLETE` | The exact string the agent outputs when done |

### Examples

```bash
# Run tests until coverage hits 80%
/ralph-loop "Add tests until we hit 80% coverage" --max-iterations 30

# Fix all TypeScript errors
/ralph-loop "Fix all type errors in src/" --max-iterations 15

# Custom completion signal
/ralph-loop "Refactor auth module" --completion-promise "REFACTOR_DONE"
```

## How It Works

```
┌─────────────────────────────────────────────────────────────┐
│                     User: /ralph-loop "task"                │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│  Agent works on task, updates state file with progress      │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│  Stop hook runs after agent response                        │
│  ├─ Check for completion promise → Done? Clean up & exit    │
│  ├─ Check max iterations → Hit limit? Clean up & exit       │
│  ├─ Session < 5? → Return followup_message to continue      │
│  └─ Session = 5? → osascript types new /ralph-loop command  │
└─────────────────────────────────────────────────────────────┘
                          │
                          ▼
                    (loop continues)
```

The key trick: Cursor limits `followup_message` chains to 5 iterations. When we hit that limit, the stop hook auto-continues by typing `/ralph-loop --continue <trace_id>` into Cursor: **macOS** uses `osascript`, **Linux** uses `xdotool` or `ydotool`, **WSL** uses PowerShell `SendKeys` to the Windows Cursor window (keep Cursor focused or its window title containing "Cursor").

**Pending state file**: The agent does not receive `CURSOR_TRACE_ID`. It writes `/tmp/cursor-ralph-pending.json`; the stop hook renames it to `/tmp/cursor-ralph-loop-<trace_id>.json` so the loop can continue.

## State File

Loop state is stored in `/tmp/cursor-ralph-loop-<trace_id>.json` (after the hook "claims" the pending file on first run). Initial state is created by the agent at `/tmp/cursor-ralph-pending.json`:

```json
{
  "prompt": "the original task",
  "max_iterations": 20,
  "completion_promise": "COMPLETE",
  "iterations": 7,
  "session_iterations": 2,
  "stop": false,
  "last_output": "Added 3 test files, coverage now at 74%"
}
```

## Requirements

- **jq** (`brew install jq` or `sudo apt install jq`)
- **Cursor**
- **Auto-continuation (optional but recommended)**:
  - **macOS**: Accessibility permissions; Cursor focused when session limit hits
  - **Linux (X11)**: `xdotool` (e.g. `sudo apt install xdotool`). Cursor focused when limit hits.
  - **Linux (Wayland)**: `ydotool` (e.g. `sudo apt install ydotool`; run `ydotoold`). Cursor focused when limit hits.
  - **WSL**: PowerShell available (default on Windows). Cursor window title should contain "Cursor"; keep Cursor focused when limit hits for best results.

## Limitations

- If no auto-continuation tool is available (or it fails), after 5 iterations run `/ralph-loop --continue <trace_id>` manually.
- Cursor should be focused when the session limit is hit so the typed command goes into the chat input.
- The ~2s delay before typing is for Cursor UI to settle.

## Credits

- Original Ralph Wiggum technique by [Geoffrey Huntley](https://ghuntley.com/ralph/)
- Based on the [ralph-wiggum plugin](https://github.com/anthropics/claude-code/tree/main/plugins/ralph-wiggum) for Claude Code
- This port by Jordan Baker

## License

MIT
