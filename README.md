# Vibelsland Free

<p align="center">
  <img src="docs/assets/readme/app-icon.png" alt="Vibelsland Free app icon" width="128">
</p>

<p align="center">
  <a href="README.md">中文</a> | <a href="README.en.md">English</a> | <a href="README.ja.md">日本語</a>
</p>

<p align="center">
  <strong>面向 macOS 的本地优先 AI coding 状态显示。</strong>
</p>

<p align="center">
  <a href="https://shinteni.github.io/prompt-island/">官网</a>
  ·
  <a href="https://github.com/shinteni/prompt-island/releases/download/v0.1.0/Vibelsland-Free-0.1.0-macos.zip">下载 v0.1.0</a>
  ·
  <a href="https://shinteni.github.io/prompt-island/install.html">安装与信任</a>
  ·
  <a href="PRIVACY.md">隐私说明</a>
  ·
  <a href="#从源码构建">从源码构建</a>
</p>

<p align="center">
  <img src="docs/assets/readme/hero-island-light.jpg" alt="Vibelsland Free floating island interface" width="960">
</p>

`macOS 14+` `Swift` `Local-first` `No telemetry` `Claude Code` `Codex CLI` `Codex Desktop`

## 一眼看清 AI 编程现场

Vibelsland Free 是给重度 AI 编程用户的 macOS 原生工具。它把 Claude Code、Codex CLI 和 Codex Desktop 的本机会话状态、工具调用、token 摘要和审批请求集中到屏幕顶部的浮岛里。

它在你工作时把最重要的 AI 编程状态留在视线范围内。空闲时安静收起，任务进行时变成紧凑药丸，遇到审批或重要状态时展开为面板。

## 产品亮点

- **顶部浮岛**：无任务时隐藏、任务中显示紧凑药丸、需要处理时展开面板，适合常驻屏幕顶部。
- **RGB 光环状态感**：边缘动态光环是核心视觉识别，让运行、完成、失败和审批状态更容易感知。
- **多工具统一视图**：同时覆盖 Claude Code、Codex CLI 和 Codex Desktop，减少反复切换窗口。
- **会话进度摘要**：展示任务标题、工具调用、AI 回复摘要、token 用量和最近活动。
- **审批集中处理**：在浮岛中处理允许、拒绝、继续、取消等审批动作。
- **健康检查中心**：在设置页查看 Bridge、Hooks、Codex Desktop 连接、日志和本机运行状态。
- **本地优先**：不需要账号，不上传遥测，不依赖云端同步，核心功能都在本机完成。

## 适合谁

- 经常同时使用 Claude Code、Codex CLI 或 Codex Desktop 的开发者。
- 希望不切窗口就能看见 AI 编程状态的人。
- 想把审批请求、工具调用和会话进度放到一个可见位置的人。
- 偏好本地工具、低干扰 UI 和 macOS 原生体验的人。

## 技术架构

Vibelsland Free 是一个 Swift Package 组织的 macOS 原生应用，界面层使用 SwiftUI 与 AppKit 组合实现菜单栏、浮岛面板和设置窗口。核心逻辑集中在 `Sources/VibelslandFreeCore`，把会话解析、审批映射、去重、展示策略、重启恢复和健康检查拆成可测试的策略模块。

本地数据流是：Claude Code / Codex CLI Hooks 与 Codex Desktop 本机状态进入 Bridge 和读取器，统一转换为 `AgentEvent` / `AgentSession`，再由 `SessionStore` 驱动顶部浮岛显示。运行时通信只使用本机文件、Unix socket 和本地配置，不需要账号或远程服务。

## 验证策略

仓库包含 Swift 单元测试、发布打包脚本、文档站校验和多组 macOS 窗口自动化验证。常用入口是 `zsh scripts/run-tests.sh`、`zsh scripts/verify-docs-site.sh` 和 `zsh scripts/verify-release-readiness.sh`。GitHub Actions 会在源码、测试或包配置变更时执行 Swift 构建和测试；本地只有 CommandLineTools 时，`scripts/run-tests.sh` 会明确降级为测试目标编译/发现检查。文档变更会触发 GitHub Pages 部署与线上校验。

## 下载与安装

v0.1.0 可从 GitHub Releases 下载。当前发布包使用 ad-hoc 签名，首次打开前请阅读安装与信任说明：

[Download v0.1.0](https://github.com/shinteni/prompt-island/releases/download/v0.1.0/Vibelsland-Free-0.1.0-macos.zip)

[安装与信任说明](https://shinteni.github.io/prompt-island/install.html)

校验下载包：

```sh
curl -LO https://github.com/shinteni/prompt-island/releases/download/v0.1.0/Vibelsland-Free-0.1.0-macos.zip
curl -LO https://github.com/shinteni/prompt-island/releases/download/v0.1.0/Vibelsland-Free-0.1.0-macos.zip.sha256
shasum -a 256 -c Vibelsland-Free-0.1.0-macos.zip.sha256
```

当前 SHA-256：

```text
64c7c0a4eae81042bbc3896e24a07ab5d5573aeaafa846eada2e982f887ecf81
```

安装方式：

1. 下载 `Vibelsland-Free-0.1.0-macos.zip`。
2. 解压后将 `>_ - island.app` 拖到 `Applications`。
3. 打开应用，在菜单栏或设置页安装 Hooks。
4. 按需开启自动启动、声音、勿扰和显示位置。

说明：当前免费发布包使用 ad-hoc codesign，首次打开需要按 Gatekeeper 说明手动确认。Developer ID 签名和 notarization 可以作为后续降低首次打开摩擦的分发改进，但当前 v0.1.0 下载、校验、源码和安装说明已经公开。

## 隐私

Vibelsland Free 是本机工具，不创建账号，不上传遥测，不同步远程服务器。它只读取 Claude Code、Codex CLI 和 Codex Desktop 在本机留下的状态、会话和审批信息，用于展示浮岛状态。

更多细节见 [PRIVACY.md](PRIVACY.md)。

## 从源码构建

```sh
swift build
zsh scripts/run-tests.sh
zsh scripts/package-release.sh
```

`scripts/package-release.sh` 会读取 [docs/release.json](docs/release.json) 里的包名和应用身份来生成本地 zip 与 `.sha256` 文件。若本地重新打包后的 hash 与 `docs/release.json` 不一致，脚本会把它标记为未发布候选包；不要只改官网 hash，必须同时上传匹配的 GitHub Release 资产并同步元数据。检查现有本地 `dist/` 与公开发布一致性时使用：

```sh
VIBELSLAND_VERIFY_DIST=1 zsh scripts/verify-docs-site.sh
VIBELSLAND_VERIFY_DIST=1 zsh scripts/verify-docs-live.sh
```

维护者发布、正式域名构建和 release gate 细节见 [MAINTAINER_RELEASE_CHECKLIST.md](MAINTAINER_RELEASE_CHECKLIST.md)。

说明：仓库最初使用 `prompt-island` 作为代码仓库名，当前产品名是 Vibelsland Free，应用包名显示为 `>_ - island.app`。

## 项目状态

Vibelsland Free v0.1.0 已经具备可下载的本机版本，包含浮岛展示、设置页、Hook 安装、审批窗口、运行状态检查、单实例保护、重启恢复和发布打包脚本。当前免费发布包使用 ad-hoc 签名，并提供公开下载、SHA-256 校验、源码、安装说明和支持入口。

## 许可证

Vibelsland Free 使用 [MIT License](LICENSE) 开源。

## 独立声明

Vibelsland Free 是独立工具，不隶属于 Anthropic、OpenAI、Claude 或 Codex。相关产品名仅用于说明本地兼容性。
