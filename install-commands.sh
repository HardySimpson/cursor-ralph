#!/bin/bash
# 将 ralph-loop 命令安装到 Cursor 能加载的位置，避免新实例中看不到 /ralph-loop
# 默认：在当前目录下创建/使用 .cursor 并安装（在项目根目录执行脚本即可）
# 支持 --global / -g：同时安装到全局 ~/.cursor、/root/.cursor 等
# 支持 --project PATH / -p PATH：安装到指定目录的 .cursor/（PATH 可为 . 表示当前目录）
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CMD_SRC="$SCRIPT_DIR/commands/ralph-loop.md"
CWD="$(pwd)"

DO_CWD=true
DO_GLOBAL=false
PROJECT_DIR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --global|-g) DO_GLOBAL=true ;;
    --project|-p)
      [ $# -gt 1 ] || { echo "Error: --project requires PATH" >&2; exit 1; }
      PROJECT_DIR="$2"
      shift
      ;;
    --help|-h)
      echo "Usage: $0 [OPTIONS]"
      echo "  (no args)       Install to current directory .cursor/ (recommended: run from project root)"
      echo "  --global, -g    Also install to global Cursor config (~/.cursor, /root/.cursor, etc.)"
      echo "  --project PATH  Install to PATH/.cursor/ (PATH can be . for cwd)"
      echo "  -p PATH         Same as --project"
      exit 0
      ;;
  esac
  shift
done

install_to() {
  local dir="$1"
  mkdir -p "$dir/commands"
  if [ -f "$CMD_SRC" ]; then
    cp "$CMD_SRC" "$dir/commands/ralph-loop.md"
    echo "Installed: $dir/commands/ralph-loop.md"
  fi
}

# Hook 脚本路径：始终用当前仓库内的脚本（支持任意安装路径）
HOOK_SCRIPT="$SCRIPT_DIR/hooks/ralph-loop-stop.sh"

# 写入或合并 hooks.json，确保 stop 里包含当前 HOOK_SCRIPT
write_hooks_json() {
  local dir="$1"
  local hooks_file="$dir/hooks.json"
  mkdir -p "$dir"
  if [ ! -f "$hooks_file" ]; then
    printf '%s\n' '{ "version": 1, "hooks": { "stop": [ { "command": "'"$HOOK_SCRIPT"'" } ] } }' > "$hooks_file"
    echo "Created: $hooks_file (hook: $HOOK_SCRIPT)"
    return
  fi
  # 已存在：用 jq 合并 stop 数组，避免覆盖其他 hook；无 jq 则整体覆盖
  if command -v jq &>/dev/null; then
    local new_json
    if new_json=$(jq --arg cmd "$HOOK_SCRIPT" '
      .hooks.stop = ((.hooks.stop // []) | map(select(.command != $cmd)) | . + [{ "command": $cmd }])
    | .version = (.version // 1)
    ' "$hooks_file" 2>/dev/null); then
      echo "$new_json" > "$hooks_file"
      echo "Updated: $hooks_file (hook: $HOOK_SCRIPT)"
    else
      printf '%s\n' '{ "version": 1, "hooks": { "stop": [ { "command": "'"$HOOK_SCRIPT"'" } ] } }' > "$hooks_file"
      echo "Updated: $hooks_file (hook: $HOOK_SCRIPT, overwritten)"
    fi
  else
    printf '%s\n' '{ "version": 1, "hooks": { "stop": [ { "command": "'"$HOOK_SCRIPT"'" } ] } }' > "$hooks_file"
    echo "Updated: $hooks_file (hook: $HOOK_SCRIPT)"
  fi
}

# 为指定 .cursor 目录安装命令并创建/更新 hooks.json
install_with_hook() {
  local dir="$1"
  install_to "$dir"
  if [ -f "$HOOK_SCRIPT" ]; then
    write_hooks_json "$dir"
  else
    echo "Warning: hook script not found, skipping hooks.json: $HOOK_SCRIPT" >&2
  fi
}

if [ ! -f "$CMD_SRC" ]; then
  echo "Not found: $CMD_SRC"
  exit 1
fi

# 当前目录安装：在运行脚本的目录下创建/使用 .cursor/
if [ "$DO_CWD" = true ]; then
  CWD_CURSOR="$CWD/.cursor"
  install_with_hook "$CWD_CURSOR"
  echo ""
  echo "Current dir .cursor: $CWD_CURSOR"
fi

# 指定项目目录安装：安装到 PATH/.cursor/
if [ -n "$PROJECT_DIR" ]; then
  PROJECT_CURSOR="$(cd "$PROJECT_DIR" && pwd)/.cursor"
  install_with_hook "$PROJECT_CURSOR"
  echo ""
  echo "Project .cursor: $PROJECT_CURSOR"
fi

# 全局安装（可选）
if [ "$DO_GLOBAL" = true ]; then
  install_with_hook "${CURSOR_HOME:-$HOME/.cursor}"

  if [ "$(whoami)" = "root" ]; then
    install_with_hook "/root/.cursor"
  fi

  if [ "$(whoami)" = "root" ] && [ -d /home/hardy ] && [ -w /home/hardy ]; then
    install_with_hook "/home/hardy/.cursor"
  fi

  if grep -qi microsoft /proc/version 2>/dev/null; then
    echo ""
    echo "If Cursor runs on Windows (not WSL), copy the command to Windows:"
    echo "  To: %USERPROFILE%\\.cursor\\commands\\ralph-loop.md"
  fi
fi
