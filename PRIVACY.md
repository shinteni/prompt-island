# Privacy

&gt;_ - island is a local macOS utility. It does not create an account, call a cloud service, upload telemetry, or sync data to a remote server.

## Local Data Used

The app reads local Claude Code, Codex CLI, and Codex Desktop state so it can show current session status, tool activity, token usage summaries, and approval requests.

The app may read:

- `~/.claude/settings.json` for Claude hook configuration.
- Claude transcript JSONL files under `~/.claude/projects` when a hook event references a session.
- `~/.codex/hooks.json` and `~/.codex/config.toml` for Codex hook configuration.
- `~/.codex/state_5.sqlite`, `~/.codex/sessions`, and Codex rollout JSONL files for local Codex CLI and Codex Desktop session state.
- Codex Desktop's local IPC/app-server proxy when available, only to receive approval requests and return the user's decision.
- Runtime files under `~/.vibelsland-free`.

## Local Data Written

The app writes:

- Configuration at `~/Library/Application Support/VibelslandFree/config.json`.
- Logs at `~/Library/Logs/VibelslandFree/app.log`.
- Runtime bridge files under `~/.vibelsland-free`, including the local Unix socket and a local bridge token.
- Hook configuration changes only when the user installs, repairs, or uninstalls hooks.

Hook payloads are filtered before they are sent to the app. The bridge keeps only known metadata fields such as session ids, event type, workspace, transcript path, approval id, and selected tool information. Nested tool input is limited to small descriptive fields such as command, path, pattern, URL, and tool name.

When the optional approval notification setting is enabled, the app posts approval summaries (source, tool, and truncated command detail) to macOS Notification Center with Allow/Decline actions. These notifications never leave the Mac, are withdrawn when the approval resolves, and follow the user's macOS notification and lock screen settings. The setting is off by default.

Logs are intentionally conservative. They record connection state, event types, timestamps, local paths, thread/request ids, and error reasons, but do not intentionally store full transcript text or full sensitive command output.

Logs stay on the user's Mac until the user deletes them. The app does not currently claim automatic log upload, automatic retention limits, or automatic log cleanup.

## Network

&gt;_ - island does not require an internet connection for its core features. Claude Code, Codex CLI, and Codex Desktop may use their own network connections independently of this app.

The optional update check is the only network feature. It contacts the GitHub releases API (`api.github.com`) only when the user clicks "Check for updates" or enables the launch-time check in settings (off by default). The request carries no account data, no session content, and no telemetry; the response is public release metadata used to compare version numbers.

Vibelsland Free is an independent project. It is not affiliated with Anthropic, OpenAI, Claude, or Codex.

## Distribution Trust

v0.1.0 is ad-hoc signed and is not Developer ID notarized. The SHA-256 checksum verifies that the downloaded file matches the GitHub Release asset; it does not prove developer identity.

The v0.1.0 package targets macOS 14+ on Apple Silicon / arm64.

## Website Privacy

The public website is a static site. It sets no first-party cookies, embeds no analytics script, and collects no form submissions.

Pages are hosted by GitHub Pages. Downloads, source links, release pages, issues, and private vulnerability reporting are provided by GitHub and are governed by GitHub's own terms and privacy policy.

Do not paste tokens, prompts, full session content, absolute private paths, or unredacted logs into public GitHub Issues.

## Security Reports

Security vulnerabilities should be reported through GitHub private vulnerability reporting when available. If that path is unavailable, open only a minimal public issue asking for private contact and do not include exploit details, tokens, prompts, paths, or full logs.

## Uninstall

Use the settings page or menu bar to uninstall hooks before removing the app. This removes Vibelsland bridge entries from Claude and Codex hook configuration.

Then quit `>_ - island` and delete the app from Applications or from the location where it was installed.

If you no longer need local state, delete:

- `~/Library/Application Support/VibelslandFree`
- `~/Library/Logs/VibelslandFree`
- `~/.vibelsland-free`

Deleting `~/.vibelsland-free` removes the local bridge token and runtime socket. The app or hooks recreate the required runtime files on the next launch.
