# SessionLens verification report

Date: 2026-08-12  
Build: `codex/sessionlens-app`  
Distribution: free local personal-use macOS 14+ app; ad-hoc signed only for local launch

All automated fixtures are synthetic. No prompt, source-code, credential, project-path, or transcript data was copied into a fixture or report.

| Acceptance criterion | Evidence | Result | Notes |
| --- | --- | --- | --- |
| 1. `swift test` passes | `scripts/test.sh` completed with 95 tests in 15 suites. | Proven | Includes provider, persistence, notifications, lifecycle, UI summary, and privacy suites. |
| 2. Release build and `.app` packaging succeed | `zsh scripts/package_app.sh`; `zsh scripts/verify_bundle.sh dist/SessionLens.app`; `codesign --verify --deep --strict`. | Proven | Bundle contains the app executable, Claude helper, Info.plist, and generated `.icns`. |
| 3. Bundle launches as a menu-bar app without a normal Dock icon | `open -n dist/SessionLens.app` launched the process; unified logs show Control Center registered `com.justinchiu.SessionLens-Item-0` as a `.menuBar` displayable. `LSUIElement=true` is verified in the bundle. | Proven | The process remains accessory/background and no Dock window is created. |
| 4. Popover exposes OpenCode, Claude, and Codex states | `docs/qa/sessionlens-popover-light.png`, `sessionlens-popover-dark.png`; native accessibility QA switched OpenCode → Claude setup-required → Codex ready. | Proven | Missing Claude is a non-fatal setup state. |
| 5. Codex shows exact account quota/history without sessions | Direct local app-server verification returned responses for only `account/rateLimits/read` and `account/usage/read`; result keys were `rateLimits`/`rateLimitsByLimitId` and `dailyUsageBuckets`/`summary`. Codex tests enforce no thread/turn/item methods. | Proven | Raw account identity was not retained in this report. |
| 6. OpenCode shows aggregate tokens/cost/history through a read-only allowlist | Independent `/usr/bin/sqlite3 -readonly -json` execution returned 5 aggregate rows; database modification time was unchanged. `PrivacyBoundaryTests` and provider tests enforce the SQL identifiers and schema behavior. | Proven | The query touches only the aggregate `session` fields. |
| 7. Claude bridge is safe and reversible | Claude bridge installer/provider suites passed preservation, checksum conflict, uninstall, atomic-cache, and allowlist tests. `claude` is not installed locally. | Proven | Live status: `Claude CLI not installed; synthetic official-payload integration passed`. No real Claude settings were changed. |
| 8. Charts and range controls render normalized data | Popover screenshots show quota/daily charts; accessibility QA changed 7d to 30d and changed the x-axis labels. | Proven | Charts use persisted normalized buckets and do not seed missing days. |
| 9. Notifications are permission-aware and deduplicated | Notification evaluator/scheduler tests passed threshold crossing, reset epochs, stale/unavailable suppression, and durable deduplication. Settings QA added a custom threshold without requesting permission. | Proven | Permission remains opt-in by default. |
| 10. Missing/stale/malformed/unavailable states are visible and non-fatal | Provider normalization and coordinator tests cover tool missing, setup required, timeout, malformed data, schema drift, stale last-good state, and non-fabricated metrics; UI QA exercised setup/error states. | Proven | One provider failure does not block the other tabs. |
| 11. Privacy tests prove forbidden access is absent | `PrivacyBoundaryTests` passed exact OpenCode SQL identifiers, Codex method allowlist, Core Data persisted-property allowlist, and Claude cache keys. | Proven | No prompt/source/project/path/message fields are persisted. |
| 12. No licensing, payment, analytics, cloud sync, or app-owned backend code | `rg -n 'URLSession|import Network|NWConnection|CFHTTP' Sources` returned no matches; README and Info.plist describe free local use; dependencies are system frameworks only. | Proven | Provider-owned CLIs may perform their own authenticated refreshes; SessionLens has no network client. |
| 13. Visual QA is clean and original | Accepted concepts and latest light/dark renders were inspected with `view_image`; fidelity ledger records comparison points and fixes. Native accessibility QA exercised tabs, ranges, refresh, Settings, mappings, confirmations, and Quit. | Proven | The icon is the original aperture-and-bars source; no SessionWatcher asset or wordmark is used. |

## Runtime notes

- OpenCode live aggregate check: 5 rows, unchanged source-database mtime.
- Codex live app-server check: initialize plus the two account methods only; no thread methods.
- Claude live check: unavailable because the CLI is not installed; synthetic official-shaped payload tests passed.
- The packaged app is ad-hoc signed for this personal build. It is intentionally not notarized or presented as a distributable commercial application.
