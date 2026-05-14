# Vibelsland Free

**Local AI coding island for macOS.**

**面向 macOS 的本地 AI 编程浮岛。**

Vibelsland Free brings Claude Code, Codex CLI, and Codex Desktop activity into one calm floating island. It stays out of the way when nothing is happening, then expands when a task, tool call, session update, or approval request needs attention.

Vibelsland Free 将 Claude Code、Codex CLI 和 Codex Desktop 的活动集中到一个轻盈的 macOS 浮岛里。空闲时它安静收起，任务进行时展示状态，遇到审批请求时主动展开。

[中文](#中文) | [English](#english)

`macOS 14+` `Swift` `Local-first` `No telemetry` `Claude Code` `Codex CLI` `Codex Desktop`

## 中文

### 一眼看清 AI 编程现场

Vibelsland Free 是给重度 AI 编程用户的 macOS 原生工具。它把分散在终端、Codex Desktop 和本地会话文件里的状态整理成一个顶部浮岛，让你不用反复切窗口，也能知道 AI 现在在做什么、用了什么工具、是否需要你批准。

### 产品亮点

- **顶部浮岛**：空闲时是小圆点，任务中是紧凑药丸，点击后展开为会话面板。
- **RGB 光环状态感**：浮岛边缘保留动态 RGB 光效，让运行、完成、失败和审批状态一眼可辨。
- **多工具统一视图**：同时支持 Claude Code、Codex CLI 和 Codex Desktop，减少多窗口来回确认。
- **会话进度摘要**：展示当前任务标题、工具调用、AI 回复摘要、token 用量和最近活动。
- **审批集中处理**：把 Claude / Codex 的允许、拒绝、取消等审批动作集中在浮岛里完成。
- **健康检查中心**：在设置页查看 Bridge、Hooks、Codex Desktop 连接和本机运行状态。
- **本地优先**：不需要账号，不上传遥测，不依赖云端服务，核心功能都在本机完成。

### 适合谁

- 经常同时使用 Claude Code、Codex CLI 或 Codex Desktop 的开发者。
- 希望不切窗口就能看见 AI 编程状态的人。
- 想把审批请求、工具调用和会话进度放到一个可见位置的人。
- 偏好本地工具、低干扰 UI 和 macOS 原生体验的人。

### 下载与安装

最新版本可以在 GitHub Releases 下载：

[Download latest release](https://github.com/shinteni/vibelsland-free/releases/latest)

安装方式：

1. 下载 `Vibelsland-Free-0.1.0-macos.zip`。
2. 解压后将 `Vibelsland Free.app` 拖到 `Applications`。
3. 打开应用，在菜单栏或设置页安装 Hooks。
4. 按需开启自动启动、声音、勿扰和显示位置。

说明：当前本地构建使用 ad-hoc codesign。面向更大范围分发时，建议使用 Developer ID 签名和 notarization，以获得更顺滑的首次打开体验。

### 隐私承诺

Vibelsland Free 是本机工具，不创建账号，不上传遥测，不同步远程服务器。它只读取 Claude Code、Codex CLI 和 Codex Desktop 在本机留下的状态、会话和审批信息，用于展示浮岛状态。

更多细节见 [PRIVACY.md](./PRIVACY.md)。

### 从源码构建

```sh
swift build
swift test
zsh scripts/package-release.sh
```

本地打包产物会生成在：

```text
dist/Vibelsland Free.app
dist/Vibelsland-Free-0.1.0-macos.zip
dist/Vibelsland-Free-0.1.0-macos.zip.sha256
```

### 项目状态

Vibelsland Free 已经具备可运行的本机版本，包含浮岛展示、设置页、Hook 安装、审批窗口、运行状态检查、单实例保护、重启恢复和发布打包脚本。公开分发前仍建议完成真实设备回归、正式签名和 notarization。

## English

### See your AI coding work at a glance

Vibelsland Free is a native macOS utility for developers who work with AI coding tools every day. It turns scattered terminal sessions, Codex Desktop activity, local transcripts, and approval requests into one compact floating island at the top of your screen.

### Highlights

- **Floating island UI**: idle dot, compact task pill, and expandable session panel.
- **RGB status glow**: a clear edge light that makes running, completed, failed, and approval states feel alive.
- **Unified AI coding view**: supports Claude Code, Codex CLI, and Codex Desktop in one place.
- **Session summaries**: shows task titles, tool activity, AI response snippets, token usage, and recent updates.
- **Approval center**: respond to allow, reject, continue, or cancel requests without hunting through windows.
- **Health dashboard**: check Bridge, Hooks, Codex Desktop connectivity, logs, and local runtime state from settings.
- **Local-first privacy**: no account, no telemetry upload, no cloud sync, and no remote service required for core features.

### Who it is for

- Developers who run Claude Code, Codex CLI, or Codex Desktop during daily work.
- People who want AI task status visible without switching windows.
- Users who want approvals, tool calls, and session progress in a single macOS-native surface.
- Anyone who prefers quiet, local, low-friction tools.

### Download and install

Download the latest build from GitHub Releases:

[Download latest release](https://github.com/shinteni/vibelsland-free/releases/latest)

Install:

1. Download `Vibelsland-Free-0.1.0-macos.zip`.
2. Unzip it and move `Vibelsland Free.app` to `Applications`.
3. Open the app and install Hooks from the menu bar or settings window.
4. Configure launch at login, sound, Do Not Disturb, and display position as needed.

Note: current local builds use ad-hoc codesign. For broader public distribution, Developer ID signing and notarization are recommended for the smoothest first-run experience.

### Privacy

Vibelsland Free is local-first. It does not create an account, upload telemetry, or sync data to a remote server. It reads local Claude Code, Codex CLI, and Codex Desktop state only to display session status, tool activity, token summaries, and approval requests.

Read the full privacy note in [PRIVACY.md](./PRIVACY.md).

### Build from source

```sh
swift build
swift test
zsh scripts/package-release.sh
```

Local release artifacts are generated at:

```text
dist/Vibelsland Free.app
dist/Vibelsland-Free-0.1.0-macos.zip
dist/Vibelsland-Free-0.1.0-macos.zip.sha256
```

### Project status

Vibelsland Free already includes the core local app experience: floating island UI, settings, hook installation, approval UI, runtime health checks, single-instance protection, restart recovery, and release packaging scripts. Before broad public distribution, real-device regression testing, Developer ID signing, and notarization are still recommended.

## Independence

Vibelsland Free is an independent utility. It is not affiliated with Anthropic, OpenAI, Claude, or Codex. Product names are used only to describe local compatibility.
