# Provider spend and effectiveness design

**Status:** Approved for implementation planning
**Date:** 2026-08-13
**Target:** SessionLens macOS app

## 1. Goal

Add a local, provider-by-provider view of cumulative API-token consumption and a hypothetical metered-API equivalent so the user can compare OpenCode, Claude Code, and Codex subscriptions at a glance.

The view must show:

- spend for the current local calendar week;
- spend for the current local calendar month;
- total spend in the locally retained history;
- measured token consumption for each period;
- a separately labeled API-equivalent estimate for that consumption;
- a combined total when at least one provider has dollar data;
- tokens delivered per dollar when the source exposes trustworthy cumulative token counts.

Provider-reported spend remains the actual-spend source of truth. The API-equivalent value is hypothetical: it uses a cached public pricing catalog and never replaces actual spend, infers a subscription fee, or fabricates a Codex provider charge when Codex reports usage as included with a plan.

## 2. Product behavior

### 2.1 Comparison rows

The popover adds a compact **Spend & effectiveness** section with one row for each configured provider and a **Combined** row. The columns are **This week**, **This month**, and **Total retained**.

Each period cell displays three lines: the provider-reported actual spend, a separate `API eq. ~$x` hypothetical metered cost, and the measured token count. A compact status under the section title identifies live, cached, or unavailable public pricing and its rates-as-of date. Accessibility labels include the actual amount, API-equivalent amount, token count, coverage, and rates-as-of. Provider labels carry actual-spend provenance:

- OpenCode: **Exact** when sourced from its local aggregate database;
- Claude Code: **Estimated** when sourced from its status-line cost total;
- Combined: **Includes estimate** when exact and estimated amounts are mixed;
- Codex: **Included with plan** rather than `$0`.

If a provider has no usable actual cost data, the first line displays an em dash and a short reason such as **Unavailable** or **Included with plan**. If the model rate is unknown or unavailable, the API-equivalent line says **API equivalent unavailable**; it never displays `$0.00` as a substitute for missing rates.

The combined row sums only dollar-backed providers. Its tokens-per-dollar value is shown only when all included token totals are trustworthy; otherwise it shows an em dash with an explanation in the accessibility label.

### 2.2 Time semantics

Week and month use `Calendar.current` local calendar boundaries, not rolling seven- or 30-day windows. The current day is included through the latest observation. **Total retained** means all spend records still present after the configured history-retention policy; the label makes that boundary explicit.

All amounts are clamped to finite, non-negative values before aggregation. A counter reset or a lower cumulative sample never creates negative spend.

### 2.3 Codex limitation

Codex currently exposes subscription usage and no five-hour dollar-priced API budget. The spend section therefore keeps **Included with plan** for actual dollar spend while showing measured tokens and, when the configured local Codex model resolves to a public rate, a clearly labeled detected-model API-equivalent estimate. This estimate is not a Codex bill and never changes the actual-spend value.

## 3. Data model and flow

### 3.1 Normalized domain types

Add provider-neutral types in `SessionLensCore`:

- `SpendProvenance`: exact, estimated, mixed, included-with-plan, or unavailable;
- `SpendAmount`: optional USD value, provenance, cumulative token count, and optional tokens-per-dollar;
- `ProviderSpendSummary`: week, month, and retained totals for one provider;
- `SpendSummary`: provider summaries plus the combined summary.

The aggregation API is pure and accepts normalized daily cost buckets plus cumulative provider samples. This keeps calendar math, provenance merging, reset handling, and formatting out of SwiftUI.

The API-equivalent summary is computed separately from actual spend. It consumes normalized token totals and model metadata, resolves rates from the fixed public Models.dev catalog, and marks latest-model, detected-model, stale-catalog, and unavailable fallbacks explicitly.

### 3.2 Exact daily aggregates

OpenCode continues to use its existing read-only SQLite aggregate query. Its daily `UsageBucket` values are exact local aggregates and provide both cost and token totals for all three periods.

Codex daily usage remains token-only. Its cost display is preserved as included-with-plan or unavailable.

### 3.3 Cumulative session samples

Claude's status line reports a cumulative session cost. To make that cost cumulative across app refreshes without double-counting, the normalized Claude cache and provider snapshot expose:

- the existing one-way session hash as a scope identifier;
- the reported cumulative cost;
- a reported cumulative token total only when the status line provides total input/output token counters.

Successful Claude samples are persisted with provider, observation time, hashed scope, cumulative cost, cumulative tokens when present, and estimated provenance. The aggregator sorts samples per scope, converts positive differences into daily contributions, and starts a new baseline when the scope changes or a counter decreases. Live context-window tokens are not differenced into historical usage.

### 3.4 Local persistence

Add a code-defined Core Data `SpendSampleRecord` entity with a uniqueness key based on provider, hashed scope, and observation timestamp. It stores no prompt, transcript, path, model response, or credential data.

Extend `SnapshotPersisting` with the smallest APIs needed to record samples, load spend inputs for a date range, and clear/prune spend history. Spend samples are pruned using `historyRetentionDays`; no spend total claims to include data older than the retained records.

On launch, `AppModel` loads the persisted spend inputs and computes the initial `SpendSummary`. After each successful refresh it records normalized samples, reloads the summary, and publishes it. Clearing history removes spend samples along with existing aggregate history.

## 4. UI placement and interaction

Create `SpendSummaryView` in the existing popover scroll content, near the quota and token summaries so the values are visible without navigating to Settings. The view uses the existing palette, spacing, typography, and compact card/grid conventions.

The section is read-only. It does not introduce provider selectors, pricing settings, network controls, or subscription billing inputs. A background request to the fixed public pricing catalog is automatic and contains no usage or credential data. Existing provider tabs remain available for detailed token and quota inspection.

Accessibility labels include the provider, period, actual amount and provenance, API-equivalent amount and coverage, measured token count, rates-as-of date, and whether tokens-per-dollar is unavailable because the provider does not expose cumulative token totals.

Preview fixtures include exact OpenCode, estimated Claude, and included-plan Codex states so light/dark previews exercise every provenance branch.

## 5. Error and edge handling

- Missing or malformed records are skipped with an unavailable provenance rather than crashing the popover.
- A provider refresh failure does not erase its last persisted spend history.
- Duplicate samples are idempotent through the Core Data key and zero deltas.
- Counter resets and corrections cannot produce negative period totals.
- Infinite, NaN, or negative provider costs/tokens are rejected or clamped before persistence.
- A mixed combined total is clearly marked as including an estimate.
- The only new network request is the fixed HTTPS public pricing-catalog request. Usage records, prompts, credentials, account identity, and project paths remain local and are never included in it.

## 6. Verification

Add focused tests for:

1. local week/month boundaries and retained-history totals;
2. exact, estimated, mixed, included-plan, and unavailable provenance;
3. positive cumulative deltas, duplicate samples, session changes, and counter decreases;
4. tokens-per-dollar availability and division-by-zero behavior;
5. Core Data round trips, pruning, clearing, and privacy allowlists;
6. AppModel launch/refresh summary loading;
7. API-equivalent rates, provenance, pricing status, rates-as-of formatting, SwiftUI accessibility labels, and preview fixture rendering where the existing test harness supports it;
8. fixed-endpoint pricing privacy and cached/offline behavior.

Run the full existing test suite and the bundle verifier before claiming completion. No release or GitHub push is part of this feature unless separately requested.
