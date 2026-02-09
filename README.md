# cursor-ralph

Agentic looping for Cursor IDE. Keeps the agent working on a task until it's done (or hits a safety limit).

This is a quick port of the "Not-quite-Ralph" loop from the [ralph-wiggum plugin](https://github.com/anthropics/claude-code/tree/main/plugins/ralph-wiggum) for Claude Code. A stop hook uses platform-specific tools to work around Cursor's 5-iteration limit.

**中文说明** → [README-cn.md](README-cn.md)

## Installation

**Recommended:** run the install script from the repo root. It installs the `/ralph-loop` command and configures the stop hook for your environment (user and, on WSL, often `/root` too):

```bash
git clone https://github.com/youruser/cursor-ralph.git ~/.cursor-ralph
cd ~/.cursor-ralph
./install-commands.sh
```

- **No args:** installs to global Cursor config (`~/.cursor`, and on WSL also `/root/.cursor` when relevant).
- **`--local` / `-l`:** also installs to the project’s `.cursor/` (script directory).
- **`--local-only`:** installs only to the project’s `.cursor/`.

**macOS:** Grant Accessibility permissions to Cursor (System Settings → Privacy & Security → Accessibility) for auto-continuation.

Then fully quit and reopen Cursor (or reload the window) so the command and hook are loaded.

### Manual installation

If you prefer not to use the script:

1. Copy `commands/ralph-loop.md` to `~/.cursor/commands/ralph-loop.md` (Linux/macOS) or `%USERPROFILE%\.cursor\commands\ralph-loop.md` (Windows). Create `commands` if needed.
2. Add the stop hook in `~/.cursor/hooks.json` (or `~/.cursor/settings.json`):
   ```json
   { "version": 1, "hooks": { "stop": [ { "command": "/path/to/cursor-ralph/hooks/ralph-loop-stop.sh" } ] } }
   ```
3. On macOS, grant Cursor Accessibility permissions for auto-continuation.

## Supported operating systems

| OS / environment | Auto-continuation | Notes |
|------------------|-------------------|--------|
| **macOS** | ✅ `osascript` | Grant Cursor Accessibility permission; keep Cursor focused when the session limit hits. |
| **Linux (X11)** | ✅ `xdotool` | Install: `sudo apt install xdotool` (or distro equivalent). Cursor focused when limit hits. |
| **Linux (Wayland)** | ✅ `ydotool` | Install: `sudo apt install ydotool`; run `ydotoold`. Cursor focused when limit hits. |
| **WSL** | ✅ PowerShell SendKeys | Sends input to the Windows Cursor window. When the script runs inside a terminal, it sends **Ctrl+`** to leave the terminal, then Ctrl+L and Escape, and simulates a click at the window bottom-center to focus the chat input before typing the continue command. |
| **Windows (native)** | ⚠️ Manual | No auto-type; after 5 iterations run `/ralph-loop --continue <conversation_id>` manually. |

If no auto-continuation is available (or it fails), run `/ralph-loop --continue <conversation_id>` manually after 5 iterations.

**Using with community extensions:** You can install [Cursor Auto Continue](https://marketplace.visualstudio.com/items?itemName=risalabs.cursor-auto-continue) or [cursor-auto-resume](https://github.com/thelastbackspace/cursor-auto-resume) alongside ralph-loop to handle both the **5-round limit** and the **25 tool-call / rate limit**. If auto-continue fails, type the continue command manually in the chat. See [docs/COMMUNITY-EXTENSIONS-AND-MANUAL-CONTINUE.md](docs/COMMUNITY-EXTENSIONS-AND-MANUAL-CONTINUE.md).

## What's a Ralph Loop?

The [Ralph Wiggum technique](https://ghuntley.com/ralph/) is an agentic pattern where you let the AI keep working in a loop until it declares the task complete. Instead of back-and-forth prompting, you give it a goal and let it run.

This implementation isn't the "true" Ralph loop (which uses more sophisticated state management) — it's a pragmatic version that works within Cursor's constraints.

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

The key trick: Cursor limits `followup_message` chains to 5 iterations. When we hit that limit, the stop hook auto-continues by typing `/ralph-loop --continue <conversation_id>` into Cursor (see [Supported operating systems](#supported-operating-systems) for per-OS behavior).

**Pending state file:** The hook has `CURSOR_CONVERSATION_ID`; the agent should write `/tmp/cursor-ralph-pending/${CURSOR_CONVERSATION_ID}.json` when that env var is set so the hook claims the right file. Otherwise the agent uses a unique filename and the hook claims by newest mtime (best-effort; avoid multiple concurrent loops). Legacy `/tmp/cursor-ralph-pending.json` is still supported.

## State File

Loop state is stored in `/tmp/cursor-ralph-loop-<conversation_id>.json` (after the hook "claims" a pending file on first run). Initial state is created by the agent as a unique file under `/tmp/cursor-ralph-pending/`:

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
- **Auto-continuation:** see [Supported operating systems](#supported-operating-systems) for per-OS tools and setup.

## Limitations

- Cursor should be focused when the session limit is hit so the typed command goes into the chat input.
- The ~2s delay before typing is for Cursor UI to settle.

## Troubleshooting

- **`/ralph-loop` does not appear**  
  Use **`./install-commands.sh`** from the repo root; it installs the command and hook to the right places (including `/root/.cursor` on WSL when relevant). Cursor loads from the opened folder’s `.cursor/commands` and the user config `commands` directory — ensure the command is a real file there, then fully quit and reopen Cursor (or reload the window).

- **Commands are in Beta**  
  If the slash command list is empty, enable Commands in Cursor Settings (Beta / Features) if available.

- **WSL: command appears in terminal, or only "bash" is recognized**  
  When the script runs in a terminal, focus is there and Ctrl+L is clear-screen in bash. The script sends **Ctrl+`** to leave the terminal, then Ctrl+L and **Escape**, then **simulates a click at the bottom-center of the Cursor window** to move focus into the chat input before typing the continue command. If it still fails, run `/ralph-loop --continue <conversation_id>` manually in the chat when you hit the 5-iteration limit. See [docs/WSL-CURSOR-FOCUS-INVESTIGATION.md](docs/WSL-CURSOR-FOCUS-INVESTIGATION.md) for a deeper analysis.

- **Using extensions to also bypass the 25 tool-call limit, or how to continue manually**  
  See [docs/COMMUNITY-EXTENSIONS-AND-MANUAL-CONTINUE.md](docs/COMMUNITY-EXTENSIONS-AND-MANUAL-CONTINUE.md).

## Credits

- Original Ralph Wiggum technique by [Geoffrey Huntley](https://ghuntley.com/ralph/)
- Based on the [ralph-wiggum plugin](https://github.com/anthropics/claude-code/tree/main/plugins/ralph-wiggum) for Claude Code
- This port by Jordan Baker

## License

MIT
