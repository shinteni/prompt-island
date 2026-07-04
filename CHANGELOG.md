# Changelog

## 0.1.0 - 2026-05-14

- Published the first GitHub Release package for macOS 14+.
- Added the local floating island UI for Claude Code, Codex CLI, and Codex Desktop session status.
- Added local approval request display and response handling.
- Added settings, hook installation, runtime health checks, single-instance protection, and restart recovery.
- Published the GitHub Pages documentation site, install notes, privacy note, checksum metadata, and release packaging scripts.

## Unreleased

- Reduced background wakeups: the Codex Desktop poller now self-schedules at its adaptive cadence instead of ticking every second, session-aging refresh only wakes at actual visibility boundaries (and not at all when idle and collapsed), and the expanded island's mouse-leave auto-collapse is driven by tracking-area events instead of a 0.22s mouse poll. Refresh rates and collapse timing are unchanged.
- Added Claude Code token usage to session details: per-turn and cumulative token counts parsed incrementally from local transcripts, plus an estimated API-equivalent cost for recognized model families.
- Added an update checker in settings: a manual "Check for updates" button plus an optional launch-time check (off by default); the GitHub releases API is contacted only on explicit user action, keeping the local-first promise.
- Added an approval queue in the expanded island: when several tools wait at once, approvals are listed oldest-first with inline Allow/Decline per row, an overflow count, and a pending-approval count on the compact pill.
- Added optional approval notifications: macOS Notification Center banners with Allow/Decline actions as a fallback when you are away from the island (off by default, withdrawn once the approval resolves, suppressed by Do Not Disturb).
- Added optional global hotkeys: ⌃⌥I toggles the island and ⌃⌥A jumps to the pending approval (off by default, no extra permissions required).
- Added Japanese README and Japanese documentation pages.
- Added GitHub Actions checks for Swift build and test-target discovery.
- Added maintainer release gate improvements and clearer ad-hoc signing documentation.
- Improved Codex Desktop live connection startup from Finder-launched macOS app environments.
