# Cursor Auto Resume 安装说明

[cursor-auto-resume](https://github.com/thelastbackspace/cursor-auto-resume) 会在 Cursor 触发「25 次 tool calls 后停止」时，自动点击「resume the conversation」链接。

仓库已克隆到：**`/home/hardy/cursor-auto-resume`**（以及 `/root/cursor-auto-resume`）。

---

## 方式一：一次性使用（推荐先试）

1. 在 Cursor 中：**Help（帮助）** → **Toggle Developer Tools（切换开发者工具）**
2. 打开 **Console（控制台）** 标签
3. 打开脚本文件，复制全部内容：
   - 路径：`/home/hardy/cursor-auto-resume/cursor-auto-resume.js`
   - 或：`/root/cursor-auto-resume/cursor-auto-resume.js`
4. 粘贴到控制台，按 **Enter** 执行
5. 可选：关闭 DevTools；右下角会出现小按钮表示脚本已运行

**说明**：关闭 Cursor 或刷新窗口后失效，需要重新执行上述步骤。

---

## 方式二：永久安装（每次启动自动加载）

1. **安装扩展**：在 Cursor 中安装 [Custom CSS and JS Loader](https://marketplace.visualstudio.com/items?itemName=be5invis.vscode-custom-css)
2. **确认脚本路径**：确保目录存在且可读  
   - Linux/WSL：`/home/hardy/cursor-auto-resume/cursor-auto-resume.js`  
   - 若 Cursor 在 Windows 下运行，需用 Windows 可访问的路径（如 `C:\Users\你的用户名\cursor-auto-resume\cursor-auto-resume.js`），并先在 Windows 下克隆该仓库
3. **修改 Cursor 的 settings.json**：
   - 打开命令面板：`Ctrl+Shift+P`（或 `Cmd+Shift+P`）
   - 输入并选择：**Preferences: Open User Settings (JSON)**
   - 在 JSON 中加入（注意路径按你的环境改）：

   ```json
   "vscode_custom_css.imports": [
       "file:///home/hardy/cursor-auto-resume/cursor-auto-resume.js"
   ]
   ```

   - 若 Cursor 在 **Windows** 上运行，例如：
   ```json
   "vscode_custom_css.imports": [
       "file:///C:/Users/你的用户名/cursor-auto-resume/cursor-auto-resume.js"
   ]
   ```

4. **重启 Cursor**（若扩展要求「以允许修改自身」方式启动，按提示操作）
5. 执行命令：**Reload Custom CSS and JS**
6. 再执行：**Reload Window**（或重新加载窗口）

**注意**：每次升级 Cursor 后，通常需要重新执行步骤 5 和 6。

---

## 常用操作

- **重置 30 分钟计时**：在开发者工具 Console 里输入 `click_reset()` 回车
- **停止脚本**：关闭/重开 Cursor 或刷新窗口；或等待 30 分钟自动停止

---

## 参考

- 项目：[thelastbackspace/cursor-auto-resume](https://github.com/thelastbackspace/cursor-auto-resume)
- 本地脚本：`/home/hardy/cursor-auto-resume/cursor-auto-resume.js`
