#!/bin/bash
# Ralph loop controller - runs after every agent response
# If in a ralph loop: increment iteration, check completion, optionally continue
# On macOS: uses osascript to bypass Cursor's 5-iteration limit on followup_message
# On Linux: xdotool/ydotool (native) or PowerShell SendKeys (WSL) to auto-continue; else manual

set -euo pipefail

CURSOR_ITERATION_LIMIT=5 # Cursor's built-in limit on followup_message chaining
RALPH_LOG="${RALPH_HOOK_LOG:-/tmp/cursor-ralph-stop-hook.log}"

log() {
  echo "$(date -Iseconds) [ralph-stop] $*" >> "$RALPH_LOG"
}

# conversation_id 来源：Cursor 通过 stdin 传 JSON，其中 conversation_id 即稳定会话 id，用于停下来时找到对应任务。
# 见 https://cursor.com/docs/agent/hooks 的 "Input (all hooks)" 与 "stop"。可选环境变量 CURSOR_CONVERSATION_ID（如手动测试）。
HOOK_INPUT=""
if [ -t 0 ]; then
  CONVERSATION_ID="${CURSOR_CONVERSATION_ID:-}"
else
  HOOK_INPUT=$(cat 2>/dev/null || true)
  CONVERSATION_ID="${CURSOR_CONVERSATION_ID:-}"
  if [ -z "$CONVERSATION_ID" ] && [ -n "$HOOK_INPUT" ] && command -v jq &>/dev/null; then
    CONVERSATION_ID=$(echo "$HOOK_INPUT" | jq -r '.conversation_id // empty')
  fi
fi
if [ -z "$CONVERSATION_ID" ]; then
  log "no conversation_id (env empty, stdin empty or no conversation_id); exiting early"
  [ -n "$HOOK_INPUT" ] && log "stdin_preview: $(echo "$HOOK_INPUT" | head -c 300)"
  exit 0
fi
log "CONVERSATION_ID=$CONVERSATION_ID (from stdin or env)"

STATE_FILE="/tmp/cursor-ralph-loop-${CONVERSATION_ID}.json"
PENDING_DIR="/tmp/cursor-ralph-pending"
LEGACY_PENDING_FILE="/tmp/cursor-ralph-pending.json"

claim_pending() {
  local src="$1"
  if [ -z "$src" ] || [ ! -f "$src" ]; then return 1; fi
  if command -v jq &>/dev/null; then
    jq '.iterations = (.iterations // 0) | .session_iterations = (.session_iterations // 0) | .stop = (.stop // false) | .last_output = (.last_output // "")' "$src" > "${STATE_FILE}.tmp" 2>/dev/null && mv "${STATE_FILE}.tmp" "$STATE_FILE" && rm -f "$src" && { log "claimed pending: $src -> $STATE_FILE"; return 0; }
  else
    mv "$src" "$STATE_FILE" && { log "claimed pending: $src -> $STATE_FILE"; return 0; }
  fi
  return 1
}

# Agent may create /tmp/cursor-ralph-pending/<conversation_id>.json (exact match) or a unique-named file (claim by newest)
if [ ! -f "$STATE_FILE" ]; then
  EXACT_PENDING="${PENDING_DIR}/${CONVERSATION_ID}.json"
  if [ -f "$EXACT_PENDING" ]; then
    claim_pending "$EXACT_PENDING" || true
  elif [ -d "$PENDING_DIR" ]; then
    NEWEST=$(ls -t "$PENDING_DIR"/*.json 2>/dev/null | head -1)
    if [ -n "$NEWEST" ] && [ -f "$NEWEST" ]; then
      claim_pending "$NEWEST" || true
    fi
  fi
fi
# Backward compatibility: single fixed pending file
if [ ! -f "$STATE_FILE" ] && [ -f "$LEGACY_PENDING_FILE" ]; then
  claim_pending "$LEGACY_PENDING_FILE" || true
fi

# If no state file, not in a ralph loop
if [ ! -f "$STATE_FILE" ]; then
  log "no state file ($STATE_FILE); not in ralph loop, exit"
  exit 0
fi
log "state_file=$STATE_FILE; processing"

# jq is required
if ! command -v jq &>/dev/null; then
  echo "{\"agent_message\": \"Ralph loop: jq is required. Install with: sudo apt install jq (or brew install jq)\"}"
  exit 0
fi

# Read state
STATE=$(cat "$STATE_FILE")
ITERATIONS=$(echo "$STATE" | jq -r '.iterations // 0')
SESSION_ITERATIONS=$(echo "$STATE" | jq -r '.session_iterations // 0')
MAX_ITERATIONS=$(echo "$STATE" | jq -r '.max_iterations // 20')
COMPLETION_PROMISE=$(echo "$STATE" | jq -r '.completion_promise // "COMPLETE"')
PROMPT=$(echo "$STATE" | jq -r '.prompt // ""')
STOP=$(echo "$STATE" | jq -r '.stop // false')
LAST_OUTPUT=$(echo "$STATE" | jq -r '.last_output // ""')

# If user clicked stop, exit silently (don't continue loop)
if [ "$STOP" = "true" ]; then
  log "stop=true; removing state, exit"
  rm -f "$STATE_FILE"
  exit 0
fi

# Increment both counters
NEW_ITERATIONS=$((ITERATIONS + 1))
NEW_SESSION_ITERATIONS=$((SESSION_ITERATIONS + 1))
jq --argjson iter "$NEW_ITERATIONS" --argjson sess "$NEW_SESSION_ITERATIONS" \
  '.iterations = $iter | .session_iterations = $sess' "$STATE_FILE" > "${STATE_FILE}.tmp" \
  && mv "${STATE_FILE}.tmp" "$STATE_FILE"

# Check if max iterations reached
if [ "$NEW_ITERATIONS" -ge "$MAX_ITERATIONS" ]; then
  log "max_iterations ($MAX_ITERATIONS) reached; stopping"
  rm -f "$STATE_FILE"
  echo "{\"agent_message\": \"Max iterations ($MAX_ITERATIONS) reached. Stopping ralph loop.\"}"
  exit 0
fi

# Check if completion promise was found in last output
if [ -n "$LAST_OUTPUT" ] && echo "$LAST_OUTPUT" | grep -qF "$COMPLETION_PROMISE"; then
  log "completion_promise found in last_output; stopping"
  rm -f "$STATE_FILE"
  echo "{\"agent_message\": \"Task completed after $NEW_ITERATIONS iterations.\"}"
  exit 0
fi

# Check if we're hitting Cursor's session limit
if [ "$NEW_SESSION_ITERATIONS" -ge "$CURSOR_ITERATION_LIMIT" ]; then
  # Reset session counter for next session
  jq '.session_iterations = 0' "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"

  # macOS: spawn osascript to continue the loop in a new session
  if [[ "$(uname -s)" == "Darwin" ]] && command -v osascript &>/dev/null; then
    osascript -e "
      delay 1.5
      tell application \"Cursor\" to activate
      delay 0.3
      tell application \"System Events\"
        keystroke \"/ralph-loop --continue ${CONVERSATION_ID}\"
        keystroke return
      end tell
    " &>/dev/null &
    echo "{\"agent_message\": \"Session limit reached. Continuing automatically... (iteration $NEW_ITERATIONS of $MAX_ITERATIONS)\"}"
    exit 0
  fi

  # Linux: try xdotool (X11) or ydotool (Wayland) to type continue command
  if [[ "$(uname -s)" == "Linux" ]]; then
    CONTINUE_CMD="/ralph-loop --continue ${CONVERSATION_ID}"
    if command -v xdotool &>/dev/null; then
      ( sleep 2; xdotool type --delay 12 "$CONTINUE_CMD"; xdotool key Return ) &>/dev/null &
      echo "{\"agent_message\": \"Session limit reached. Continuing automatically (xdotool)... (iteration $NEW_ITERATIONS of $MAX_ITERATIONS)\"}"
      exit 0
    fi
    if command -v ydotool &>/dev/null; then
      ( sleep 2; echo -n "$CONTINUE_CMD" | ydotool type -f -; ydotool key 28:1 28:0 ) &>/dev/null &
      echo "{\"agent_message\": \"Session limit reached. Continuing automatically (ydotool)... (iteration $NEW_ITERATIONS of $MAX_ITERATIONS)\"}"
      exit 0
    fi

    # WSL: write command to temp file, set clipboard via clip.exe, then paste (avoids IME / vs 、 and wrong clipboard)
    if grep -qi microsoft /proc/version 2>/dev/null; then
      PS_EXE=""
      for p in powershell.exe /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe /mnt/c/Windows/SysWOW64/WindowsPowerShell/v1.0/powershell.exe; do
        if command -v "$p" &>/dev/null || [ -x "$p" ] 2>/dev/null; then PS_EXE="$p"; break; fi
      done
      if [ -n "$PS_EXE" ]; then
        WIN_TEMP="${WIN_TEMP:-/mnt/c/Windows/Temp}"
        CMD_FILE="$WIN_TEMP/ralph-paste-cmd.txt"
        if printf '%s' "ralph-loop --continue $CONVERSATION_ID" > "$CMD_FILE" 2>/dev/null; then
          WIN_CMD="$(wslpath -w "$CMD_FILE" 2>/dev/null || echo "C:\\Windows\\Temp\\ralph-paste-cmd.txt")"
          ( sleep 2; "$PS_EXE" -NoProfile -Command "
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Threading;
public class SendUnicode {
  [DllImport(\"user32.dll\")] public static extern uint SendInput(uint n, INPUT[] p, int size);
  public const int INPUT_KEYBOARD=1, KEYEVENTF_UNICODE=0x0004, KEYEVENTF_KEYUP=0x0002;
  [StructLayout(LayoutKind.Sequential)] public struct KEYBDINPUT { public ushort wVk; public ushort wScan; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
  [StructLayout(LayoutKind.Sequential)] public struct INPUT { public int type; public KEYBDINPUT ki; }
  public static void SendChar(char c) {
    var down = new INPUT(); down.type = INPUT_KEYBOARD; down.ki.wVk = 0; down.ki.wScan = c; down.ki.dwFlags = KEYEVENTF_UNICODE;
    var up   = new INPUT(); up.type = INPUT_KEYBOARD; up.ki.wVk = 0; up.ki.wScan = c; up.ki.dwFlags = KEYEVENTF_UNICODE | KEYEVENTF_KEYUP;
    SendInput(1, new INPUT[] { down }, Marshal.SizeOf(typeof(INPUT)));
    Thread.Sleep(50);
    SendInput(1, new INPUT[] { up }, Marshal.SizeOf(typeof(INPUT)));
  }
}
'@
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class WindowClick {
  [DllImport(\"user32.dll\")] public static extern IntPtr GetForegroundWindow();
  [DllImport(\"user32.dll\")] public static extern bool GetWindowRect(IntPtr hwnd, out RECT lpRect);
  [DllImport(\"user32.dll\")] public static extern bool SetCursorPos(int x, int y);
  [DllImport(\"user32.dll\")] public static extern void mouse_event(uint dwFlags, int dx, int dy, uint dwData, UIntPtr dwExtraInfo);
  public const uint MOUSEEVENTF_LEFTDOWN = 0x0002, MOUSEEVENTF_LEFTUP = 0x0004;
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  public static void ClickForegroundBottomCenter(int offsetFromBottom) {
    IntPtr h = GetForegroundWindow();
    RECT r; GetWindowRect(h, out r);
    int x = r.Left + (r.Right - r.Left) / 2;
    int y = r.Bottom - offsetFromBottom;
    SetCursorPos(x, y);
    mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, UIntPtr.Zero);
    mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, UIntPtr.Zero);
  }
}
'@
\$clip = \$env:SystemRoot + '\System32\clip.exe'
\$w = New-Object -ComObject wscript.shell
[void]\$w.AppActivate('Cursor')
Start-Sleep -Milliseconds 500
\$w.SendKeys('^{\`}')
Start-Sleep -Milliseconds 400
\$w.SendKeys('^l')
Start-Sleep -Milliseconds 700
\$w.SendKeys('{ESCAPE}')
Start-Sleep -Milliseconds 350
[WindowClick]::ClickForegroundBottomCenter(80)
Start-Sleep -Milliseconds 200
\$w.SendKeys('^a')
Start-Sleep -Milliseconds 300
[SendUnicode]::SendChar('/')
Start-Sleep -Milliseconds 200
[SendUnicode]::SendChar('/')
Start-Sleep -Milliseconds 500
Get-Content -Path '$WIN_CMD' -Raw | & \$clip | Out-Null
\$w.SendKeys('^v')
Start-Sleep -Milliseconds 300
\$w.SendKeys('~')
[void](Remove-Item -Path '$WIN_CMD' -Force -ErrorAction SilentlyContinue)
" ) &>/dev/null &
          echo "{\"agent_message\": \"Session limit reached. Continuing automatically (WSL→Windows)... (iteration $NEW_ITERATIONS of $MAX_ITERATIONS)\"}"
          exit 0
        fi
      fi
    fi
  fi

  # Fallback: tell user to continue manually
  echo "{\"agent_message\": \"Session limit (5) reached. To continue, run: /ralph-loop --continue ${CONVERSATION_ID} (iteration $NEW_ITERATIONS of $MAX_ITERATIONS)\"}"
  exit 0
fi

# Continue the loop normally - return followup_message (use jq for proper JSON escaping)
log "returning followup_message; iter=$NEW_ITERATIONS sess=$NEW_SESSION_ITERATIONS"
jq -n \
  --arg prompt "$PROMPT" \
  --arg iter "$NEW_ITERATIONS" \
  --arg max "$MAX_ITERATIONS" \
  --arg promise "$COMPLETION_PROMISE" \
  --arg state_file "$STATE_FILE" \
  '{followup_message: "Continue working on: \($prompt)\n\nIteration \($iter) of \($max).\n\nWhen complete, output exactly: \($promise)\n\nTo record your progress, update the state file:\njq --arg out '\''YOUR_OUTPUT_SUMMARY'\'' '\''.last_output = $out'\'' \"\($state_file)\" > tmp && mv tmp \"\($state_file)\""}'
