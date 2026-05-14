# Privacy

Vibelsland Free is a local macOS utility. It does not create an account, call a cloud service, upload telemetry, or sync data to a remote server.

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

Logs are intentionally conservative. They record connection state, event types, timestamps, local paths, thread/request ids, and error reasons, but do not intentionally store full transcript text or full sensitive command output.

## Network

Vibelsland Free does not require an internet connection for its core features. Claude Code, Codex CLI, and Codex Desktop may use their own network connections independently of this app.

## Uninstall

Use the settings page to uninstall hooks. The local runtime directory, logs, and app configuration can then be removed manually if desired.
