# SessionLens

SessionLens is a free, local-only macOS menu-bar utility inspired by SessionWatcher. It is a personal SwiftUI app for OpenCode, Claude Code, and Codex usage, costs, quota windows, history, charts, and optional notifications. It has no license key, subscription, backend, or telemetry.

The project is available under the [MIT License](LICENSE).

## What SessionLens reads

- OpenCode: `~/.local/share/opencode/opencode.db`, through one fixed `sqlite3 -readonly -json` aggregate query over the `session` table.
- Claude Code: only after you explicitly install the bridge, the official status-line JSON delivered to the bridge on standard input. The bridge keeps normalized quota, context-token, model, session-hash, and estimated-cost metadata in the local SessionLens bridge directory.
- Codex: the local `codex app-server --listen stdio://` JSONL process, limited to `initialize`, `initialized`, `account/rateLimits/read`, and `account/usage/read`.
- SessionLens: its own normalized aggregate history, notification deduplication records, and settings in Application Support.

## What SessionLens never reads

SessionLens never reads prompts, source code, transcript/message content, diffs, project files, credentials, API keys, or provider databases outside the documented aggregate fields. It does not call a network API, ship data to a service, or use a remote analytics SDK. The only provider configuration file it touches is `~/.claude/settings.json`, and only for the explicitly confirmed bridge install/uninstall flow.

## Requirements

- macOS 14 or newer.
- Swift 6 from Xcode Command Line Tools (or Xcode).
- Any provider CLI is optional. OpenCode and Codex must already be installed and authenticated for live values; Claude Code must be installed to use its status-line bridge.

## Build and package

From the repository root:

```zsh
swift test
zsh scripts/package_app.sh
zsh scripts/verify_bundle.sh dist/SessionLens.app
```

The package script creates `dist/SessionLens.app`, copies the bridge helper, derives the original icon, removes quarantine attributes, and applies an ad-hoc local signature. The signature is for local launch validation, not App Store distribution or notarization.

## First launch of the unsigned app

Open `dist/SessionLens.app`. If macOS blocks the first launch, Control-click the app, choose **Open**, and confirm the macOS warning. SessionLens is an accessory/menu-bar app, so it intentionally has no normal Dock icon. Click its menu-bar mark to open the popover, then use **Settings** for setup and preferences.

## OpenCode setup

Leave the default OpenCode database at `~/.local/share/opencode/opencode.db` or make the same path available before refreshing. SessionLens reports setup required, tool missing, timeout, schema drift, or a ready aggregate without fabricating zeros. OpenCode provider IDs are not assigned to Claude or Codex quotas unless you explicitly choose a mapping in Settings.

In Settings → Providers, each discovered OpenCode provider ID can have an optional local USD budget for a rolling 5-hour window and a weekly window. These values are user-configured guardrails, not provider quotas; the popover labels them **Local budget**. A wildcard fallback can be used when the aggregate contains several provider IDs. Exact Claude or Codex attribution always takes precedence.

Quota windows are shown as remaining capacity throughout the app: a 22% used window appears as 78% remaining, and its bar depletes as usage accumulates. Notification thresholds and stored history continue to use provider-reported usage percentages.

## Claude bridge setup and removal

Open Settings → Providers → Claude Code and choose **Install Bridge**. Read and confirm the native warning before allowing the one write to `~/.claude/settings.json`. SessionLens backs up the prior `statusLine` value, preserves its command output, and uses a checksum before restoring it. Choose **Uninstall Bridge** to restore the exact prior status line; if the setting changed afterward, SessionLens stops without overwriting it.

## Codex setup

Install and authenticate Codex locally so `codex` is discoverable on `PATH` or in one of the supported macOS locations. SessionLens starts the local app-server and requests only account usage and rate-limit methods. It does not enumerate threads or read thread content.

Codex quota windows are detection-only: SessionLens shows a 5-hour window only when the current app-server response exposes one. The menu-bar summary prefers that 5-hour window and falls back to the returned weekly window while Codex's 5-hour limit is unavailable.

## Notifications

Notifications are disabled by default. Enable them in Settings to request macOS permission, then choose percentage thresholds and whether quota resets should notify. Unavailable, stale, estimated, and local-budget values do not produce provider-quota alerts, and durable event keys prevent duplicate crossings.

## Local data and clearing history

Normalized history is stored at `~/Library/Application Support/SessionLens/usage.sqlite`; Claude bridge metadata and cache live under `~/Library/Application Support/SessionLens/Bridge`. Settings control the 60-second default refresh interval and retention. Fine-grained quota observations are retained for at most 90 days, daily aggregates follow the selected retention, and notification crossing keys are pruned with that same local retention. **Clear History** asks for confirmation and deletes only SessionLens usage, quota-history, and notification records; it does not touch provider data or Claude settings.

## Verification

The focused and full test commands exercise provider normalization, privacy allowlists, persistence, notifications, bridge safety, lifecycle settings, and menu-bar summaries. The final local checks are:

```zsh
swift package clean
swift test
zsh scripts/package_app.sh
zsh scripts/verify_bundle.sh dist/SessionLens.app
if rg -n 'URLSession|import Network|NWConnection|CFHTTP' Sources; then exit 1; fi
git diff --check
```
