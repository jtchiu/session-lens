# Daily quota remaining chart Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make quota-remaining history meaningful by displaying one latest observation per calendar day over the selected 7d/30d/90d range.

**Architecture:** Preserve raw `SnapshotRecord` quota observations and alert semantics. Add a repository read path that reduces valid observations to the latest point per local calendar day, wire `AppModel` to request the selected range, and format the Swift Charts x-axis as dates.

**Tech Stack:** Swift 6, Foundation/Core Data, SwiftUI, Swift Charts, Swift Testing.

## Global Constraints

- Keep persisted `usedPercent` and notification evaluation unchanged; only presentation history is reduced to remaining capacity.
- Do not fabricate missing days, interpolate points, or change provider adapters/schema.
- Use the existing `UsageChartRange` values: 7, 30, and 90 days.
- Preserve the weekly-window-first fallback and last-good provider behavior.

---

### Task 1: Add daily quota-history reduction

**Files:**
- Modify: `Sources/SessionLensCore/Persistence/SnapshotRepository.swift` near `quotaHistory`
- Test: `Tests/SessionLensCoreTests/Persistence/SnapshotRepositoryTests.swift`

**Interfaces:**
- Consumes: normalized `SnapshotRecord` rows, provider, quota duration, date range, and a `Calendar`.
- Produces: `dailyQuotaHistory(provider:durationMinutes:range:calendar:) -> [QuotaHistoryPoint]`, sorted chronologically with at most one latest valid point per calendar day.

- [ ] **Step 1: Write the failing test** — Add `dailyQuotaHistoryUsesLatestObservationPerCalendarDay` with two same-day snapshots (20 and 36 used percent) and one next-day snapshot (44). Query a fixed Gregorian two-day range and assert percentages `[36, 44]`, timestamps from the latest rows, and selected provenance/reset metadata.
- [ ] **Step 2: Verify RED** — Run `swift test --filter SnapshotRepositoryTests.dailyQuotaHistoryUsesLatestObservationPerCalendarDay`; expect a compile failure because `dailyQuotaHistory` is absent.
- [ ] **Step 3: Implement the minimal read path** — Keep raw `quotaHistory` unchanged. Decode/filter the same records, sort by `observedAt`, group by `calendar.startOfDay(for:)`, replace each day with the later valid point, and return points sorted chronologically.
- [ ] **Step 4: Verify GREEN** — Rerun the focused test and expect PASS.
- [ ] **Step 5: Commit** — `git add Sources/SessionLensCore/Persistence/SnapshotRepository.swift Tests/SessionLensCoreTests/Persistence/SnapshotRepositoryTests.swift && git commit -m "feat: reduce quota history to daily points"`.

### Task 2: Wire the selected daily range into the app and chart

**Files:**
- Modify: `Sources/SessionLensCore/Settings/AppSettings.swift` to add `UsageChartRange.dateRange(endingAt:calendar:)`
- Modify: `Sources/SessionLens/AppModel.swift` in `setChartRange`, `applySettings`, `reloadQuotaHistory`, and `loadQuotaHistory`
- Modify: `Sources/SessionLens/Views/UsageCharts.swift` in `UsageRateChart`
- Test: `Tests/SessionLensCoreTests/Settings/AppSettingsTests.swift`

**Interfaces:**
- Consumes: `UsageChartRange`, current date/calendar, and repository `dailyQuotaHistory`.
- Produces: quota history loaded for the selected calendar-day range and a date-based x-axis.

- [ ] **Step 1: Write the failing range test** — Add an `AppSettingsTests` assertion for `UsageChartRange.sevenDays.dateRange(endingAt:calendar:)`, proving it starts at local start-of-day six days before the reference day and ends at the reference time, protecting against the current five-hour interval.
- [ ] **Step 2: Verify RED** — Run `swift test --filter AppSettingsTests`; expect the new assertion to fail against the five-hour behavior.
- [ ] **Step 3: Implement the wiring** — Use `chartRange` (and `settings.chartRange` during launch hydration) to compute the calendar-day range, call `dailyQuotaHistory` for the weekly window or fallback duration, reload immediately when the range changes, and replace `.dateTime.hour()` with `.dateTime.month().day()`. Keep the existing Daily Usage picker as the shared range control.
- [ ] **Step 4: Verify GREEN** — Run the focused tests, then `zsh scripts/test.sh`; expect all tests and the app target to pass.
- [ ] **Step 5: Commit** — `git add Sources/SessionLens/AppModel.swift Sources/SessionLens/Views/UsageCharts.swift Tests/SessionLensCoreTests/Settings/AppSettingsTests.swift && git commit -m "fix: chart quota remaining by day"`.

### Task 3: Package and verify the final behavior

**Files:**
- Verify: `README.md`, `docs/qa/verification-report.md`, `dist/SessionLens.app`

- [ ] **Step 1: Run static checks** — Run `git diff --check` and fail if `rg -n 'URLSession|import Network|NWConnection|CFHTTP' Sources` finds a match.
- [ ] **Step 2: Package and verify** — Run `zsh scripts/package_app.sh` followed by `zsh scripts/verify_bundle.sh dist/SessionLens.app`.
- [ ] **Step 3: Inspect final state** — Run `git status --short` and `git log --oneline -4`; confirm only the daily-chart behavior, tests, and approved spec/plan are present.
