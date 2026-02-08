#!/bin/bash
# Ralph loop controller - runs after every agent response
# If in a ralph loop: increment iteration, check completion, optionally continue
# On macOS: uses osascript to bypass Cursor's 5-iteration limit on followup_message
# On Linux: xdotool/ydotool (native) or PowerShell SendKeys (WSL) to auto-continue; else manual

set -euo pipefail

CURSOR_ITERATION_LIMIT=5 # Cursor's built-in limit on followup_message chaining

TRACE_ID="${CURSOR_TRACE_ID:-}"

# If no trace ID, nothing to do
if [ -z "$TRACE_ID" ]; then
  exit 0
fi

STATE_FILE="/tmp/cursor-ralph-loop-${TRACE_ID}.json"
PENDING_FILE="/tmp/cursor-ralph-pending.json"

# Agent creates pending file (no CURSOR_TRACE_ID in agent env); hook "claims" it with trace_id
if [ -f "$PENDING_FILE" ]; then
  if command -v jq &>/dev/null; then
    jq '.iterations = (.iterations // 0) | .session_iterations = (.session_iterations // 0) | .stop = (.stop // false) | .last_output = (.last_output // "")' "$PENDING_FILE" > "${STATE_FILE}.tmp" 2>/dev/null && mv "${STATE_FILE}.tmp" "$STATE_FILE" && rm -f "$PENDING_FILE"
  else
    mv "$PENDING_FILE" "$STATE_FILE"
  fi
fi

# If no state file, not in a ralph loop
if [ ! -f "$STATE_FILE" ]; then
  exit 0
fi

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
  rm -f "$STATE_FILE"
  echo "{\"agent_message\": \"Max iterations ($MAX_ITERATIONS) reached. Stopping ralph loop.\"}"
  exit 0
fi

# Check if completion promise was found in last output
if [ -n "$LAST_OUTPUT" ] && echo "$LAST_OUTPUT" | grep -qF "$COMPLETION_PROMISE"; then
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
        keystroke \"/ralph-loop --continue ${TRACE_ID}\"
        keystroke return
      end tell
    " &>/dev/null &
    echo "{\"agent_message\": \"Session limit reached. Continuing automatically... (iteration $NEW_ITERATIONS of $MAX_ITERATIONS)\"}"
    exit 0
  fi

  # Linux: try xdotool (X11) or ydotool (Wayland) to type continue command
  if [[ "$(uname -s)" == "Linux" ]]; then
    CONTINUE_CMD="/ralph-loop --continue ${TRACE_ID}"
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

    # WSL: try PowerShell SendKeys to control Windows Cursor window (Cursor must be focused or have "Cursor" in title)
    if grep -qi microsoft /proc/version 2>/dev/null; then
      PS_EXE=""
      for p in powershell.exe /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe /mnt/c/Windows/SysWOW64/WindowsPowerShell/v1.0/powershell.exe; do
        if command -v "$p" &>/dev/null || [ -x "$p" ] 2>/dev/null; then PS_EXE="$p"; break; fi
      done
      if [ -n "$PS_EXE" ]; then
        TID_SAFE="${TRACE_ID//\'/\'\'\'}"
        ( sleep 2; "$PS_EXE" -NoProfile -Command "\$tid='$TID_SAFE'; \$w=New-Object -ComObject wscript.shell; \$w.AppActivate('Cursor'); Start-Sleep -Milliseconds 400; \$w.SendKeys(\"/ralph-loop --continue \" + \$tid); \$w.SendKeys('~')" ) &>/dev/null &
        echo "{\"agent_message\": \"Session limit reached. Continuing automatically (WSL→Windows)... (iteration $NEW_ITERATIONS of $MAX_ITERATIONS)\"}"
        exit 0
      fi
    fi
  fi

  # Fallback: tell user to continue manually
  echo "{\"agent_message\": \"Session limit (5) reached. To continue, run: /ralph-loop --continue ${TRACE_ID} (iteration $NEW_ITERATIONS of $MAX_ITERATIONS)\"}"
  exit 0
fi

# Continue the loop normally - return followup_message (use jq for proper JSON escaping)
jq -n \
  --arg prompt "$PROMPT" \
  --arg iter "$NEW_ITERATIONS" \
  --arg max "$MAX_ITERATIONS" \
  --arg promise "$COMPLETION_PROMISE" \
  --arg state_file "$STATE_FILE" \
  '{followup_message: "Continue working on: \($prompt)\n\nIteration \($iter) of \($max).\n\nWhen complete, output exactly: \($promise)\n\nTo record your progress, update the state file:\njq --arg out '\''YOUR_OUTPUT_SUMMARY'\'' '\''.last_output = $out'\'' \"\($state_file)\" > tmp && mv tmp \"\($state_file)\""}'
