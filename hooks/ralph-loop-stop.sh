#!/bin/bash
# Ralph loop controller - runs after every agent response
# If in a ralph loop: increment iteration, check completion, optionally continue
# On macOS: uses osascript to bypass Cursor's 5-iteration limit on followup_message
# On Linux: loop stops at 5 iterations; user can manually run /ralph-loop --continue <trace_id>

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
  else
    # Linux/WSL: no osascript — tell user to continue manually
    echo "{\"agent_message\": \"Session limit (5) reached. To continue, run: /ralph-loop --continue ${TRACE_ID} (iteration $NEW_ITERATIONS of $MAX_ITERATIONS)\"}"
  fi
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
