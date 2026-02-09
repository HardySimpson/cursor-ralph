#!/bin/bash
# 将 ralph-loop 命令安装到 Cursor 能加载的位置，避免新实例中看不到 /ralph-loop
# WSL 下 Cursor 常用 root 运行，会读 /root/.cursor，因此同时安装到 $HOME 和 /root
# 支持 --local / -l：安装到脚本所在目录的 .cursor/
# 支持 --project PATH / -p PATH：安装到指定项目目录的 .cursor/（PATH 可为 . 表示当前目录）
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CMD_SRC="$SCRIPT_DIR/commands/ralph-loop.md"

DO_LOCAL=false
DO_GLOBAL=true
PROJECT_DIR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --local|-l) DO_LOCAL=true ;;
    --local-only) DO_LOCAL=true; DO_GLOBAL=false ;;
    --project|-p)
      [ $# -gt 1 ] || { echo "Error: --project requires PATH" >&2; exit 1; }
      PROJECT_DIR="$2"
      shift
      ;;
    --help|-h)
      echo "Usage: $0 [OPTIONS]"
      echo "  (no args)       Install to global Cursor config (~/.cursor, /root/.cursor, etc.)"
      echo "  --local, -l     Also install to script dir .cursor/"
      echo "  --local-only    Install only to script dir .cursor/"
      echo "  --project PATH  Install to PATH/.cursor/ (PATH can be . for cwd); creates/updates hooks.json"
      echo "  -p PATH         Same as --project"
      exit 0
      ;;
  esac
  shift
done
# 本目录下已有 .cursor 时，直接使用（自动安装到本地项目）
[ -d "$SCRIPT_DIR/.cursor" ] && DO_LOCAL=true

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

# 全局安装
if [ "$DO_GLOBAL" = true ]; then
  # 当前用户
  install_with_hook "${CURSOR_HOME:-$HOME/.cursor}"

  # WSL 下 Cursor 往往用 root：仅当当前是 root 时才装到 /root，避免普通用户因无权限失败
  if [ "$(whoami)" = "root" ]; then
    install_with_hook "/root/.cursor"
  fi

  # 若当前是 root 但存在 hardy 用户目录，也装一份到 hardy 的 .cursor，避免 Cursor 以 hardy 打开时看不到命令
  if [ "$(whoami)" = "root" ] && [ -d /home/hardy ] && [ -w /home/hardy ]; then
    install_with_hook "/home/hardy/.cursor"
  fi

  # 若在 WSL，提示 Windows 侧
  if grep -qi microsoft /proc/version 2>/dev/null; then
    echo ""
    echo "If Cursor runs on Windows (not WSL), copy the command to Windows:"
    echo "  To: %USERPROFILE%\\.cursor\\commands\\ralph-loop.md"
  fi
fi

# 本地项目安装：安装到脚本所在目录的 .cursor/
if [ "$DO_LOCAL" = true ]; then
  LOCAL_CURSOR="$SCRIPT_DIR/.cursor"
  install_with_hook "$LOCAL_CURSOR"
  echo ""
  echo "Local project: $LOCAL_CURSOR"
fi

# 指定项目目录安装：安装到 PATH/.cursor/ 并创建/更新 hooks.json
if [ -n "$PROJECT_DIR" ]; then
  PROJECT_CURSOR="$(cd "$PROJECT_DIR" && pwd)/.cursor"
  install_with_hook "$PROJECT_CURSOR"
  echo ""
  echo "Project .cursor: $PROJECT_CURSOR"
fi
