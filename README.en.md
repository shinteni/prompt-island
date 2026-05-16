# Vibelsland Free

<p align="center">
  <img src="docs/assets/readme/app-icon.png" alt="Vibelsland Free app icon" width="128">
</p>

<p align="center">
  <a href="README.md">中文</a> | <a href="README.en.md">English</a>
</p>

<p align="center">
  <strong>A local-first AI coding status display for macOS.</strong>
</p>

<p align="center">
  <a href="https://shinteni.github.io/prompt-island/">Website</a>
  ·
  <a href="https://github.com/shinteni/prompt-island/releases/download/v0.1.0/Vibelsland-Free-0.1.0-macos.zip">Download v0.1.0</a>
  ·
  <a href="https://shinteni.github.io/prompt-island/en/install.html">Install &amp; Trust</a>
  ·
  <a href="PRIVACY.md">Privacy</a>
  ·
  <a href="#build-from-source">Build from source</a>
</p>

<p align="center">
  <img src="docs/assets/readme/hero-island-light.jpg" alt="Vibelsland Free floating island interface" width="960">
</p>

`macOS 14+` `Swift` `Local-first` `No telemetry` `Claude Code` `Codex CLI` `Codex Desktop`

## See AI Coding Work At A Glance

Vibelsland Free is a native macOS utility for developers who work with AI coding tools every day. It brings local Claude Code, Codex CLI, and Codex Desktop session status, tool activity, token summaries, and approval requests into one floating island at the top of your screen.

It keeps the most important AI coding state visible while you work. When idle, it stays quiet. During a task, it becomes a compact pill. When an approval request or important update needs attention, it expands into a panel.

## Highlights

- **Floating island UI**: idle dot, compact task pill, and expandable session panel.
- **RGB status glow**: the edge glow is the core visual signature for running, completed, failed, and approval states.
- **Unified AI coding view**: supports Claude Code, Codex CLI, and Codex Desktop in one place.
- **Session summaries**: shows task titles, tool activity, AI response snippets, token usage, and recent updates.
- **Approval center**: respond to allow, reject, continue, or cancel requests from the island.
- **Health dashboard**: check Bridge, Hooks, Codex Desktop connectivity, logs, and local runtime state from settings.
- **Local-first privacy**: no account, no telemetry upload, no cloud sync, and no remote service required for core features.

## Who It Is For

- Developers who run Claude Code, Codex CLI, or Codex Desktop during daily work.
- People who want AI task status visible without switching windows.
- Users who want approvals, tool calls, and session progress in a single macOS-native surface.
- Anyone who prefers quiet, local, low-friction tools.

## Download And Install

Download v0.1.0 from GitHub Releases. This release uses ad-hoc signing, so read the install and trust notes before first launch:

[Download v0.1.0](https://github.com/shinteni/prompt-island/releases/download/v0.1.0/Vibelsland-Free-0.1.0-macos.zip)

[Install & Trust](https://shinteni.github.io/prompt-island/en/install.html)

Verify the download:

```sh
curl -LO https://github.com/shinteni/prompt-island/releases/download/v0.1.0/Vibelsland-Free-0.1.0-macos.zip
curl -LO https://github.com/shinteni/prompt-island/releases/download/v0.1.0/Vibelsland-Free-0.1.0-macos.zip.sha256
shasum -a 256 -c Vibelsland-Free-0.1.0-macos.zip.sha256
```

Current SHA-256:

```text
64c7c0a4eae81042bbc3896e24a07ab5d5573aeaafa846eada2e982f887ecf81
```

Install:

1. Download `Vibelsland-Free-0.1.0-macos.zip`.
2. Unzip it and move `>_ - island.app` to `Applications`.
3. Open the app and install Hooks from the menu bar or settings window.
4. Configure launch at login, sound, Do Not Disturb, and display position as needed.

Note: the current free release uses ad-hoc codesign, so first launch requires the Gatekeeper confirmation above. Developer ID signing and notarization can reduce first-launch friction in a future distribution path, but the current v0.1.0 download, checksum, source, and install notes are public.

## Privacy

Vibelsland Free is local-first. It does not create an account, upload telemetry, or sync data to a remote server. It reads local Claude Code, Codex CLI, and Codex Desktop state only to display session status, tool activity, token summaries, and approval requests.

Read the full privacy note in [PRIVACY.md](PRIVACY.md).

## Build From Source

```sh
swift build
swift test
zsh scripts/package-release.sh
```

## Website Publishing

The website source lives in `docs/` and targets `https://shinteni.github.io/prompt-island/` by default. For a custom domain, do not hand-edit scattered canonical, OG, sitemap, robots, or security.txt URLs. Generate a domain-specific output:

```sh
VIBELSLAND_SITE_URL=https://your-domain.example/ \
VIBELSLAND_CUSTOM_DOMAIN=your-domain.example \
zsh scripts/build-docs-site.sh /tmp/vibelsland-docs-site
```

The script writes `CNAME`, rewrites site URLs, and runs `scripts/verify-docs-site.sh` against multilingual canonical/hreflang, sitemap alternates, manifest, robots, security.txt, and release checksum data.

The website and packaging scripts share [docs/release.json](docs/release.json) as the metadata source for the v0.1.0 package name, checksums, download URLs, and app bundle identity.

Local release artifacts are generated at:

```text
dist/>_ - island.app
dist/Vibelsland-Free-0.1.0-macos.zip
dist/Vibelsland-Free-0.1.0-macos.zip.sha256
```

## Project Status

Vibelsland Free v0.1.0 already includes the downloadable local app experience: floating island UI, settings, hook installation, approval UI, runtime health checks, single-instance protection, restart recovery, and release packaging scripts. The current free release uses ad-hoc signing and provides public download, SHA-256 verification, source, install notes, and support entry points.

## License

Vibelsland Free is open source under the [MIT License](LICENSE).

## Independence

Vibelsland Free is an independent utility. It is not affiliated with Anthropic, OpenAI, Claude, or Codex. Product names are used only to describe local compatibility.
