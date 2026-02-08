#!/bin/bash
# 测试 hook 在「第 5 轮后」是否走自动续跑分支（WSL/Linux/macOS）
# 用法: ./test-hook-session-limit.sh

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/hooks/ralph-loop-stop.sh"
[ ! -x "$HOOK" ] && HOOK="$HOME/.cursor-ralph/hooks/ralph-loop-stop.sh"
if [ ! -f "$HOOK" ] || [ ! -x "$HOOK" ]; then
  echo "Hook not found or not executable: $HOOK"
  exit 1
fi

# 清除可能干扰的 pending
rm -f /tmp/cursor-ralph-pending.json

TRACE_ID="test-$(date +%s)"
STATE_FILE="/tmp/cursor-ralph-loop-${TRACE_ID}.json"
# 模拟第 5 轮结束时的状态（hook 会先 +1 变成第 6 轮，然后发现 session >= 5 走自动续跑）
echo '{"prompt":"test task","max_iterations":20,"completion_promise":"COMPLETE","iterations":5,"session_iterations":5,"stop":false,"last_output":""}' > "$STATE_FILE"

echo "State file: $STATE_FILE"
echo "Running hook with CURSOR_TRACE_ID=$TRACE_ID ..."
echo "---"
export CURSOR_TRACE_ID="$TRACE_ID"
"$HOOK"
echo "---"
echo "Done. If you see 'Continuing automatically (WSL→Windows)' or similar, the over-5 iteration path works."
