# SessionLens Fidelity Ledger

This ledger compares the accepted visual concepts with native SwiftUI/AppKit renders. Runtime truth, accessibility, and native macOS behavior take precedence over illustrative concept values.

## Popover

Evidence:

- Accepted concept: `docs/design/sessionlens-popover-concept.png`
- Native light render: `docs/qa/sessionlens-popover-light.png`
- Native dark render: `docs/qa/sessionlens-popover-dark.png`
- Rendered content size: 390 × 640 points. The saved QA images include the debug-only AppKit title-bar region; release uses the same content inside `MenuBarExtra`.

| Comparison point | Native result | Resolution or intentional difference |
| --- | --- | --- |
| Visible copy | Provider names, quota, usage, range, token, cost, freshness, Settings, and Quit copy match the accepted inventory. | Error/setup branches add only the approved plain-language next action. No SessionWatcher, license, upgrade, or account copy appears. |
| Provider tabs | Three equal native buttons, status dots, selected accent, and a separate 30-point refresh target are present. | Tested OpenCode, Claude setup-required, and Codex ready transitions through the accessibility tree. Selection uses color plus weight/background. |
| Vertical geometry | Stable brand, selector, provider header, scrollable metric region, and fixed footer fit within 390 × 640. | Native debug title-bar chrome is QA-only and compiled out of release. Compact density is intentionally tighter than the high-resolution raster while preserving order and grouping. |
| Typography | System San Francisco only; rounded bold brand/quota, semibold section titles, small metadata, and monospaced numeric values. | Native text metrics and accessibility scaling take precedence over raster pixel measurements. |
| Palette and material | Original OpenCode violet, Claude coral, Codex blue, semantic green quota, semantic separators, and system surfaces render in light and dark appearances. | Whole panels remain neutral; only selection, dots, charts, and quota states use accent color. Reduce Transparency switches to an opaque system window background. |
| Quota row | Weekly label, used percentage, semantic colored bar, reset countdown, and provenance are present. | OpenCode without a mapping renders an em dash and `Quota unavailable`; it never shows zero. |
| Usage-rate chart | Two-point rounded provider stroke and subtle area fill use persisted logical-window quota observations. | The concept curve was illustrative. Production never seeds or interpolates it; fewer than two real observations show a stable insufficient-history message. Axis density is reduced for the 390-point surface. |
| Daily chart | Native Swift Charts bars, provider accent, full-opacity current day, and working 7d/30d/90d segmented control are present. | Bars encode real aggregate tokens, not the concept's illustrative percentages. Missing days are not invented. The initial latest-day boundary bug was fixed and the accessibility result reports all seven days. |
| Token table | Today, Last 7 Days, total tokens, and cost are aligned in a flat table with hairlines. | Cost distinguishes exact local aggregate, estimated Claude session cost, included plan, and unavailable in accessibility text. |
| Footer | Freshness, bordered Settings control, divider, and plain Quit control remain fixed at the bottom. | Manual refresh and Quit were exercised in the native QA process; Settings opens the native SwiftUI Settings scene. |
| Icon style | The code-native original aperture-and-bars mark and SF Symbols are used. | No SessionWatcher icon or downloaded interface icon is used. The final `.icns` asset is handled during packaging. |
| Light and dark | Both saved renders preserve hierarchy, contrast, semantic colors, controls, and all values. | Dark mode uses the accepted cool system surface instead of tinting panels with provider colors. |
| Accessibility | Provider/state labels, quota value/provenance, chart summaries, range radios, cost provenance, Settings, and Quit are exposed. | Color is never the sole indicator. The Claude setup state combines its title, explanation, and Refresh action into a discoverable group. |

## Interaction evidence

- Provider selection: OpenCode ready → Claude setup required → Codex ready rendered distinct, non-fatal branches.
- Range selection: the accessibility tree changed from `7d = 1` to `30d = 1`, and the x-axis changed from weekday to calendar labels.
- Manual refresh: the control activated and fixture metrics stayed deterministic.
- Quit: the native button terminated the QA process; the accessibility app list became empty.

## Settings

Evidence:

- Accepted concept: `docs/design/sessionlens-settings-concept.png`
- Native light render: `docs/qa/sessionlens-settings-light.png`
- Native dark render: `docs/qa/sessionlens-settings-dark.png`
- Rendered content size: 760 × 560 points, plus the standard title-bar region in the debug QA window.

| Comparison point | Native result | Resolution or intentional difference |
| --- | --- | --- |
| Window geometry | The native Settings scene uses a fixed 760 × 560 content size, 196-point material sidebar, separator, and 24-point detail inset. | Native title-bar metrics take precedence over the concept's illustrative chrome. |
| Sidebar and brand | General, Providers, Menu Bar, Notifications, and Privacy use SF Symbols and native selection. The original SessionLens mark and title fit on one line. | The first render exposed a wrapped brand title; tested layout metrics reduced the mark and gap while preserving the accepted hierarchy. |
| Provider rows | OpenCode Detected, Claude Code Not installed, and Codex Connected appear with exact source explanations, status text, provider accents, actions, and separators. | Runtime health replaces illustrative statuses. The source paths and local app-server methods remain compact metadata rather than marketing copy. |
| Provider actions | Mapping expands exact `openai` and `anthropic` ID controls; Refresh invokes the coordinator; Install Bridge presents a native confirmation before any write. | QA cancelled the bridge confirmation, so `~/.claude/settings.json` was not changed. |
| General | Launch at login, refresh interval, default range, and retention use native controls. | The refresh interval was changed from five minutes to one minute in the in-memory fixture and the accessibility value updated. The real login item was not changed during QA. |
| Menu Bar | Urgent, Active, Icons, and Minimal modes are visible with a live preview and accessible provider-order controls. | Selecting Active changed the preview from exact quota urgency to the active OpenCode aggregate. |
| Notifications | Explicit enable toggle, permission explanation, threshold list, custom stepper, Add action, and reset toggle are present. | Adding 80% updated the in-memory list. Notification permission was intentionally not requested during fixture QA. |
| Privacy | Exact OpenCode, Claude Code, and Codex allowlists; no-backend statement; local-store path; and destructive Clear History action are visible. | Clear History presents a native confirmation that names only SessionLens-owned aggregate and notification records. QA cancelled the deletion. |
| Light and dark | Both appearances preserve hierarchy, contrast, provider accents, status colors, controls, and readable secondary metadata. | System materials and semantic colors adapt natively rather than reproducing raster colors literally. |
| Accessibility | Sidebar selection, provider status groups, mappings, every picker/toggle, ordering buttons, notification stepper, and destructive confirmations are exposed with names and values. | Color is never the only source/status signal; disabled edge-order controls are announced. |

## Settings interaction evidence

- Sidebar: all five sections rendered distinct content in the native accessibility tree.
- Mapping: Configure Mapping revealed two exact provider-ID pickers, both defaulting to `No quota mapping`.
- Claude bridge: Install Bridge opened the reversible `~/.claude/settings.json` confirmation; Cancel returned without a write.
- General: Refresh interval changed from `5 minutes` to `1 minute` in the in-memory fixture.
- Menu Bar: Active changed from unselected to selected and the live preview changed providers/metric.
- Notifications: Add inserted an `80% used` threshold and disabled the duplicate Add action.
- Privacy: Clear History opened the provider-safe deletion confirmation; Cancel returned without deleting data.
