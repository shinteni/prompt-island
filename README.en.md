# Vibelsland Free

<p align="center">
  <img src="docs/assets/readme/app-icon.png" alt="Vibelsland Free app icon" width="128">
</p>

<p align="center">
  <a href="README.md">中文</a> | <a href="README.en.md">English</a> | <a href="README.ja.md">日本語</a>
</p>

<p align="center">
  <strong>A local-first AI coding status island for macOS.</strong>
</p>

<p align="center">
  <a href="https://shinteni.github.io/prompt-island/">Website</a>
  ·
  <a href="https://github.com/shinteni/prompt-island/releases/download/v0.2.1/Vibelsland-Free-0.2.1-macos.zip">Download v0.2.1</a>
  ·
  <a href="https://shinteni.github.io/prompt-island/en/install.html">Install Guide</a>
  ·
  <a href="PRIVACY.md">Privacy</a>
  ·
  <a href="LICENSE">MIT License</a>
</p>

<p align="center">
  <img src="docs/assets/readme/hero-island-light.jpg" alt="Vibelsland Free floating island interface" width="960">
</p>

`macOS 14+` `Claude Code` `Codex CLI` `Codex Desktop` `Local-first` `No telemetry`

Vibelsland Free brings Claude Code, Codex CLI, and Codex Desktop task status, tool activity, token summaries, and approval requests into one island at the top of your screen. It stays quiet when idle and appears automatically when a task is active or needs attention.

## Features

- See running, completed, failed, and approval states at the top of the screen.
- Review task titles, tool activity, AI response summaries, token usage, and recent events.
- Handle allow, reject, continue, and cancel requests directly from the island.
- Use Claude Code, Codex CLI, and Codex Desktop in one unified view.
- Choose English, Japanese, or Chinese, and configure sound, hotkeys, Do Not Disturb, and island position.
- Keep core data on your Mac with no account and no telemetry upload.

## Download And Install

[Download Vibelsland Free v0.2.1](https://github.com/shinteni/prompt-island/releases/download/v0.2.1/Vibelsland-Free-0.2.1-macos.zip), unzip it, and move `>_ - island.app` to the Applications folder.

The current release uses ad-hoc signing. If macOS blocks the first launch, follow the [Install & Trust guide](https://shinteni.github.io/prompt-island/en/install.html).

You can also install it with Homebrew:

```sh
brew tap shinteni/island https://github.com/shinteni/prompt-island.git
brew install --cask shinteni/island/vibelsland-free
```

## How To Use

1. Open `>_ - island.app`. The app stays in the menu bar, and the island appears at the top of the screen when a task starts.
2. Click the `>_` menu bar icon, open Settings, and enable Claude Code, Codex CLI, or Codex Desktop under Sources.
3. For Claude Code or Codex CLI, choose Install Hooks from the menu bar. Codex Desktop does not need a hook; the app reads the current user's local state.
4. Start an AI coding task normally. Click the island to view details and respond when an approval request appears.
5. If Settings reports a connection issue, use Repair Connection under Maintenance and run the check again.

Language, island position, launch at login, sound, Do Not Disturb, and global hotkeys can all be changed in Settings.

## Privacy And License

Vibelsland Free does not create an account, upload telemetry, or sync sessions to a remote server. See [PRIVACY.md](PRIVACY.md) for details.

The project is open source under the [MIT License](LICENSE).

Vibelsland Free is an independent utility and is not affiliated with Anthropic, OpenAI, Claude, or Codex. Product names are used only to describe local compatibility.
