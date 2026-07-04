# Changelog

## 0.1.0 - 2026-05-14

- Published the first GitHub Release package for macOS 14+.
- Added the local floating island UI for Claude Code, Codex CLI, and Codex Desktop session status.
- Added local approval request display and response handling.
- Added settings, hook installation, runtime health checks, single-instance protection, and restart recovery.
- Published the GitHub Pages documentation site, install notes, privacy note, checksum metadata, and release packaging scripts.

## Unreleased

- Added one-click in-app updates: "Check & update" in settings downloads the new release, verifies its SHA-256 against the published checksum, verifies the code signature structure, atomically swaps the app bundle (with rollback on failure), and relaunches. Falls back to the release page for dev builds or releases without self-update assets.
- Polished island motion and interaction feedback: the expand/collapse frame animation is now display-link driven (full frame rate on ProMotion) with a snappier ease-out expansion curve, content crossfades gain subtle depth scaling, approval cards spring in and out, and every clickable island element gets hover highlighting with a pointing-hand cursor plus press feedback. The system Reduce Motion setting disables all scaling and transitions.
- Added Homebrew Cask support: the repository doubles as a tap (`brew tap shinteni/island https://github.com/shinteni/prompt-island.git && brew install --cask shinteni/island/vibelsland-free`); the cask is generated from docs/release.json and verify-cask.sh gates version/SHA-256 consistency.
- Added a local statistics card in settings: today/last-7-days session, approval, and token/cost counters with a per-day token mini chart. Counters are aggregate-only (no session content), stay on this Mac, keep 30 days, and can be cleared anytime.
- Release packaging now builds a Universal Binary (Apple Silicon + Intel): each architecture compiles separately and merges via lipo so the flow works without full Xcode, and build/verify scripts assert both slices are present. Applies from the next release; the published v0.1.0 package remains arm64-only.
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
