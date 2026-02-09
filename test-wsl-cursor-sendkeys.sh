#!/usr/bin/env bash
# 独立测试：WSL 下通过 PowerShell SendKeys 激活 Cursor 并输入续跑命令
# 用法: ./test-wsl-cursor-sendkeys.sh [conversation_id]
# 不传 conversation_id 时用 test-conv-123，仅验证能否正常激活并输入。
#
# 流程：Ctrl+` 移出终端 → Ctrl+L 打开聊天 → Escape → 模拟点击窗口底部中央（聚焦聊天输入框）
#       → Ctrl+A → SendChar('/') → 粘贴 "ralph-loop --continue id" → 回车。参见 docs/WSL-CURSOR-FOCUS-INVESTIGATION.md

set -e

CONVERSATION_ID="${1:-test-conv-123}"
echo "=== WSL → Cursor SendKeys 测试 ==="
echo "conversation_id: $CONVERSATION_ID"
echo ""

if ! grep -qi microsoft /proc/version 2>/dev/null; then
  echo "错误: 未检测到 WSL（/proc/version 中无 microsoft）。本脚本仅在 WSL 下用于测试 Windows Cursor。"
  exit 1
fi

PS_EXE=""
for p in powershell.exe /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe /mnt/c/Windows/SysWOW64/WindowsPowerShell/v1.0/powershell.exe; do
  if command -v "$p" &>/dev/null || [ -x "$p" ] 2>/dev/null; then
    PS_EXE="$p"
    break
  fi
done

if [ -z "$PS_EXE" ]; then
  echo "错误: 未找到 PowerShell。请确保 Windows 已安装 PowerShell 且 WSL 能调用 powershell.exe。"
  exit 1
fi

echo "使用 PowerShell: $PS_EXE"
WIN_TEMP="${WIN_TEMP:-/mnt/c/Windows/Temp}"
CMD_FILE="$WIN_TEMP/ralph-paste-cmd.txt"
printf '%s' "ralph-loop --continue $CONVERSATION_ID" > "$CMD_FILE" || { echo "错误: 无法写入 $WIN_TEMP（可设置 WIN_TEMP）"; exit 1; }
WIN_CMD="$(wslpath -w "$CMD_FILE" 2>/dev/null || echo "C:\\Windows\\Temp\\ralph-paste-cmd.txt")"
CURSOR_INPUT_CLICK_OFFSET="${CURSOR_INPUT_CLICK_OFFSET:-80}"

echo "约 2 秒后将：1) 激活 Cursor  2) Ctrl+\` 移出终端  3) Ctrl+L  4) Escape  5) 点击窗口底部中央聚焦输入框  6) Ctrl+A 发送 '/' 粘贴 回车"
echo "请确保 Cursor 窗口存在且 2 秒内可被切换到前台。"
echo ""

sleep 2
echo "执行中..."
"$PS_EXE" -NoProfile -Command "
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
[WindowClick]::ClickForegroundBottomCenter($CURSOR_INPUT_CLICK_OFFSET)
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
" 2>/dev/null || true

echo ""
echo "已执行。请到 Cursor 聊天框确认是否出现 /ralph-loop --continue ... 并已回车。"
