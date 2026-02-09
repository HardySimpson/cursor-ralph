# cursor-ralph

为 Cursor IDE 提供代理式循环：让 AI 持续执行任务直到完成（或达到安全上限）。

本项目是 Claude Code 的 [ralph-wiggum 插件](https://github.com/anthropics/claude-code/tree/main/plugins/ralph-wiggum) 中「Not-quite-Ralph」循环的移植版。通过 stop hook 配合各平台工具，绕过 Cursor 的 5 轮迭代限制。

**English** → [README.md](README.md)

---

## 为什么需要 cursor-ralph？

在 Cursor 里用 Agent 做「大一点」的事时，经常会遇到这种体验：

- **任务还没做完，对话就停了**：比如「把测试覆盖率提到 80%」「修完 src/ 下所有类型错误」，Agent 刚改了几轮，就提示你「可以继续对话」或直接不再自动回复。
- **原因在于 Cursor 的 5 轮限制**：同一对话里，Agent 通过 `followup_message` 连续自动续接的次数被限制为 **5 轮**。第 5 轮之后，链就断了，必须由**用户**再发一条消息才能继续。
- **结果**：你要么守在旁边每隔几轮手动点「继续」或再发一句「继续」，要么任务被半路截断，体验割裂，长任务很难「一次性跑完」。

也就是说：**痛点不是模型能力不够，而是产品层面的轮次上限，导致 Cursor 无法在无人值守的情况下持续工作。**

cursor-ralph 要解决的就是这件事：**让 Cursor 像真正的代理一样，在安全上限内一直跑，直到任务完成或你主动停止。**

---

## cursor-ralph 如何让 Cursor 持续工作？

### 思路：Ralph 循环 + stop hook

1. **Ralph 循环**  
   你只发一次目标（例如「添加测试直到覆盖率达到 80%」），Agent 在**循环**里反复执行：改代码、跑测试、看结果、再改……直到输出约定好的「完成」信号（默认是 `COMPLETE`）或达到你设的最大迭代数。你不需要每 5 轮就过来点一次继续。

2. **用 Cursor 的 stop hook 接上循环**  
   每次 Agent 回复结束后，Cursor 会执行我们配置的 **stop hook**。hook 会：
   - 读当前任务状态（进度、是否完成、是否已达最大轮数）；
   - 若任务已完成或达到安全上限 → 清理并退出；
   - 若当前会话还没到 5 轮 → 通过返回 `followup_message` 让 Cursor **自动再问 Agent 一句**，链继续；
   - 若已经到第 5 轮（Cursor 的硬限制）→ 用各平台方式**往 Cursor 聊天框里自动输入**一条新消息：`/ralph-loop --continue <conversation_id>`，相当于「用户」发了一条续跑指令，新会话重新计数，从而绕过 5 轮上限。

3. **自动续跑（按平台）**  
   - **macOS**：用 `osascript` 把续跑命令输入到 Cursor（需授予辅助功能权限）。  
   - **Linux (X11 / Wayland)**：用 `xdotool` 或 `ydotool` 把输入发到 Cursor 窗口。  
   - **WSL**：用 PowerShell 的 SendKeys 把输入发到 Windows 下的 Cursor 窗口（会先尝试把焦点从终端移到聊天框）。  
   - **Windows 原生**：暂无自动输入，5 轮后需在聊天框**手动**输入 `/ralph-loop --continue <conversation_id>`。

4. **和社区扩展一起用（可选）**  
   Cursor 还有「25 次工具调用后暂停」等限制，和 5 轮限制是两回事。可以**同时**安装 [Cursor Auto Continue](https://marketplace.visualstudio.com/items?itemName=risalabs.cursor-auto-continue) 或 [cursor-auto-resume](https://github.com/thelastbackspace/cursor-auto-resume)，让 5 轮由 ralph-loop 解决、25 工具调用/限流由扩展解决，长任务更少被打断。详见 [与社区扩展一起使用 / 手动续跑](docs/COMMUNITY-EXTENSIONS-AND-MANUAL-CONTINUE.md)。

**总结**：  
- **痛点**：Cursor 的 5 轮 followup_message 限制，导致长任务被强制中断，需要人工反复「继续」。  
- **做法**：用 `/ralph-loop "任务"` 启动一次，由 stop hook 在每轮结束后决定是自动续接（followup_message）还是自动输入续跑命令（越过 5 轮），从而让 Cursor 在设定上限内**持续工作**，直到任务完成或达到最大迭代数。

---

## 安装

**推荐：** 在仓库根目录执行安装脚本。脚本会安装 `/ralph-loop` 命令并配置 stop hook（包括当前用户目录，在 WSL 下通常还会配置 `/root`）：

```bash
git clone https://github.com/youruser/cursor-ralph.git ~/.cursor-ralph
cd ~/.cursor-ralph
./install-commands.sh
```

- **无参数：** 安装到全局 Cursor 配置（`~/.cursor`，在 WSL 下必要时也会安装到 `/root/.cursor`）。
- **`--local` / `-l`：** 同时安装到当前项目（脚本所在目录）的 `.cursor/`。
- **`--local-only`：** 仅安装到当前项目的 `.cursor/`。

**macOS：** 为 Cursor 授予辅助功能权限（系统设置 → 隐私与安全性 → 辅助功能），以便自动续跑。

安装后请完全退出并重新打开 Cursor（或重新加载窗口），以加载命令和 hook。

### 手动安装

若不想用脚本，可手动操作：

1. 将 `commands/ralph-loop.md` 复制到 `~/.cursor/commands/ralph-loop.md`（Linux/macOS）或 `%USERPROFILE%\.cursor\commands\ralph-loop.md`（Windows），没有 `commands` 目录则先创建。
2. 在 `~/.cursor/hooks.json`（或 `~/.cursor/settings.json`）中添加 stop hook：
   ```json
   { "version": 1, "hooks": { "stop": [ { "command": "/path/to/cursor-ralph/hooks/ralph-loop-stop.sh" } ] } }
   ```
3. 在 macOS 上为 Cursor 授予辅助功能权限以启用自动续跑。

## 支持的操作系统

| 系统 / 环境 | 自动续跑 | 说明 |
|-------------|----------|------|
| **macOS** | ✅ `osascript` | 为 Cursor 授予辅助功能权限；达到会话上限时保持 Cursor 在前台。 |
| **Linux (X11)** | ✅ `xdotool` | 安装：`sudo apt install xdotool`（或发行版等价命令）。达到上限时 Cursor 需在前台。 |
| **Linux (Wayland)** | ✅ `ydotool` | 安装：`sudo apt install ydotool`；并运行 `ydotoold`。达到上限时 Cursor 需在前台。 |
| **WSL** | ✅ PowerShell SendKeys | 向 Windows 上的 Cursor 窗口发送输入。脚本若在终端中运行，会先发 Ctrl+` 移出终端，再 Ctrl+L、Escape，并模拟点击窗口底部中央以聚焦聊天输入框，再输入续跑命令。 |
| **Windows（原生）** | ⚠️ 手动 | 无自动输入；5 轮后需手动执行 `/ralph-loop --continue <conversation_id>`。 |

若无法使用自动续跑（或失败），可在 5 轮后手动执行 `/ralph-loop --continue <conversation_id>`。

**与社区扩展一起使用**：可与 [Cursor Auto Continue](https://marketplace.visualstudio.com/items?itemName=risalabs.cursor-auto-continue)、[cursor-auto-resume](https://github.com/thelastbackspace/cursor-auto-resume) 等扩展同时安装，分别应对 **5 轮限制**与 **25 工具调用/限流**，减少长任务中断。Cursor Auto Continue 可从扩展市场安装、在界面中从 VSIX 安装，或**用命令行安装**（依赖：终端可用的 Cursor CLI + 本仓库中的 `cursor-auto-continue-0.1.5.vsix`）：`cursor --install-extension "$(pwd)/cursor-auto-continue-0.1.5.vsix"`。各方式与依赖说明见 [docs/CURSOR-AUTO-CONTINUE-INSTALL.md](docs/CURSOR-AUTO-CONTINUE-INSTALL.md)，自动续跑失败时手动续跑见 [docs/COMMUNITY-EXTENSIONS-AND-MANUAL-CONTINUE.md](docs/COMMUNITY-EXTENSIONS-AND-MANUAL-CONTINUE.md)。

## 什么是 Ralph 循环？

[Ralph Wiggum 技巧](https://ghuntley.com/ralph/) 是一种代理模式：让 AI 在循环中持续工作，直到它声明任务完成。你只需给出目标，无需反复对话。

本实现并非「完整」Ralph 循环（后者有更复杂的状态管理），而是在 Cursor 限制下的实用版本。

## 使用

```
/ralph-loop "你的任务描述"
```

### 选项

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `--max-iterations <n>` | 20 | 安全上限，防止死循环 |
| `--completion-promise "<文本>"` | `COMPLETE` | 任务完成时 agent 输出的精确字符串 |

### 示例

```bash
# 跑测试直到覆盖率达到 80%
/ralph-loop "添加测试直到覆盖率达到 80%" --max-iterations 30

# 修复所有 TypeScript 错误
/ralph-loop "修复 src/ 下所有类型错误" --max-iterations 15

# 自定义完成信号
/ralph-loop "重构 auth 模块" --completion-promise "REFACTOR_DONE"
```

## 工作原理

```
┌─────────────────────────────────────────────────────────────┐
│                     用户：/ralph-loop "任务"                 │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│  Agent 执行任务，并更新状态文件中的进度                      │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│  每次 agent 回复后 stop hook 运行                            │
│  ├─ 检查完成信号 → 完成？清理并退出                          │
│  ├─ 检查最大迭代数 → 达到上限？清理并退出                    │
│  ├─ 当前会话 < 5？→ 返回 followup_message 继续               │
│  └─ 当前会话 = 5？→ 用 osascript 等输入新 /ralph-loop 命令   │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          ▼
                    （循环继续）
```

要点：Cursor 将 `followup_message` 链限制为 5 轮。达到该限制时，stop hook 通过向 Cursor 输入 `/ralph-loop --continue <conversation_id>` 自动续跑（各平台行为见[支持的操作系统](#支持的操作系统)）。

**待处理状态文件：** hook 端有 `CURSOR_CONVERSATION_ID`；agent 在该环境变量存在时应写入 `/tmp/cursor-ralph-pending/${CURSOR_CONVERSATION_ID}.json`，以便 hook 正确认领。否则 agent 使用唯一文件名，hook 按最新修改时间认领（尽力而为；避免多任务并发）。仍支持旧版单文件 `/tmp/cursor-ralph-pending.json`。

## 状态文件

循环状态保存在 `/tmp/cursor-ralph-loop-<conversation_id>.json`（hook 在首次运行时从待处理文件「认领」后）。初始状态由 agent 在 `/tmp/cursor-ralph-pending/` 下创建唯一文件：

```json
{
  "prompt": "原始任务",
  "max_iterations": 20,
  "completion_promise": "COMPLETE",
  "iterations": 7,
  "session_iterations": 2,
  "stop": false,
  "last_output": "已添加 3 个测试文件，覆盖率现为 74%"
}
```

## 依赖

- **jq**（`brew install jq` 或 `sudo apt install jq`）
- **Cursor**
- **自动续跑：** 见[支持的操作系统](#支持的操作系统)中各平台工具与配置。

## 限制

- 达到会话上限时 Cursor 需处于前台，这样输入的指令才会进入聊天框。
- 输入前约 2 秒延迟是为了让 Cursor 界面稳定。

## 故障排除

- **看不到 `/ralph-loop`**  
  在仓库根目录执行 **`./install-commands.sh`**；它会将命令和 hook 安装到正确位置（在 WSL 下会包含 `/root/.cursor`）。Cursor 从当前打开目录的 `.cursor/commands` 和用户配置的 `commands` 目录加载——确保该处有真实文件，然后完全退出并重新打开 Cursor（或重新加载窗口）。

- **命令列表为空**  
  若斜杠命令列表为空，请在 Cursor 设置中启用 Commands（Beta / 功能）。

- **WSL 下命令被输入到终端、或只看到 "bash" 被识别**  
  脚本在终端里跑时焦点在终端，Ctrl+L 在 bash 里是清屏，会被终端吃掉。脚本会先发 **Ctrl+`** 移出终端，再 Ctrl+L、**Escape**，然后**模拟点击 Cursor 窗口底部中央**以把焦点移入聊天输入框，再输入续跑命令。若仍失败，可到第 5 轮时手动在聊天里输入 `/ralph-loop --continue <conversation_id>`。详见 [docs/WSL-CURSOR-FOCUS-INVESTIGATION.md](docs/WSL-CURSOR-FOCUS-INVESTIGATION.md)。

- **想同时绕过 25 工具调用限制，或自动续跑失败时如何手动续跑**  
  见 [docs/COMMUNITY-EXTENSIONS-AND-MANUAL-CONTINUE.md](docs/COMMUNITY-EXTENSIONS-AND-MANUAL-CONTINUE.md)。若要用命令行（含 headless）安装 Cursor Auto Continue，见 [docs/CURSOR-AUTO-CONTINUE-INSTALL.md](docs/CURSOR-AUTO-CONTINUE-INSTALL.md)（依赖：Cursor CLI + `cursor-auto-continue-0.1.5.vsix`）。

## 致谢

- Ralph Wiggum 技巧原作者 [Geoffrey Huntley](https://ghuntley.com/ralph/)
- 基于 Claude Code 的 [ralph-wiggum 插件](https://github.com/anthropics/claude-code/tree/main/plugins/ralph-wiggum)
- 本移植由 Jordan Baker 完成

## 许可证

MIT
