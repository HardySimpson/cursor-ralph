# Cursor Auto Continue 安装说明

[Cursor Auto Continue](https://marketplace.visualstudio.com/items?itemName=risalabs.cursor-auto-continue) 在 Claude 触发「25 次 tool calls 后停止」时，自动在聊天框输入「continue」并发送，可与 ralph-loop 一起使用以同时应对 5 轮限制与 25 工具调用限制。

---

## 依赖说明

| 安装方式 | 依赖 |
|----------|------|
| **方法一**（扩展市场） | 已安装的 Cursor；扩展在 Cursor 市场可用。 |
| **方法二**（从 VSIX 在 Cursor 内安装） | 已安装的 Cursor；本仓库中的 **`cursor-auto-continue-0.1.5.vsix`**（或自行从 [GitHub](https://github.com/risa-labs-inc/cursor-auto-continue) 打包的 VSIX）。 |
| **方法三**（命令行 / headless） | **Cursor CLI** 在终端可用（安装 Cursor 后通常已加入 PATH；可用 `cursor --version` 校验）；**VSIX 文件**（本仓库根目录的 **`cursor-auto-continue-0.1.5.vsix`** 或任意有效路径）。无需图形界面，适合脚本与 CI。 |

---

## 方法一：在 Cursor 内从扩展市场安装（推荐）

1. 按 **Ctrl+Shift+X**（macOS：**Cmd+Shift+X**）打开扩展视图
2. 搜索 **Auto Continue** 或 **Cursor Auto Continue**
3. 找到 **Cursor Auto Continue**（发布者：Risa Labs），点击 **安装**

若 Cursor 使用自己的扩展市场且未上架该扩展，请用方法二。

---

## 方法二：从 VSIX 安装

本仓库已包含打包好的 VSIX，可直接安装：

1. **VSIX 文件位置**（任选其一）：
   - 项目根目录：**`cursor-auto-continue-0.1.5.vsix`**
   - WSL 下从 Windows 访问：`\\wsl$\Ubuntu\home\hardy\workspace\tmp\cursor-ralph\cursor-auto-continue-0.1.5.vsix`（路径按你的 WSL 发行版与用户名调整）
2. 在 Cursor 中：
   - 打开扩展视图（**Ctrl+Shift+X** / **Cmd+Shift+X**）
   - 点击扩展列表右上角 **「…」**
   - 选择 **「从 VSIX 安装…」**
   - 选择上述 `.vsix` 文件（若在 WSL，可在文件选择器中输入 `\\wsl$\` 访问 WSL 路径）

若需自行打包，可克隆 [cursor-auto-continue](https://github.com/risa-labs-inc/cursor-auto-continue) 后执行 `npm install && npm run package`。

---

## 方法三：命令行（headless）安装

**依赖**：终端中可用的 **Cursor CLI**（`cursor --version` 能执行即可）、以及 **VSIX 文件**（本仓库根目录的 `cursor-auto-continue-0.1.5.vsix` 或你本地的路径）。无需打开 Cursor 图形界面，适合脚本、自动化与 headless 环境。

在终端执行（将路径改为你的 VSIX 实际路径）：

```bash
cursor --install-extension /path/to/cursor-auto-continue-0.1.5.vsix
```

**本仓库内**（在项目根目录下，直接使用自带 VSIX）：

```bash
cursor --install-extension "$(pwd)/cursor-auto-continue-0.1.5.vsix"
```

说明：

- **WSL**：若 `cursor` 指向 Windows 版 Cursor，上述命令会安装到当前 WSL 的扩展目录（输出会显示 "Installing extensions on WSL: ubuntu..."）。
- 用扩展 ID 安装（`cursor --install-extension risalabs.cursor-auto-continue`）在 Cursor 市场可能不可用，**必须使用 VSIX 文件路径**。

---

## 配置与使用

- **状态栏**：显示 **AUTO**；绿色表示已启用，红色表示已关闭；点击可开关
- **设置**：**文件 → 首选项 → 设置**，搜索 **Auto Continue**
  - `autoContinue.enabled`：是否启用
  - `autoContinue.waitTimeMs`：自动继续前的等待时间（毫秒）

安装后无需额外操作，扩展会在检测到 25 次工具调用限制时自动继续对话。

---

## 参考

- [VS Code Marketplace - Cursor Auto Continue](https://marketplace.visualstudio.com/items?itemName=risalabs.cursor-auto-continue)
- [GitHub - risa-labs-inc/cursor-auto-continue](https://github.com/risa-labs-inc/cursor-auto-continue)
