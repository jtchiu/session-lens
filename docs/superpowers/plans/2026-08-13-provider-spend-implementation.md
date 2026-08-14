# Provider Spend Comparison Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a local provider spend ledger that shows weekly, monthly, and retained-history API-token cost plus trustworthy tokens-per-dollar comparisons for OpenCode, Claude Code, and Codex.

**Architecture:** Keep calendar math and provenance in a pure `SessionLensCore` spend aggregator. OpenCode contributes exact daily buckets; Claude contributes hashed-session cumulative samples whose positive deltas become daily contributions; Codex remains token/quota-only with included-plan cost. Persist Claude samples in a privacy-reviewed Core Data entity, expose the computed summary through `AppModel`, and render a compact provider comparison section in the popover.

**Tech Stack:** Swift 5.9+, SwiftUI, Core Data with a code-defined model, Swift Testing, Swift Package Manager, macOS 14+.

## Global Constraints

- Use provider-reported cost fields only; do not fetch prices or infer subscription prices.
- Codex dollar cost remains **Included with plan** or unavailable; never display fabricated `$0`.
- Week and month use `Calendar.current` local calendar boundaries; total means locally retained history.
- Persist only normalized aggregate data and the one-way Claude session hash; never persist prompts, transcripts, paths, credentials, responses, or source content.
- Reject or clamp negative, NaN, and infinite costs/tokens; counter resets cannot create negative spend.
- Preserve exact, estimated, mixed, included-with-plan, and unavailable provenance in domain values and accessibility labels.
- Use the existing Swift Testing harness and run `scripts/test.sh` plus the bundle verifier before completion.

## File Map

### New files

- `Sources/SessionLensCore/Domain/SpendModels.swift` — spend provenance, samples, period values, provider summaries, and aggregate summary types.
- `Sources/SessionLensCore/Domain/SpendAggregator.swift` — pure local-calendar aggregation and cumulative-sample delta logic.
- `Sources/SessionLensCore/Domain/SpendSummaryLoader.swift` — assemble provider sources from persisted daily buckets/samples and retention settings.
- `Sources/SessionLens/Views/SpendSummaryView.swift` — compact provider/combined spend and effectiveness UI.
- `Tests/SessionLensCoreTests/Domain/SpendAggregatorTests.swift` — calendar, provenance, ratio, reset, and retention tests.
- `Tests/SessionLensCoreTests/Domain/SpendSummaryLoaderTests.swift` — source assembly and retention wiring tests.

### Modified files

- `Sources/SessionLensCore/Domain/UsageModels.swift` — optional normalized cost-sample metadata on `ProviderSnapshot`.
- `Sources/SessionLensCore/Providers/Claude/ClaudeStatusPayload.swift` — retain documented cumulative input/output token total separately from live context tokens.
- `Sources/SessionLensCore/Providers/Claude/ClaudeProvider.swift` — emit an estimated hashed-session spend sample.
- `Sources/SessionLensCore/Persistence/PersistenceModels.swift` — add the `SpendSampleRecord` entity and privacy-safe aggregate attributes.
- `Sources/SessionLensCore/Persistence/SnapshotRepository.swift` — persist/load spend samples, prune them by configured retention, and clear them with history.
- `Sources/SessionLens/AppModel.swift` — publish/load/reload `SpendSummary` on launch, refresh, settings retention changes, and clear-history.
- `Sources/SessionLens/Views/PopoverView.swift` — place `SpendSummaryView` in the scroll content.
- `Sources/SessionLens/PreviewFixtures.swift` — supply exact, estimated, and included-plan spend fixtures.
- `Tests/SessionLensCoreTests/Support/Fixtures.swift` — construct snapshots/cache samples for the new fields.
- `Tests/SessionLensCoreTests/Providers/ClaudeBridgeTests.swift` — verify cumulative token normalization and sample emission.
- `Tests/SessionLensCoreTests/Persistence/SnapshotRepositoryTests.swift` — verify sample round trips, pruning, and clearing.
- `Tests/SessionLensCoreTests/Privacy/PrivacyBoundaryTests.swift` — update the explicit persisted-property and normalized-cache allowlists.

---

### Task 1: Add pure spend domain models and aggregation

**Files:**
- Create: `Sources/SessionLensCore/Domain/SpendModels.swift`
- Create: `Sources/SessionLensCore/Domain/SpendAggregator.swift`
- Create: `Tests/SessionLensCoreTests/Domain/SpendAggregatorTests.swift`

**Interfaces:**
- `SpendProvenance`: `exact`, `estimated`, `mixed`, `includedWithPlan`, `unavailable`.
- `ProviderSpendSample`: `provider`, `observedAt`, optional `scopeID`, optional cumulative USD cost, optional cumulative token count, and provenance.
- `SpendSource`: provider, exact daily buckets, cumulative samples, cost provenance, and `includedWithPlan` flag.
- `SpendValue`: optional USD cost, optional token count, provenance, and computed optional `tokensPerDollar`.
- `ProviderSpendSummary`: provider plus `week`, `month`, and `retained` `SpendValue`s.
- `SpendSummary`: provider summaries, optional combined value for each period, and the retention-day count.
- `SpendAggregator.makeSummary(now:historyRetentionDays:sources:calendar:) -> SpendSummary`.

**Steps:**

- [ ] **Step 1: Write failing tests for exact daily aggregation.** Add a fixed UTC calendar and buckets spanning a Sunday/Monday week boundary and a month boundary. Assert that `makeSummary` puts each bucket in the correct local week/month/retained period, sums costs and tokens, and computes `tokensPerDollar` only for positive cost.

```swift
@Test
func aggregatesLocalWeekMonthAndRetainedTotals() {
    let summary = SpendAggregator.makeSummary(
        now: Fixtures.day(10),
        historyRetentionDays: 30,
        sources: [.daily(
            provider: .opencode,
            buckets: [
                UsageBucket(day: Fixtures.day(8), tokens: 100, costUSD: 1),
                UsageBucket(day: Fixtures.day(10), tokens: 300, costUSD: 3),
            ],
            provenance: .exact
        )],
        calendar: Fixtures.calendar
    )

    #expect(summary.providers[.opencode]?.week.costUSD == 3)
    #expect(summary.providers[.opencode]?.month.tokens == 400)
    #expect(summary.providers[.opencode]?.retained.tokensPerDollar == 100)
}
```

- [ ] **Step 2: Run the focused test and verify it fails.** Run `swift test --filter SpendAggregatorTests/aggregatesLocalWeekMonthAndRetainedTotals`. Expected: compile/test failure because the spend types and aggregator do not exist.
- [ ] **Step 3: Implement the minimum domain types and daily-bucket path.** Normalize finite non-negative values, derive local start-of-week/start-of-month ranges with the injected calendar, retain only the configured history window, and compute the ratio as `tokens / cost` only when both values are present and cost is greater than zero.
- [ ] **Step 4: Add failing tests for cumulative session deltas and provenance.** Cover duplicate samples (zero delta), a new scope, a lower counter, estimated-only values, exact+estimated mixed combined values, included-plan Codex, unavailable cost, and missing token totals.
- [ ] **Step 5: Run the new tests and verify the expected failures.** Run `swift test --filter SpendAggregatorTests`; failures should identify the unimplemented sample/provenance branches.
- [ ] **Step 6: Implement sample delta aggregation and combined rows.** Sort samples by scope/time, emit only positive cost/token deltas after the first baseline, assign each delta to its observation day, merge exact/estimated provenance, omit included-plan from dollar sums, and make combined tokens-per-dollar unavailable if any included dollar source lacks trustworthy tokens.
- [ ] **Step 7: Run the focused suite.** Run `swift test --filter SpendAggregatorTests`; all tests must pass.
- [ ] **Step 8: Commit the domain unit.** Run `git add Sources/SessionLensCore/Domain/SpendModels.swift Sources/SessionLensCore/Domain/SpendAggregator.swift Tests/SessionLensCoreTests/Domain/SpendAggregatorTests.swift` and commit with `feat: add provider spend aggregation`.

### Task 2: Normalize Claude cumulative samples without misusing context tokens

**Files:**
- Modify: `Sources/SessionLensCore/Domain/UsageModels.swift`
- Modify: `Sources/SessionLensCore/Providers/Claude/ClaudeStatusPayload.swift`
- Modify: `Sources/SessionLensCore/Providers/Claude/ClaudeBridgeStore.swift`
- Modify: `Sources/SessionLensCore/Providers/Claude/ClaudeProvider.swift`
- Modify: `Tests/SessionLensCoreTests/Support/Fixtures.swift`
- Modify: `Tests/SessionLensCoreTests/Providers/ClaudeBridgeTests.swift`
- Modify: `Tests/SessionLensCoreTests/Privacy/PrivacyBoundaryTests.swift`

**Interfaces:**
- Add optional `costSample: ProviderSpendSample?` to `ProviderSnapshot`, defaulting to `nil` so existing provider fixtures remain source-compatible.
- Add `reportedSessionTokenTotal: Int?` to `ClaudeNormalizedCache`; encode it as the allowlisted key `reportedSessionTokenTotal`.
- `ClaudeStatusPayload.ContextWindow` computes that field only from documented cumulative `total_input_tokens` and `total_output_tokens`; it must not use `current_usage` for this historical counter.
- `ClaudeProvider.snapshot` emits `.estimated` `ProviderSpendSample(provider: .claude, scopeID: cache.sessionHash, cumulativeCostUSD: cache.estimatedSessionCostUSD, cumulativeTokens: cache.reportedSessionTokenTotal)`.

**Steps:**

- [ ] **Step 1: Add failing normalization and provider tests.** Assert that fixture totals `15_500 + 1_200` become the reported session token total, current context tokens remain unchanged, absent totals produce `nil`, the provider emits the hashed scope and estimated cost, and live-context-only fixtures do not emit a token total.
- [ ] **Step 2: Run the focused Claude tests and verify failure.** Run `swift test --filter ClaudeBridgeTests`; expected failure is missing cache field/sample API.
- [ ] **Step 3: Implement the cache field and allowlisted decoding.** Add the optional property with a backwards-compatible decoding default, update `allowedKeys`, and calculate only finite non-negative cumulative totals.
- [ ] **Step 4: Implement snapshot sample emission.** Preserve existing quota/cost behavior and attach the sample only when Claude has a hashed session scope and at least one valid cumulative value.
- [ ] **Step 5: Update privacy fixtures and tests.** Keep the normalized JSON limited to the explicit aggregate allowlist; assert no sensitive field is introduced.
- [ ] **Step 6: Run Claude and privacy suites.** Run `swift test --filter ClaudeBridgeTests` and `swift test --filter PrivacyBoundaryTests`; all must pass.
- [ ] **Step 7: Commit the normalization unit.** Commit with `feat: expose normalized Claude spend samples`.

### Task 3: Persist and retain spend samples safely

**Files:**
- Modify: `Sources/SessionLensCore/Persistence/PersistenceModels.swift`
- Modify: `Sources/SessionLensCore/Persistence/SnapshotRepository.swift`
- Modify: `Tests/SessionLensCoreTests/Persistence/SnapshotRepositoryTests.swift`
- Modify: `Tests/SessionLensCoreTests/Privacy/PrivacyBoundaryTests.swift`

**Interfaces:**
- Add `SpendSampleRecord` with `key`, `providerRaw`, `observedAt`, optional `scopeID`, optional `cumulativeCostUSD`, optional `cumulativeTokens`, and `provenanceRaw`.
- Add optional `costSampleData` to `SnapshotRecord` so latest normalized snapshots preserve `ProviderSnapshot.costSample` as well as the dedicated sample ledger.
- `SnapshotRepository.record(_:)` persists `snapshot.costSample` idempotently using `provider:scopeID:observedAt` as the sample key while preserving normal snapshot/daily-bucket behavior.
- Add `SnapshotRepository.spendSamples() throws -> [ProviderSpendSample]` sorted by provider, scope, and observation time.
- Add `SnapshotRepository.spendSampleRecordCount() throws -> Int` for tests.
- `prune(now:historyRetentionDays:)` removes sample records older than the normalized retention cutoff; `clearHistory()` removes all sample records.

**Steps:**

- [ ] **Step 1: Write failing repository tests.** Record a Claude snapshot with two samples, assert round-trip values and idempotence for the same key, add an old/recent sample and assert configured pruning, then assert clear-history removes all samples.

```swift
@Test
func repositoryRoundTripsAndDeduplicatesSpendSamples() throws {
    let repository = try SnapshotRepository.inMemory()
    let snapshot = Fixtures.claudeSnapshot(
        sample: ProviderSpendSample(
            provider: .claude,
            observedAt: Fixtures.now,
            scopeID: "hashed-session",
            cumulativeCostUSD: 1.25,
            cumulativeTokens: 10_000,
            provenance: .estimated
        )
    )

    try repository.record(snapshot)
    try repository.record(snapshot)

    #expect(try repository.spendSampleRecordCount() == 1)
    #expect(try repository.spendSamples().first?.cumulativeCostUSD == 1.25)
}
```

- [ ] **Step 2: Run the focused repository tests and verify failure.** Run `swift test --filter SnapshotRepositoryTests`; expected failure is the missing entity/API.
- [ ] **Step 3: Add the code-defined Core Data entity.** Register `SpendSampleRecord` in `SessionLensPersistenceModel`, mark only aggregate fields optional where the domain permits absence, and keep its uniqueness constraint on `key`.
- [ ] **Step 4: Persist sample data in `record`.** Encode the snapshot's optional sample into `costSampleData`, insert/update the dedicated ledger record, decode both paths in `latest(provider:)`, reject corrupt spend provenance with `SnapshotRepositoryError`, and never store raw Claude status-line input.
- [ ] **Step 5: Implement loading, pruning, clearing, and count helpers.** Ensure the configured retention is clamped using the existing settings rules and applies to samples as well as daily history.
- [ ] **Step 6: Update the privacy allowlist.** Add only the new aggregate property names and assert forbidden fragments remain absent.
- [ ] **Step 7: Run repository and privacy tests.** Run `swift test --filter SnapshotRepositoryTests` and `swift test --filter PrivacyBoundaryTests`; all must pass.
- [ ] **Step 8: Commit the persistence unit.** Commit with `feat: persist provider spend samples`.

### Task 4: Publish spend summaries through AppModel

**Files:**
- Create: `Sources/SessionLensCore/Domain/SpendSummaryLoader.swift`
- Create: `Tests/SessionLensCoreTests/Domain/SpendSummaryLoaderTests.swift`
- Modify: `Sources/SessionLens/AppModel.swift`
- Modify: `Sources/SessionLens/PreviewFixtures.swift`
- Modify: `Tests/SessionLensCoreTests/App/MenuBarSummaryTests.swift` only if shared fixture construction requires it.

**Interfaces:**
- Add `@Published private(set) var spendSummary: SpendSummary` to `AppModel`.
- Add an initializer parameter `initialSpendSummary: SpendSummary = .empty`.
- Add a private `loadSpendSummary(repository:now:settings:snapshots:) -> SpendSummary` helper that loads all retained daily buckets and `repository.spendSamples()`, then calls `SpendAggregator.makeSummary`.
- `AppModel.live()` loads the initial summary before constructing the model.
- `refreshNow` reloads the summary after coordinator persistence and pruning; `applySettings` reloads after retention changes; `clearHistory` resets it to `.empty`.

**Steps:**

- [ ] **Step 1: Add a failing source-assembly test.** Add a core-facing `SpendSummaryLoader` helper that accepts repository-loaded daily buckets/samples and settings retention, then test that the exact OpenCode plus estimated Claude inputs produce provider and combined values. AppModel will call this helper rather than duplicating source assembly.
- [ ] **Step 2: Run the focused loader test and verify failure.** Run `swift test --filter SpendSummaryLoaderTests`; expected failure is the missing loader API.
- [ ] **Step 3: Implement summary state and repository loading.** Keep existing refresh serialization, load all provider daily buckets with `Date.distantPast...Date.distantFuture`, include `settings.historyRetentionDays`, and avoid clearing persisted spend when a provider refresh is unhealthy.
- [ ] **Step 4: Wire launch, refresh, settings, and clear-history paths.** Ensure the initial summary is present before the first popover appears and updates after successful coordinator persistence.
- [ ] **Step 5: Add exact/estimated/included preview summary values.** Make preview mode deterministic and independent of live provider binaries or the current date.
- [ ] **Step 6: Run the full core suite.** Run `scripts/test.sh`; all existing and new tests must pass.
- [ ] **Step 7: Commit the app-state unit.** Commit with `feat: publish provider spend summary`.

### Task 5: Render provider comparison and effectiveness UI

**Files:**
- Create: `Sources/SessionLens/Views/SpendSummaryView.swift`
- Modify: `Sources/SessionLens/Views/PopoverView.swift`
- Modify: `Sources/SessionLens/PreviewFixtures.swift`

**Interfaces:**
- `SpendSummaryView` accepts `summary: SpendSummary` and `providerOrder: [ProviderID]`.
- It renders a **Spend & effectiveness** heading, columns **This week**, **This month**, **Total retained**, a row per provider, and a **Combined** row.
- Cell copy is driven by `SpendValue.provenance`; use `—` for missing values, **Included with plan** for Codex plan cost, and a visibly marked estimate for Claude/mixed totals.

**Steps:**

- [ ] **Step 1: Add a deterministic formatting test or pure formatter tests.** Assert USD formatting, compact token formatting, ratio formatting, estimate/mixed labels, included-plan copy, and accessibility strings for all provenance branches. Keep formatting helpers outside the view when the existing target setup permits.
- [ ] **Step 2: Run the focused formatter test and verify failure.** Run its `swift test --filter` target; expected failure is missing formatter/UI data source.
- [ ] **Step 3: Implement `SpendSummaryView`.** Use existing SessionLens spacing/palette/typography, keep the grid compact at the existing 390-point popover width, make each provider-period cell accessible as one combined label, and avoid a new navigation surface.
- [ ] **Step 4: Place the view in `PopoverView`.** Pass `model.spendSummary` and `model.providerOrder` in the ready/stale scroll content near quota/token summaries.
- [ ] **Step 5: Add preview fixtures for OpenCode exact, Claude estimated, Codex included-plan, and mixed Combined states.** Verify both light and dark previews compile.
- [ ] **Step 6: Run `swift test` and the app build.** Use `scripts/test.sh` and the existing package/build command; fix SwiftUI compile or accessibility issues before continuing.
- [ ] **Step 7: Commit the UI unit.** Commit with `feat: show provider spend comparison`.

### Task 6: End-to-end verification and handoff

**Files:**
- Modify: `README.md` only if the existing feature list needs the spend comparison documented.
- Modify: `docs/qa/verification-report.md` with the new test/build evidence if that report is maintained for this release.

**Steps:**

- [ ] **Step 1: Run the complete test command.** Run `scripts/test.sh`; record the exact passing test count and confirm no privacy, persistence, provider, or UI compilation regressions.
- [ ] **Step 2: Package and verify the bundle.** Run `zsh scripts/package_app.sh`, then `zsh scripts/verify_bundle.sh dist/SessionLens.app`, and confirm the app bundle still contains the expected helpers/resources.
- [ ] **Step 3: Inspect the current worktree and diff.** Run `git diff --check`, `git status --short`, and review all spend-related changes for secrets, network calls, unbounded SQL, or fabricated Codex dollars.
- [ ] **Step 4: Perform a preview/manual UI pass.** Launch the preview or built app, inspect the spend section at the existing popover size in light and dark appearance, and verify provider rows, estimates, included-plan copy, em dashes, and accessibility labels.
- [ ] **Step 5: Update documentation evidence.** Document that weekly/monthly are local calendar periods and total is retained history; do not claim subscription-fee ROI or Codex API dollars.
- [ ] **Step 6: Commit verification/documentation changes.** Commit with `chore: verify provider spend comparison` only if the preceding checks are green.
- [ ] **Step 7: Audit the objective requirement-by-requirement.** Confirm exact OpenCode costs, estimated Claude costs, weekly/monthly/retained totals, provider and combined rows, trustworthy tokens-per-dollar gating, included-plan Codex handling, provenance preservation, tests, and privacy checks all have direct evidence before marking the goal complete.
