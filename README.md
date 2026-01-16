# cursor-ralph

Agentic looping for Cursor IDE. Keeps the agent working on a task until it's done (or hits a safety limit).

This is a quick port of the "Not-quite-Ralph" loop from the [ralph-wiggum plugin](https://github.com/anthropics/claude-code/tree/main/plugins/ralph-wiggum) for Claude Code. Uses `osascript` on macOS to work around Cursor's 5-iteration stop hook limit.

> **macOS only.** Linux/Windows PRs welcome.

## What's a Ralph Loop?

The [Ralph Wiggum technique](https://ghuntley.com/ralph/) is an agentic pattern where you let the AI keep working in a loop until it declares the task complete. Instead of back-and-forth prompting, you give it a goal and let it run.

This implementation isn't the "true" Ralph loop (which uses more sophisticated state management) — it's a pragmatic version that works within Cursor's constraints.

## Installation

1. Clone this repo somewhere:
   ```bash
   git clone https://github.com/youruser/cursor-ralph.git ~/.cursor-ralph
   ```

2. Symlink the command into your Cursor commands directory:
   ```bash
   mkdir -p ~/.cursor/commands
   ln -s ~/.cursor-ralph/commands/ralph.md ~/.cursor/commands/ralph.md
   ```

3. Add the stop hook to your Cursor settings (`~/.cursor/settings.json`):
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

4. Grant Accessibility permissions to Cursor (System Settings → Privacy & Security → Accessibility). Required for the `osascript` workaround.

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

The key trick: Cursor limits `followup_message` chains to 5 iterations. When we hit that limit, the stop hook spawns an `osascript` process that waits 1.5 seconds then simulates typing `/ralph-loop --continue <trace_id>` into Cursor. This starts a "new" user message, resetting Cursor's internal counter while preserving our loop state.

## State File

Loop state is stored in `/tmp/cursor-ralph-loop-<trace_id>.json`:

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

- **macOS** (uses `osascript` for keyboard simulation)
- **jq** (`brew install jq`)
- **Cursor** with Accessibility permissions
- Cursor window must be focused when the session limit is hit

## Limitations

- macOS only — `osascript` doesn't exist on Linux/Windows
- Requires Cursor to be focused when session limit hits
- If `osascript` fails, loop stops at iteration 5 (you can manually continue)
- The 1.5s delay between sessions is a bit janky but necessary for reliability

## Credits

- Original Ralph Wiggum technique by [Geoffrey Huntley](https://ghuntley.com/ralph/)
- Based on the [ralph-wiggum plugin](https://github.com/anthropics/claude-code/tree/main/plugins/ralph-wiggum) for Claude Code
- This port by Jordan Baker

## License

MIT
