# SessionLens macOS App Design

**Status:** Approved design
**Date:** 2026-08-12
**Target:** macOS 14 Sonoma and later
**Distribution:** Free, unsigned personal-use `.app`

## 1. Purpose

SessionLens is a clean-room, local-first macOS menu-bar utility inspired by the useful workflow of SessionWatcher. It gives one-glance visibility into OpenCode, Claude Code, and Codex usage without licensing, subscriptions, analytics, or an app-owned backend.

The app must track:

- provider availability and freshness;
- token usage and cost when the provider exposes them;
- rolling rate-limit windows and reset times when the provider exposes them;
- local history and charts;
- configurable threshold and reset notifications.

The app must never persist or intentionally inspect prompts, responses, reasoning, source code, diffs, command output, credentials, project names, working-directory paths, or transcript contents.

## 2. Product principles

1. **Glanceable:** the most urgent quota is understandable from the menu bar without opening a dashboard.
2. **Honest provenance:** every quota or cost value is classified as exact, locally derived, user-configured, stale, or unavailable.
3. **Local by construction:** the app owns no network client and sends no telemetry. Provider-owned CLIs may contact their own services to refresh account data.
4. **Privacy through allowlists:** adapters request or decode only explicitly approved aggregate fields.
5. **Graceful partial operation:** one missing or broken provider never blocks the other providers.
6. **Native restraint:** the interface uses familiar macOS popover, material, chart, settings, notification, and launch-at-login behavior.

## 3. Scope

### In scope

- Native SwiftUI menu-bar app with no normal Dock presence.
- OpenCode, Claude Code, and Codex provider adapters.
- Menu-bar summary and provider popover.
- Five-hour and weekly quota windows where exposed.
- Underlying-provider quota attribution for OpenCode sessions.
- Token, cache-token, and cost summaries where exposed.
- Seven-, 30-, and 90-day charts backed by local aggregate history.
- Notifications at configurable thresholds and on reset.
- Settings for providers, menu-bar display, refresh interval, local budgets, history retention, notifications, launch at login, and privacy inspection.
- A build script that produces a double-clickable unsigned `.app` for personal use.

### Out of scope

- SessionWatcher branding, trademarks, copyrighted assets, proprietary code, license bypasses, or authentication bypasses.
- Reading or displaying conversation content, project names, code, diffs, or command output.
- Cloud sync, accounts, analytics, licensing, payments, auto-update infrastructure, or an app-owned service.
- Editing provider credentials or logging the user into a provider.
- Claiming an estimated budget is a provider quota.
- Universal OpenCode quotas; OpenCode can route through providers with incompatible quota models.
- Mac App Store distribution, signing, notarization, or multi-device sync.

## 4. Naming and identity

The working product name is **SessionLens**. It uses an original bar-and-aperture mark rather than SessionWatcher's icon or wordmark. Provider names and marks appear only to identify integrations and include a small independence notice in About.

## 5. Architecture

### 5.1 App shell

`SessionLensApp` owns:

- a SwiftUI `MenuBarExtra` using window style;
- a settings `Window` scene;
- an `AppModel` on the main actor;
- one long-lived `UsageCoordinator` actor;
- a launch-at-login controller using `SMAppService` when supported.

The app declares `LSUIElement = true`, so it does not appear as a normal Dock app. Opening Settings may temporarily activate the application and bring its window forward.

### 5.2 Domain boundaries

The core module defines provider-neutral types:

- `ProviderID`: `opencode`, `claude`, or `codex`;
- `ProviderSnapshot`: provider health, observation time, usage totals, cost, daily buckets, quota windows, and provenance;
- `QuotaWindow`: label, duration, used percent, reset time, state, and provenance;
- `TokenBreakdown`: input, output, reasoning, cache read, cache write, and total;
- `UsageBucket`: local day, tokens, and optional cost;
- `MetricProvenance`: exact provider value, exact local aggregate, user-configured local budget, estimated, stale, or unavailable;
- `ProviderHealth`: ready, setup required, tool missing, stale, malformed data, timed out, or temporarily unavailable.

Provider adapters conform to a small `UsageProvider` protocol. UI, storage, and notification code never depend on provider-specific wire formats.

### 5.3 Refresh coordination

`UsageCoordinator`:

- performs an initial refresh at launch;
- refreshes on a configurable 60-second default timer;
- refreshes immediately when the popover opens if the newest snapshot is older than 15 seconds;
- runs adapters concurrently with a task group;
- prevents overlapping refreshes;
- applies an eight-second timeout per adapter;
- retains the last good snapshot after a transient failure;
- publishes an immutable aggregate state to the main actor;
- persists only normalized aggregate data.

## 6. Provider adapters

### 6.1 Codex

The Codex adapter launches the installed `codex app-server --listen stdio://` process and communicates over newline-delimited JSON.

The connection performs the required `initialize` request and `initialized` notification, then uses only these account methods:

- `account/rateLimits/read` for exact quota percentages and reset times;
- `account/usage/read` for exact account token totals and daily token buckets.

The adapter does not call thread, turn, item, history, or transcript methods. It does not open `~/.codex/sessions` or other Codex conversation files.

For ChatGPT subscription usage, incremental dollar cost is displayed as **Included with plan**, not fabricated from API pricing. If an exact cost is unavailable, the normalized cost remains `nil`.

The subprocess is reused while healthy and restarted after protocol failure. Stderr is bounded and used only for a short redacted diagnostic code; raw stderr is neither persisted nor shown.

### 6.2 Claude Code

Claude Code exposes usage and subscription quota values to its official status-line command. SessionLens provides an opt-in bridge installed from Settings.

The bridge:

1. receives Claude's status-line JSON on stdin;
2. selects only an allowlist of numeric and non-content fields;
3. atomically writes the normalized snapshot to SessionLens Application Support;
4. forwards the original JSON to the user's existing status-line command when one existed;
5. returns the existing status-line output unchanged.

Allowed fields are:

- observation timestamp added by the bridge;
- a one-way hash of `session_id` used only for counter-reset detection;
- model identifier and display name;
- cost totals;
- context-window token totals and current token breakdown;
- five-hour and seven-day used percentages and reset timestamps;
- Claude Code version.

The bridge never writes `cwd`, workspace fields, transcript path, session name, git data, agent data, or any unrecognized field. The status-line payload does not contain prompt or source-code content.

Installation is explicit. The app backs up the exact existing `statusLine` settings block, installs a wrapper, and records a checksum. Uninstall restores the original block only when the wrapper still matches that checksum; otherwise it stops and explains the conflict instead of overwriting a user's later edit.

History begins when the bridge is installed. Session-level cumulative counters are converted to deltas using the hashed session identifier and monotonically increasing totals.

### 6.3 OpenCode

OpenCode persists aggregate values in its local SQLite `session` table. The adapter opens the database read-only through `/usr/bin/sqlite3 -readonly -json` and executes a fixed query that selects only:

- `time_created` and `time_updated`;
- `model`;
- `cost`;
- `tokens_input`;
- `tokens_output`;
- `tokens_reasoning`;
- `tokens_cache_read`;
- `tokens_cache_write`.

No query may reference `message`, `part`, `session_input`, project, directory, title, prompt, text, data, or credential tables/columns. Tests enforce the allowed table and column list.

The query groups results into daily, model, and provider-neutral totals. When the installed schema lacks required aggregate columns, the adapter returns a schema-drift health state and keeps its last good snapshot.

OpenCode does not own a universal quota because it can route through many providers. The UI therefore:

- associates OpenAI-backed sessions with the exact Codex account quota when that mapping is valid;
- associates Anthropic-backed sessions with the exact Claude quota when that mapping is valid;
- otherwise shows an optional user-configured rolling five-hour or weekly local budget, labeled **Local budget**;
- shows **Quota unavailable** when neither exact attribution nor a local budget exists.

## 7. Persistence

SwiftData stores normalized aggregate records in the app's Application Support directory.

Persisted entities are:

- provider snapshot summaries;
- daily usage buckets;
- quota observations;
- notification crossing keys;
- provider health timestamps;
- user preferences;
- Claude bridge installation metadata and original settings backup.

Raw provider responses, CLI stderr, credentials, paths, session names, project identifiers, prompts, messages, and source content are never stored.

Retention defaults:

- fine-grained quota observations: 90 days;
- daily aggregate buckets: one year;
- notification crossing keys: until the associated reset plus seven days;
- diagnostics: in memory only.

Cleanup runs once per day and is safe to repeat.

## 8. User experience

### 8.1 Menu bar

The status item uses the SessionLens mark plus a compact text mode chosen in Settings:

- **Urgent:** provider abbreviation and the highest exact used percentage;
- **Active:** most recently updated provider and percentage or token count;
- **Icons:** three tiny provider state indicators without numbers;
- **Minimal:** mark only.

The default is Urgent. Exact quota values outrank local budgets. Unavailable values never render as `0%`.

Semantic colors are restrained: neutral below 70%, amber at 70%, red at 90%, and muted gray when unavailable or stale. Color is never the only state cue.

### 8.2 Popover

The popover targets approximately 390 by 640 points and follows the system appearance.

From top to bottom:

1. Provider selector for OpenCode, Claude, and Codex with availability dots.
2. Provider header with current state, freshness, and manual refresh.
3. Quota section with five-hour and weekly rows, percentage, direction/burn indicator, reset countdown, and provenance label where needed.
4. Usage-rate chart for the selected quota or local budget.
5. Daily usage chart with 7d, 30d, and 90d range control.
6. Token and cost summary table.
7. Model/provider breakdown when safely available.
8. Footer with last refresh, Settings, and Quit.

Controls update real local state. Selecting a provider or range changes the rendered data. Refresh triggers the coordinator. Settings and Quit perform their native actions.

### 8.3 Settings

Settings uses five sections:

- **General:** launch at login, refresh interval, and history retention.
- **Providers:** detection state, data-source explanation, Claude bridge install/uninstall, and OpenCode local budgets.
- **Menu Bar:** display mode and provider ordering.
- **Notifications:** permission state, threshold toggles, custom thresholds, and reset alerts.
- **Privacy:** exact allowlists, local storage location, clear-history action, and confirmation that analytics/networking are absent.

### 8.4 Visual system

The interface is recognizably a native macOS utility rather than a website inside a window:

- system materials and vibrancy;
- SF Pro/system typography;
- 12-point primary surface radius and 8-point compact control radius;
- hairline separators instead of nested cards everywhere;
- provider accents: Claude warm coral, Codex blue, OpenCode violet;
- semantic green, amber, and red only for usage state;
- Swift Charts with subtle fills and accessible line contrast;
- light and dark appearances with identical information hierarchy;
- reduced-motion support and no decorative continuous animation.

## 9. Notifications

The app requests notification permission only when the user enables notifications.

Default alerts are:

- first crossing of 70% within a quota window;
- first crossing of 90%;
- quota reset after a previously observed nonzero window.

Each alert key includes provider, account scope when safely available, window identity, threshold, and reset epoch. An alert fires once per real crossing. Dropping below a threshold does not re-arm it until the reset epoch changes.

Local-budget notifications explicitly say **local budget**. Stale or unavailable values never trigger quota alerts.

## 10. Error and stale-state behavior

- Missing executable: show setup required and the discovered search paths.
- Provider not authenticated: show provider-owned sign-in guidance without handling credentials.
- Timeout: keep the last good snapshot and mark it stale.
- Malformed data or schema drift: isolate the adapter, retain other providers, and show a concise source-health message.
- Database busy: retry once with a short delay, then keep the last good snapshot.
- Claude bridge conflict: leave settings untouched and offer a manual explanation.
- Notification permission denied: keep tracking and show a settings shortcut.
- No data yet: show a designed empty state with the exact next action, never seeded fake metrics.

## 11. Security and privacy constraints

1. The app target has no HTTP client code or analytics dependency.
2. No credential file is opened or copied.
3. Every adapter uses an explicit field allowlist.
4. OpenCode SQL is a constant, read-only query enforced by tests.
5. Codex app-server access is limited to initialization and account usage/rate-limit methods.
6. Claude bridge output is written atomically with user-only permissions.
7. Diagnostics contain provider, error category, and timestamp only.
8. Clear History deletes only SessionLens-owned aggregate records after confirmation.
9. The app never modifies provider state except the explicitly approved Claude bridge install/uninstall operation.

## 12. Packaging and build

The repository uses Swift Package Manager so it can build with the installed Swift command-line toolchain without requiring a full Xcode installation.

The package contains:

- the app executable target;
- focused core, provider, persistence, and UI source groups;
- unit and integration test targets;
- resources for the original app icon and provider-identification assets;
- a packaging script that builds release mode and assembles `dist/SessionLens.app` with its `Info.plist` and resources.

The personal build is unsigned. Documentation explains the local first-launch flow and makes no claim of notarization.

## 13. Testing and verification

### Automated tests

- Domain normalization and provenance rules.
- Codex JSONL request/response framing, initialization, rate-limit parsing, usage parsing, timeout, restart, and redaction.
- Claude bridge allowlist, atomic cache write, cumulative-to-delta conversion, existing-status-line preservation, checksum conflict handling, and uninstall restoration.
- OpenCode SQL allowlist, daily aggregation, read-only behavior, database-busy handling, and schema drift.
- Coordinator concurrency, no-overlap behavior, last-good retention, and staleness.
- Notification crossing and reset deduplication.
- Persistence retention and clear-history behavior.
- Menu-bar urgency selection and unavailable-value handling.

All fixtures are synthetic and contain no real prompts, paths, credentials, or user data.

### Runtime verification

- Build and test with the installed Swift toolchain.
- Assemble and launch the real `.app` bundle.
- Verify menu-bar-only behavior and Settings activation.
- Exercise Codex against the locally installed app-server and compare normalized results to the same account methods.
- Exercise OpenCode against a temporary synthetic SQLite database and, separately, verify the real database can be opened read-only without querying content tables.
- Exercise the Claude bridge with synthetic official status-line payloads; if Claude Code is unavailable locally, report live-provider verification as unavailable rather than claiming it passed.
- Trigger synthetic 70%, 90%, reset, stale, missing-tool, and schema-drift states.
- Inspect the real popover and settings UI in light and dark appearance.
- Compare the accepted visual concept with screenshots at its native size and record a fidelity ledger.
- Confirm no app-owned network request occurs during a refresh.

## 14. Acceptance criteria

The implementation is complete only when all of the following are proven on the current tree:

1. `swift test` passes.
2. The release build and `.app` packaging succeed.
3. Launching the bundle creates a working menu-bar app with no normal Dock icon.
4. The popover exposes working OpenCode, Claude, and Codex states.
5. Codex shows live exact account quota and history through app-server without reading sessions.
6. OpenCode shows aggregate tokens/cost/history through the allowlisted read-only query.
7. Claude bridge installation, ingestion, preservation, and removal pass synthetic integration tests; live verification is separately identified if Claude is not installed.
8. Charts and range controls render real normalized data.
9. Notifications are permission-aware and deduplicated.
10. Missing, stale, malformed, and unavailable states are visible and non-fatal.
11. Privacy tests prove forbidden OpenCode tables/columns and Codex thread methods are not accessed or persisted.
12. No licensing, payment, analytics, cloud-sync, or app-owned backend code exists.
13. Visual QA finds no clipped content, unreadable typography, placeholder UI, inert controls, or unapproved reference-brand copying.

## 15. Known risks and mitigations

- **Provider schema drift:** isolate wire formats inside adapters, test fixtures by version, preserve last-good state, and expose source health.
- **Claude bridge settings conflict:** explicit install, exact backup, checksum guard, and fail-closed restoration.
- **OpenCode provider ambiguity:** never infer quota from model name alone; require a validated mapping or user-configured local budget.
- **Codex process lifetime:** bounded reads, protocol IDs, timeouts, stderr limits, and supervised restart.
- **Unsigned-app friction:** document the personal local-launch flow and do not overstate distribution readiness.
- **No local Claude installation during development:** build a faithful synthetic integration harness and keep live verification status explicit.

## 16. Design completion state

There are no unresolved placeholders or implementation-defining choices in this design. Visual concept generation may refine spacing and exact component geometry, but it may not alter the architecture, privacy boundaries, provider semantics, feature scope, or acceptance criteria without a design amendment.
