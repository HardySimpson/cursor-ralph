# 与社区扩展一起使用 / 手动续跑

本文说明如何**同时越过 Cursor 的两种限制**，以及在自动续跑失败时如何**手动续跑**。

---

## 1. 加法：扩展 + ralph-loop 同时使用

Cursor 里有两类常见限制：

| 限制 | 表现 | 谁来解决 |
|------|------|----------|
| **5 轮 followup_message** | 同一对话内 Agent 连续 5 次回复后不能再自动续接 | **ralph-loop**（stop hook 输入 `/ralph-loop --continue <id>`） |
| **25 次工具调用 / 限流** | 出现「Note: By default, we stop the agent after 25 tool calls. You can resume the conversation.」或连接/限流错误 | **社区扩展**（自动点「resume」或输入「continue」并发送） |

这两类限制互不重叠。**可以同时安装 ralph-loop 与下列扩展**，分别应对 5 轮限制与 25 工具调用/限流，从而在长任务中减少中断：

- **[Cursor Auto Continue](https://marketplace.visualstudio.com/items?itemName=risalabs.cursor-auto-continue)**（VS Code 扩展）：检测到 25 工具调用限制时自动在聊天框输入「continue」并发送。
- **[cursor-auto-resume](https://github.com/thelastbackspace/cursor-auto-resume)**：通过 Custom CSS and JS Loader 注入脚本，自动点击「resume the conversation」链接；也处理部分连接/限流错误。

安装方式请见各项目说明。与 ralph-loop 无冲突，可一起使用。

---

## 2. 手动续跑（自动续跑失败时）

当**第 5 轮**触达、但自动续跑未生效时（例如 WSL 下焦点在终端、命令被输入到错误位置），可以**手动在聊天框输入**续跑命令：

```
/ralph-loop --continue <conversation_id>
```

其中 `<conversation_id>` 会在 hook 给出的提示里出现，例如：

> Session limit (5) reached. To continue, run: **/ralph-loop --continue abc-123-xyz** (iteration 5 of 20)

把其中的 `abc-123-xyz` 换成当前对话实际显示的 conversation_id，在聊天输入框输入整行后回车即可继续循环。

- **WSL**：若经常遇到自动续跑失败，可优先采用手动续跑，或参考 [WSL-CURSOR-FOCUS-INVESTIGATION.md](WSL-CURSOR-FOCUS-INVESTIGATION.md) 尝试改进焦点与输入方式。
- **Windows（原生）**：当前无自动输入，5 轮后需手动执行上述命令。

---

## 小结

- **要同时越过 5 轮 + 25 工具调用/限流**：安装 ralph-loop 后，再安装 Cursor Auto Continue 或 cursor-auto-resume（加法）。
- **自动续跑失败时**：在聊天框手动输入 `/ralph-loop --continue <conversation_id>` 即可续跑。

---

## English

### 1. Using extensions alongside ralph-loop (additive)

Cursor has two separate limits:

| Limit | What happens | Handled by |
|-------|----------------|------------|
| **5-round followup_message** | After 5 agent replies in a row, the chain stops | **ralph-loop** (stop hook types `/ralph-loop --continue <id>`) |
| **25 tool calls / rate limit** | "Note: By default, we stop the agent after 25 tool calls. You can resume the conversation." or connection errors | **Community extensions** (auto-click resume or type "continue") |

You can **install ralph-loop and one of these extensions together** to address both:

- **[Cursor Auto Continue](https://marketplace.visualstudio.com/items?itemName=risalabs.cursor-auto-continue)**: VS Code extension that types "continue" and submits when the 25 tool-call limit is hit.
- **[cursor-auto-resume](https://github.com/thelastbackspace/cursor-auto-resume)**: Injected script that clicks the "resume the conversation" link and handles some connection/rate-limit UI.

### 2. Manual continue when auto-continue fails

When you hit the **5th round** but the continue command was not typed into the chat (e.g. on WSL it went to the terminal), run this **manually in the chat input**:

```
/ralph-loop --continue <conversation_id>
```

Use the `<conversation_id>` from the hook’s message (e.g. "To continue, run: /ralph-loop --continue abc-123-xyz"). On native Windows, manual continue is required after every 5 rounds.
