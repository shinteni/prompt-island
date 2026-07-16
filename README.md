# Vibelsland Free

<p align="center">
  <img src="docs/assets/readme/app-icon.png" alt="Vibelsland Free app icon" width="128">
</p>

<p align="center">
  <a href="README.md">中文</a> | <a href="README.en.md">English</a> | <a href="README.ja.md">日本語</a>
</p>

<p align="center">
  <strong>面向 macOS 的本地优先 AI 编程状态浮岛。</strong>
</p>

<p align="center">
  <a href="https://shinteni.github.io/prompt-island/">官网</a>
  ·
  <a href="https://github.com/shinteni/prompt-island/releases/download/v0.2.1/Vibelsland-Free-0.2.1-macos.zip">下载 v0.2.1</a>
  ·
  <a href="https://shinteni.github.io/prompt-island/install.html">安装说明</a>
  ·
  <a href="PRIVACY.md">隐私</a>
  ·
  <a href="LICENSE">MIT License</a>
</p>

<p align="center">
  <img src="docs/assets/readme/hero-island-light.jpg" alt="Vibelsland Free floating island interface" width="960">
</p>

`macOS 14+` `Claude Code` `Codex CLI` `Codex Desktop` `本地优先` `无遥测`

Vibelsland Free 把 Claude Code、Codex CLI 和 Codex Desktop 的任务状态、工具调用、token 摘要与审批请求集中显示在屏幕顶部。空闲时浮岛会安静收起，任务运行或需要处理时自动出现。

## 主要功能

- 在屏幕顶部显示 AI 编程任务的运行、完成、失败和审批状态。
- 集中查看任务标题、工具调用、AI 回复摘要、token 用量和最近活动。
- 直接在浮岛中处理允许、拒绝、继续或取消等审批操作。
- 同时支持 Claude Code、Codex CLI 和 Codex Desktop。
- 提供中文、英文和日文界面，以及声音、快捷键、勿扰和显示位置设置。
- 所有核心数据都留在本机，不需要账号，也不上传遥测。

## 下载与安装

[下载 Vibelsland Free v0.2.1](https://github.com/shinteni/prompt-island/releases/download/v0.2.1/Vibelsland-Free-0.2.1-macos.zip)，解压后将 `>_ - island.app` 移到“应用程序”文件夹。

当前版本使用 ad-hoc 签名。首次打开时如被 macOS 阻止，请按照[安装与信任说明](https://shinteni.github.io/prompt-island/install.html)操作。

也可以使用 Homebrew 安装：

```sh
brew tap shinteni/island https://github.com/shinteni/prompt-island.git
brew install --cask shinteni/island/vibelsland-free
```

## 使用方式

1. 打开 `>_ - island.app`。应用会常驻菜单栏，任务开始后浮岛会出现在屏幕顶部。
2. 点击菜单栏中的 `>_` 图标，打开“设置”，在“接收来源”中启用需要使用的 Claude Code、Codex CLI 或 Codex Desktop。
3. 使用 Claude Code 或 Codex CLI 时，从菜单栏选择“安装 Hooks”。Codex Desktop 不需要安装 Hook，应用会读取当前用户的本机状态。
4. 正常开始 AI 编程任务。点击浮岛可查看详细进度，并在出现审批请求时直接处理。
5. 如果设置页提示连接异常，在“维护”中点击“修复接入”，然后重新检测。

语言、浮岛位置、登录时启动、声音、勿扰模式和全局快捷键都可以在设置页调整。

## 隐私与许可

Vibelsland Free 不创建账号、不上传遥测，也不把会话同步到远程服务器。详细说明见 [PRIVACY.md](PRIVACY.md)。

项目以 [MIT License](LICENSE) 开源。

Vibelsland Free 是独立工具，不隶属于 Anthropic、OpenAI、Claude 或 Codex。相关产品名仅用于说明本地兼容性。
