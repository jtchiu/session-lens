# SessionLens Design Inventory

## Accepted images

- `sessionlens-popover-concept.png` is the source of truth for the 390 × 640 point menu-bar popover. The committed raster is a 979 × 1606 high-resolution concept at the same aspect ratio.
- `sessionlens-settings-concept.png` is the source of truth for the 760 × 560 point Settings window. The committed raster is a 1462 × 1076 high-resolution concept at the same aspect ratio.
- `sessionlens-icon-source.png` is the original 1024 × 1024 application-icon master. AppIcon sizes are derived from this file without changing its geometry.
- The concepts define hierarchy, density, visual character, and copy. Runtime values, native control metrics, accessibility sizing, and system materials take precedence when the operating system requires them.

## Allowed visible copy

Popover copy is limited to: `OpenCode`, `Claude`, `Codex`, `5-hour`, `Weekly`, `resets`, `Remaining`, `Depleted`, `Exact provider quota`, `Local budget`, `Quota unavailable`, `Quota Remaining`, `of weekly limit`, `Daily Usage`, `7d`, `30d`, `90d`, `Token Usage`, `Token Detail`, `Model Breakdown`, `Input`, `Output`, `Reasoning`, `Cache read`, `Cache write`, `Today`, `Last 7 Days`, `Cost`, `Spend & effectiveness`, `Included with plan`, `API eq.`, `tokens`, `Live pricing`, `Cached pricing`, `Pricing unavailable`, `API equivalent unavailable`, `Rates as of`, `Updated just now`, `Settings`, `Quit`, availability and error explanations, localized dates, normalized token counts, normalized currency totals, percentages, and reset countdowns.

Settings copy is limited to: `SessionLens`, `General`, `Providers`, `Menu Bar`, `Notifications`, `Privacy`, `Local, read-only usage sources.`, `Detected`, `Not installed`, `Connected`, `Configure Mapping`, `Install Bridge`, `Uninstall Bridge`, `Manual Resolution`, `Local budget`, `Permission`, `Not requested`, `Authorized`, `Denied`, `Open System Settings`, `Refresh`, `Aggregate tokens and cost from the local session database.`, `Install a privacy bridge to receive usage and quota metadata.`, `Exact account usage and rate limits through the local app-server.`, `Weekly`, `Aggregate usage metadata stays on this Mac. Public model pricing metadata may be fetched for API-equivalent estimates. Claude bridge settings and only the allowlisted top-level Codex model setting are read locally; prompts, source code, credentials, and project-path metadata are never read or sent.`, `Public model pricing is fetched only for API-equivalent estimates; usage data stays on this Mac.`, `Prompts, source code, credentials, and project-path metadata are never sent or stored.`, `No analytics, licensing, cloud sync, or app-owned backend.`, `Learn More`, plus native labels for refresh interval, chart range, menu-bar display, notification thresholds, launch at login, retention, bridge confirmation, history deletion confirmation, and source-specific failure states.

Never show prompts, source code, message excerpts, credentials, project paths, account identifiers, raw provider payloads, marketing copy, upgrade prompts, license copy, advertisements, or SessionWatcher product text or marks.

## Layout geometry

- Popover: fixed 390-point width and 640-point preferred height, with a single vertically scrolling content region only if accessibility text or error details require it.
- Popover header: 16-point outer inset; compact brand row; three equal provider segments and one 28-point refresh target.
- Summary: weekly quota and reset share one baseline. Charts occupy the full content width and remain visually flat rather than becoming nested cards.
- Footer: fixed bottom row with freshness at leading, then Settings and Quit actions at trailing.
- Settings: 760 × 560 points, native title-bar chrome, 196-point sidebar, one-pixel separator, and a flexible detail column with 24-point outer insets.
- Provider rows: 112–132 points tall, color dot and title at leading, status inline, description and provenance below, one trailing action, and a hairline divider.

## Light and dark palette

Use semantic macOS colors wherever an equivalent exists so contrast follows the current appearance.

| Role | Light reference | Dark reference |
| --- | --- | --- |
| Window/material | system window background / translucent popover material | system window background / translucent popover material |
| Primary text | graphite `#202124` | near-white `#F3F4F6` |
| Secondary text | slate `#686A70` | cool gray `#AEB1B8` |
| Separator | `#D8DADF` at 70% | `#FFFFFF` at 12% |
| Codex | electric blue `#146EF5` | `#4C8DFF` |
| Claude | warm coral `#F06F45` | `#FF8A65` |
| OpenCode | violet `#6F3BDD` | `#9B72F2` |
| Success | system green | system green |
| Warning | system orange | system orange |
| Failure | system red | system red |

Provider accents identify selection, dots, chart strokes, and compact highlights only. They do not tint whole panels. Charts use the selected provider accent plus a low-opacity fill. The icon retains its graphite tile and blue highlight in both appearances.

## Typography

- Use the system San Francisco family only; no bundled fonts.
- Popover title/primary quota: `.system(size: 24, weight: .bold, design: .rounded)` or the closest Dynamic Type-relative native style.
- Section title and provider title: 13–17 points, semibold.
- Body and metric labels: 12–13 points, regular or medium.
- Metadata, provenance, reset, axes, and footer: 10–11 points, regular.
- Numeric usage values use monospaced digits. Token and cost values abbreviate only after preserving the full value in accessibility text.
- Respect system text scaling. Truncate only paths and source identifiers; wrap error and privacy explanations.

## Spacing and radii

- Base spacing unit: 4 points.
- Standard gaps: 4, 8, 12, 16, and 24 points. Avoid ad hoc spacing.
- Popover outer inset: 16 points. Settings content inset: 24 points.
- Compact control radius: 6 points. Segmented selection radius: 8 points. Surface radius: 12 points.
- Chart corner radius: 2 points for bars; line joins and caps are round.
- Hairlines are one physical pixel using semantic separators.
- Interactive targets are at least 28 × 28 points in the compact popover and 32 × 32 points in Settings, with descriptive accessibility labels.

## Icon inventory

Use SF Symbols for all code-native interface icons:

- Brand/menu bar: original SessionLens aperture-and-bars template mark.
- Refresh: `arrow.clockwise`.
- Settings: `gearshape`.
- Quit: `power`.
- General: `gearshape`.
- Providers: `externaldrive.connected.to.line.below` or `cylinder` when the former is unavailable.
- Menu Bar: `menubar.rectangle`.
- Notifications: `bell`.
- Privacy: `lock`.
- Privacy explanation: `shield`.
- Success/status: provider-colored circle plus textual status; never color alone.
- Warning/error: `exclamationmark.triangle` and a plain-language explanation.
- No copied SessionWatcher icons or decorative illustration set.

## Component families and states

- Provider selector: unavailable, available, selected, stale, refreshing, and failed. Selection uses an accent underline/fill and text weight; availability uses a dot plus an accessibility label.
- Quota summary: exact, estimated, unavailable, and stale. Estimated values must carry `Estimated`; unavailable values use an em dash and explanation.
- Metric rows: normalized value, included-plan cost, API-equivalent estimate, measured token count, locally calculated cost, and unavailable.
- Chart: populated, zero usage, insufficient history, and stale. Empty states retain axes/layout so the surface does not jump.
- Source row: detected/connected, not installed, permission denied, incompatible schema, command unavailable, and transient failure.
- Buttons: normal, hover, pressed, keyboard-focused, disabled, and in-progress. Destructive Clear History uses the native destructive role and confirmation.
- Notifications and bridge installation remain off until the user explicitly enables or confirms them.

## Chart styling

- Quota Remaining is a two-point selected-provider stroke with rounded joins, a subtle 8–12% accent fill, minimal horizontal guides, no point markers except on hover, and a restrained right-edge current-value emphasis. It charts remaining capacity, so the line falls as provider usage accumulates.
- Daily Usage is seven, thirty, or ninety compact bars. The selected range control is native and the current day uses full accent opacity; historical bars use 55–75% opacity.
- Use calendar-correct day boundaries in the current locale and timezone. Do not interpolate missing provider data into false precision.
- Axis labels use secondary text at 10 points. Gridlines use semantic separators at low opacity.
- Quota percentages cap visually at 100%, while accessibility and diagnostics can report a larger normalized value if a provider supplies one.
- Animation is limited to a short value transition after refresh; charts never continuously animate.

## Motion and reduced motion

- Default transitions are 160–220 ms native ease-in-out for provider changes, refreshed values, and chart-range changes.
- The refresh symbol may rotate once per refresh, but never spin indefinitely after a terminal result.
- Popover presentation, Settings presentation, confirmation sheets, hover, and focus use standard AppKit/SwiftUI behavior.
- With Reduce Motion enabled, replace chart morphing and symbol rotation with crossfades no longer than 120 ms.
- With Reduce Transparency enabled, use opaque semantic window backgrounds and preserve separator contrast.

## Intentional differences from SessionWatcher

- SessionLens is an original, free, local-first personal utility with no licensing, account, payment, upgrade, telemetry, or app-owned remote service surface. It fetches only public model-pricing metadata for API-equivalent estimates.
- It begins with OpenCode, Claude Code, and Codex and uses their documented/local aggregate interfaces rather than copying another product's integrations.
- Branding, aperture-and-bars mark, icon geometry, provider colors, layout proportions, copy, and implementation are original.
- Provider provenance and privacy boundaries are visible in Settings, while the popover remains compact.
- Exact quota is shown only when an exact local source supplies it. OpenCode totals are not misrepresented as a provider account quota without an explicit user mapping.
- Native system controls, accessibility semantics, reduced-motion behavior, dark appearance, failure isolation, and source freshness are first-class requirements.
