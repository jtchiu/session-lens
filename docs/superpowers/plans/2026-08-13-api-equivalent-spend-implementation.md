# API-equivalent subscription comparison Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show measured token consumption and a clearly estimated metered-API equivalent beside each provider's actual subscription/API spend.

**Architecture:** Add a pure pricing domain and estimator, a cached Models.dev catalog client, deterministic model resolution (including local Codex model detection), and a separate API-equivalent summary on `SpendSummary`. `AppModel` refreshes pricing independently of provider refresh, while the existing local usage ledger remains the source for consumption and actual provider spend. The SwiftUI table renders actual spend, API-equivalent spend, and tokens together.

**Tech Stack:** Swift 6, macOS 14, SwiftUI, Foundation `URLSession`, Core Data's programmatic model, Swift Testing, existing `scripts/test.sh` and app packaging scripts.

## Global Constraints

- The API-equivalent value is hypothetical and must never replace provider-reported actual spend or fabricate Codex API dollars.
- The only network request is a fixed HTTPS public pricing-catalog request; prompts, transcripts, usage records, credentials, account identity, and project paths never leave the Mac.
- Pricing fetches have an eight-second timeout, a 24-hour refresh TTL, atomic cache replacement, and cached/offline provenance.
- Missing or unknown model rates produce unavailable/estimated states, never `$0.00`.
- Codex model resolution reads only its documented local model setting and does not read conversation or project content.
- Preserve existing `SpendValue.costUSD`, combined actual-spend semantics, provider privacy allowlists, macOS 14 support, and all existing tests.
- Run focused tests through `zsh scripts/test.sh --filter ...`; run the full suite and bundle verifier before completion.

---

## File map

Create these focused units:

- `Sources/SessionLensCore/Domain/ApiEquivalentModels.swift` — pricing rates, coverage, and API-equivalent summary value types.
- `Sources/SessionLensCore/Domain/ApiEquivalentEstimator.swift` — pure token-to-cost arithmetic and fallback blending.
- `Sources/SessionLensCore/Pricing/PricingCatalogClient.swift` — injected HTTP transport, TTL, ETag, and cache behavior.
- `Sources/SessionLensCore/Pricing/PricingCatalogModels.swift` — narrow Models.dev decoder and normalized catalog.
- `Sources/SessionLensCore/Pricing/ModelRateResolver.swift` — provider/model normalization and resolution order.
- `Sources/SessionLensCore/Pricing/CodexModelDetector.swift` — local Codex model-setting reader.
- `Sources/SessionLensCore/Domain/ApiEquivalentSummaryBuilder.swift` — period aggregation using existing spend totals and resolved rates.
- `Tests/SessionLensCoreTests/Domain/ApiEquivalentEstimatorTests.swift` — arithmetic and provenance tests.
- `Tests/SessionLensCoreTests/Pricing/PricingCatalogClientTests.swift` — decoder, cache, TTL, transport, and stale fallback tests.
- `Tests/SessionLensCoreTests/Pricing/ModelRateResolverTests.swift` — exact, alias, latest, Codex, and unknown resolution tests.

Modify these existing units:

- `Sources/SessionLensCore/Domain/SpendModels.swift` and `SpendSummaryLoader.swift` — carry the separate API-equivalent summary.
- `Sources/SessionLensCore/Persistence/PersistenceModels.swift` and `SnapshotRepository.swift` — persist normalized model breakdowns for future resolution without storing raw provider payloads.
- `Sources/SessionLens/AppModel.swift` — inject pricing service, hydrate/publish pricing state, and recompute summaries without delaying provider refresh.
- `Sources/SessionLens/Views/SpendSummaryView.swift` and `Sources/SessionLensCore/Domain/SpendFormatting.swift` — render actual spend, API-equivalent spend, token totals, and accessible provenance.
- `Sources/SessionLens/PreviewFixtures.swift` — supply a deterministic pricing catalog/summary for visual previews.
- `Sources/SessionLens/Views/SettingsView.swift`, `README.md`, `docs/design/sessionlens-design-inventory.md`, and the prior provider-spend spec — document the public pricing fetch and local-only usage boundary.
- `Tests/SessionLensCoreTests/Domain/SpendSummaryLoaderTests.swift`, `SpendFormattingTests.swift`, `SnapshotRepositoryTests.swift`, and `PrivacyBoundaryTests.swift` — cover integration, persistence, formatting, and privacy changes.

---

### Task 1: Add pure pricing and API-equivalent domain types

**Files:**
- Create: `Sources/SessionLensCore/Domain/ApiEquivalentModels.swift`
- Create: `Sources/SessionLensCore/Domain/ApiEquivalentEstimator.swift`
- Create: `Tests/SessionLensCoreTests/Domain/ApiEquivalentEstimatorTests.swift`

**Interfaces:**
- `PricingRate(inputPerMillion: Double?, outputPerMillion: Double?, reasoningPerMillion: Double?, cacheReadPerMillion: Double?, cacheWritePerMillion: Double?)` normalizes only finite non-negative values.
- `PricingCoverage` cases are `.modelAttributed`, `.latestKnownModel`, `.detectedProviderModel`, `.catalogStale`, and `.unavailable`.
- `ApiEquivalentValue(costUSD: Double?, tokens: Int?, coverage: PricingCoverage, modelID: String?, ratesAsOf: Date?)` is Codable/Hashable/Sendable and preserves nil when unpriced.
- `ApiEquivalentPeriods(week: ApiEquivalentValue, month: ApiEquivalentValue, retained: ApiEquivalentValue)` and `ApiEquivalentSummary(providers: [ProviderID: ApiEquivalentPeriods], combined: ApiEquivalentPeriods, catalogState: PricingCatalogState)` mirror existing spend periods.
- `ApiEquivalentEstimator.price(tokens: TokenBreakdown, rate: PricingRate, coverage: PricingCoverage, modelID: String?, ratesAsOf: Date?) -> ApiEquivalentValue` prices categorized tokens.
- `ApiEquivalentEstimator.priceUncategorized(tokens: Int, rate: PricingRate, coverage: PricingCoverage, modelID: String?, ratesAsOf: Date?) -> ApiEquivalentValue` uses the mean of valid input/output rates when categories are unavailable.

- [ ] **Step 1: Write failing arithmetic and provenance tests**

```swift
@Test
func pricesTokenCategoriesAtPerMillionRates() {
    let value = ApiEquivalentEstimator.price(
        tokens: TokenBreakdown(input: 1_000_000, output: 2_000_000,
                               reasoning: 500_000, cacheRead: 100_000,
                               cacheWrite: 50_000),
        rate: PricingRate(inputPerMillion: 1, outputPerMillion: 2,
                          reasoningPerMillion: 4, cacheReadPerMillion: 0.1,
                          cacheWritePerMillion: 0.5),
        coverage: .modelAttributed,
        modelID: "gpt-test",
        ratesAsOf: nil
    )

    #expect(abs((value.costUSD ?? 0) - 7.035) < 0.000_001)
    #expect(value.tokens == 3_650_000)
    #expect(value.coverage == .modelAttributed)
}

@Test
func uncategorizedTokensUseExplicitMeanFallbackAndNeverBecomeZero() {
    let value = ApiEquivalentEstimator.priceUncategorized(
        tokens: 1_000_000,
        rate: PricingRate(inputPerMillion: 1, outputPerMillion: 3),
        coverage: .detectedProviderModel,
        modelID: "codex-model",
        ratesAsOf: nil
    )

    #expect(value.costUSD == 2)
    #expect(value.coverage == .detectedProviderModel)
}
```

- [ ] **Step 2: Run the focused test to verify it fails**

Run: `zsh scripts/test.sh --filter ApiEquivalentEstimatorTests`

Expected: FAIL because the new domain types and estimator do not exist.

- [ ] **Step 3: Implement normalized value types and pure arithmetic**

Use `Double.isFinite`, `max(0, value)`, and `Int.max`-safe token normalization. Sum only priced categories. If reasoning pricing is nil, use output pricing for reasoning; if a category has no rate, omit that category and return nil when no category can be priced. For uncategorized tokens, require both finite input and output rates and use `(input + output) / 2`.

- [ ] **Step 4: Run focused tests and add edge cases**

Run: `zsh scripts/test.sh --filter ApiEquivalentEstimatorTests`

Expected: PASS. Add tests for nil rates, stale coverage, negative/NaN normalization, zero tokens, and large-token arithmetic before moving on.

- [ ] **Step 5: Commit the domain unit**

```bash
git add Sources/SessionLensCore/Domain/ApiEquivalentModels.swift \
  Sources/SessionLensCore/Domain/ApiEquivalentEstimator.swift \
  Tests/SessionLensCoreTests/Domain/ApiEquivalentEstimatorTests.swift
git commit -m "feat: add API-equivalent pricing domain"
```

### Task 2: Implement the public pricing catalog client and cache

**Files:**
- Create: `Sources/SessionLensCore/Pricing/PricingCatalogModels.swift`
- Create: `Sources/SessionLensCore/Pricing/PricingCatalogClient.swift`
- Create: `Tests/SessionLensCoreTests/Pricing/PricingCatalogClientTests.swift`

**Interfaces:**
- `PricingCatalogModel(providerID: String, modelID: String, rate: PricingRate)` is the normalized lookup record. `PricingCatalog(models: [PricingCatalogModel], updatedAt: Date?, fetchedAt: Date)` is Codable/Hashable/Sendable and provides `model(providerID:modelID:)` lookup.
- `PricingCatalogSource` is a Codable/Hashable/Sendable enum with `.live`, `.cached`, and `.unavailable`.
- `PricingCatalogState` is a Codable/Hashable/Sendable struct containing `source: PricingCatalogSource`, optional `catalog`, and an optional user-safe message; expose `ratesAsOf` as a computed property.
- `PricingCatalogTransport` is `Sendable` with `func fetch(ifNoneMatch: String?) async throws -> PricingCatalogHTTPResponse`.
- `PricingCatalogHTTPResponse(statusCode: Int, data: Data, etag: String?, lastModified: String?)` is Sendable.
- `PricingCatalogClient` is an actor initialized with `cacheURL: URL`, `transport: any PricingCatalogTransport`, `now: @Sendable () -> Date`, and `ttl: TimeInterval = 86_400`.
- `PricingCatalogClient.state(now:) async -> PricingCatalogState` loads cache without network.
- `PricingCatalogClient.refreshIfNeeded(now:) async -> PricingCatalogState` returns valid cache immediately when fresh, otherwise performs the bounded fetch and atomically writes a successful catalog.

- [ ] **Step 1: Write failing fixture, cache, TTL, and transport tests**

Define `PricingFixtures.catalogJSON`, `PricingFixtures.catalog`, and an actor `FakePricingTransport` in the test file. Test JSON containing two providers, a model with input/output/cache rates, an invalid negative entry, and unknown fields. Verify fresh cache avoids transport, stale cache sends its ETag, a `304` keeps the cached catalog, non-2xx/timeout/invalid JSON leaves the old cache intact, and no-cache failure returns `.unavailable`.

```swift
@Test
func staleCacheUsesConditionalFetchAndKeepsCatalogOnFailure() async throws {
    let transport = FakePricingTransport(
        response: .init(statusCode: 503, data: Data(), etag: nil, lastModified: nil)
    )
    let cacheURL = try TestCacheFile.write(PricingFixtures.catalogJSON)
    let client = PricingCatalogClient(
        cacheURL: cacheURL,
        transport: transport,
        now: { PricingFixtures.day(2) },
        ttl: 86_400
    )

    let state = await client.refreshIfNeeded(now: PricingFixtures.day(2))

    #expect(state.catalog?.models.count == 2)
    #expect(state.source == .cached)
    #expect(await transport.lastETag() == "fixture-etag")
}
```

- [ ] **Step 2: Run focused tests to verify they fail**

Run: `zsh scripts/test.sh --filter PricingCatalogClientTests`

Expected: FAIL because the catalog decoder, transport, cache, and client are missing.

- [ ] **Step 3: Implement the narrow catalog decoder**

Decode Models.dev's provider/model dictionary into `PricingCatalogModel` values. Accept only provider ID, model ID, `cost.input`, `cost.output`, `cost.reasoning`, `cost.cache_read`, `cost.cache_write`, and catalog update metadata. Drop an entry only when every usable cost field is absent or invalid; ignore unrelated JSON fields.

- [ ] **Step 4: Implement conditional HTTP and atomic cache behavior**

Use `URLSession.shared.data(for:)` behind `PricingCatalogTransport`, set the fixed URL `https://models.dev/api.json`, request JSON, and enforce an eight-second timeout. Persist only normalized catalog data, source URL, fetched time, catalog time, ETag, and Last-Modified. Write a sibling temporary file and replace the cache atomically. Treat `304` as a successful cached refresh. Never include usage or credential data in the request.

- [ ] **Step 5: Run focused tests and commit**

Run: `zsh scripts/test.sh --filter PricingCatalogClientTests`

Expected: PASS with live network disabled in tests.

```bash
git add Sources/SessionLensCore/Pricing \
  Tests/SessionLensCoreTests/Pricing/PricingCatalogClientTests.swift
git commit -m "feat: fetch and cache public model pricing"
```

### Task 3: Resolve model rates and detect Codex's configured model

**Files:**
- Create: `Sources/SessionLensCore/Pricing/ModelRateResolver.swift`
- Create: `Sources/SessionLensCore/Pricing/CodexModelDetector.swift`
- Create: `Tests/SessionLensCoreTests/Pricing/ModelRateResolverTests.swift`
- Modify: `Tests/SessionLensCoreTests/Support/TestDoubles.swift` (add a deterministic file-reader fake if the existing doubles do not cover it)

**Interfaces:**
- `ResolvedModelRate` contains `modelID`, `rate`, and `coverage`.
- `ModelRateResolver.resolve(provider: ProviderID, providerID: String?, modelID: String?, latestModelID: String?, catalog: PricingCatalog, catalogIsStale: Bool) -> ResolvedModelRate?` follows exact, OpenCode alias, latest, then unavailable order.
- `CodexModelDetector.detect(configuration: String) -> String?` parses only a top-level `model = "..."` setting and rejects malformed/non-string values.
- `PricingFileSystem` is a Sendable protocol with `func readIfExists(_ url: URL) -> String?`; `FoundationPricingFileSystem` is the production implementation.
- `CodexModelDetector.live(homeDirectory: URL, fileSystem: any PricingFileSystem) -> String?` reads only `$HOME/.codex/config.toml` through the injected file-system seam.

- [ ] **Step 1: Write failing resolver and detection tests**

Cover exact `provider/model`, OpenCode configured `modelID`, latest-model fallback, stale coverage, unknown model, quoted Codex model, whitespace/comments, and missing/malformed config. Assert that detection never returns a project path or arbitrary TOML value.

- [ ] **Step 2: Run the focused test to verify it fails**

Run: `zsh scripts/test.sh --filter ModelRateResolverTests`

Expected: FAIL because the resolver and detector are missing.

- [ ] **Step 3: Implement deterministic resolution and minimal TOML parsing**

Normalize surrounding whitespace and provider/model separators without lowercasing case-sensitive model IDs. For Codex, try the exact configured provider first, then the documented `openai` catalog provider alias; do not fuzzy-match a model name. For Codex config, scan line-by-line for a top-level `model` assignment, strip a matching pair of quotes, and return nil for any other shape. Do not decode or retain the entire config.

- [ ] **Step 4: Run focused tests and commit**

Run: `zsh scripts/test.sh --filter ModelRateResolverTests`

Expected: PASS.

```bash
git add Sources/SessionLensCore/Pricing \
  Tests/SessionLensCoreTests/Pricing/ModelRateResolverTests.swift \
  Tests/SessionLensCoreTests/Support/TestDoubles.swift
git commit -m "feat: resolve model rates and detect Codex model"
```

### Task 4: Persist model metadata and build API-equivalent summaries

**Files:**
- Create: `Sources/SessionLensCore/Domain/ApiEquivalentSummaryBuilder.swift`
- Modify: `Sources/SessionLensCore/Domain/SpendModels.swift`
- Modify: `Sources/SessionLensCore/Domain/SpendSummaryLoader.swift`
- Modify: `Sources/SessionLensCore/Persistence/PersistenceModels.swift`
- Modify: `Sources/SessionLensCore/Persistence/SnapshotRepository.swift`
- Modify: `Tests/SessionLensCoreTests/Domain/SpendSummaryLoaderTests.swift`
- Modify: `Tests/SessionLensCoreTests/Persistence/SnapshotRepositoryTests.swift`
- Modify: `Tests/SessionLensCoreTests/Privacy/PrivacyBoundaryTests.swift`

**Interfaces:**
- `ApiEquivalentSummaryBuilder.make(summary: SpendSummary, snapshots: [ProviderID: ProviderSnapshot], catalog: PricingCatalog?, catalogState: PricingCatalogState, codexModelID: String?, now: Date, calendar: Calendar) -> ApiEquivalentSummary`.
- `SpendSummary` adds `public let apiEquivalent: ApiEquivalentSummary`, with an initializer defaulting to `.unavailable` and backward-compatible decoding when the key is absent.
- `SnapshotRecord.modelData` stores only encoded normalized `[ModelUsage]`; old records decode an empty list.
- `SnapshotRepository.latest(provider:)` round-trips `modelBreakdowns` and keeps the existing normalized-only privacy boundary.

- [ ] **Step 1: Write failing summary, persistence, and privacy tests**

Add a fixture catalog and assert that a Codex included-plan row keeps `costUSD == nil` in actual spend but receives a detected-model API-equivalent estimate, while a provider with an unknown model remains unavailable. Assert weekly/monthly/retained token totals are unchanged. Record/load a snapshot with model breakdowns and assert the round trip. Update the privacy property allowlist to include only `modelData` and assert no forbidden property names appear.

- [ ] **Step 2: Run focused tests to verify the new assertions fail**

Run: `zsh scripts/test.sh --filter SpendSummaryLoaderTests --filter SnapshotRepositoryTests --filter PrivacyBoundaryTests`

Expected: FAIL because `SpendSummary` has no API-equivalent property and model metadata is not persisted.

- [ ] **Step 3: Add backward-compatible model metadata persistence**

Add optional `modelData` to the programmatic Core Data entity and managed object. Encode/decode `[ModelUsage]` with the existing JSON encoder/decoder. Do not persist raw provider payloads, model prompts, paths, or configuration contents. Keep the model optional so existing SQLite stores migrate automatically.

- [ ] **Step 4: Add the summary builder and loader wiring**

Use existing period token values as the consumption source. Use persisted/current model breakdowns to choose the latest model and category proportions; because the existing daily ledger has no per-model day key, price each period total with the resolved latest model and mark it as a fallback estimate. Use the detected Codex model when no Codex breakdown exists, pass catalog staleness into coverage, and sum only priced API-equivalent values. Keep actual combined dollars unchanged and make API-equivalent combined values separately estimated.

- [ ] **Step 5: Run focused tests and commit**

Run: `zsh scripts/test.sh --filter SpendSummaryLoaderTests --filter SnapshotRepositoryTests --filter PrivacyBoundaryTests`

Expected: PASS with old encoded summaries and old stores still readable.

```bash
git add Sources/SessionLensCore/Domain/ApiEquivalentSummaryBuilder.swift \
  Sources/SessionLensCore/Domain/SpendModels.swift \
  Sources/SessionLensCore/Domain/SpendSummaryLoader.swift \
  Sources/SessionLensCore/Persistence/PersistenceModels.swift \
  Sources/SessionLensCore/Persistence/SnapshotRepository.swift \
  Tests/SessionLensCoreTests/Domain/SpendSummaryLoaderTests.swift \
  Tests/SessionLensCoreTests/Persistence/SnapshotRepositoryTests.swift \
  Tests/SessionLensCoreTests/Privacy/PrivacyBoundaryTests.swift
git commit -m "feat: add API-equivalent summary aggregation"
```

### Task 5: Integrate pricing refresh into AppModel without blocking providers

**Files:**
- Modify: `Sources/SessionLens/AppModel.swift`
- Modify: `Sources/SessionLens/PreviewFixtures.swift`
- Modify: `Sources/SessionLensCore/Domain/SpendSummaryLoader.swift` if the production loader signature needs a defaulted pricing context
- Add or modify: `Tests/SessionLensCoreTests/Support/TestDoubles.swift` for a fake catalog client, if needed

**Interfaces:**
- Inject `PricingCatalogClient` into `AppModel` with a live default and a deterministic preview initializer. Derive the cache URL from the same SessionLens Application Support directory used by `SnapshotRepository`.
- Publish `pricingState: PricingCatalogState` only; do not publish raw HTTP errors or configuration text.
- `AppModel.refreshPricingIfNeeded(now:) async` updates pricing state and recomputes `spendSummary` without changing provider snapshots.

- [ ] **Step 1: Extend the pricing-client and loader tests for the integration seam**

Use the fake pricing transport from Task 2 and the summary builder from Task 4. Assert that a timeout returns an unavailable/cached state without throwing and that a later catalog result recomputes API-equivalent values while actual spend and provider snapshots remain unchanged. The executable target is not added as a test-target dependency; the AppModel wiring is verified by the packaged-app smoke check in Task 7.

- [ ] **Step 2: Run focused tests to verify the new seam fails**

Run: `zsh scripts/test.sh --filter PricingCatalogClientTests --filter SpendSummaryLoaderTests`

Expected: FAIL because the client-to-summary seam and AppModel pricing state do not exist yet.

- [ ] **Step 3: Wire startup and refresh**

Load persisted snapshots/model metadata and the existing spend summary first. Start provider refresh as today. Start `refreshPricingIfNeeded` independently with a bounded task; use the last catalog immediately and recompute after the task completes. Do not make the 8-second provider refresh wait for the network catalog. Run pricing refresh on launch and rely on the 24-hour client TTL for later timer ticks.

- [ ] **Step 4: Update visual fixtures and run focused tests**

Give preview fixtures a local catalog containing the fixture OpenCode/Claude/Codex model IDs so the preview shows actual spend, API-equivalent spend, and tokens deterministically. Run the focused integration/loader tests and verify the provider snapshot values remain unchanged.

- [ ] **Step 5: Commit the lifecycle integration**

```bash
git add Sources/SessionLens/AppModel.swift Sources/SessionLens/PreviewFixtures.swift \
  Tests/SessionLensCoreTests/Support/TestDoubles.swift
git commit -m "feat: refresh pricing independently from provider usage"
```

### Task 6: Render the comparison and update privacy copy

**Files:**
- Modify: `Sources/SessionLens/Views/SpendSummaryView.swift`
- Modify: `Sources/SessionLensCore/Domain/SpendFormatting.swift`
- Modify: `Sources/SessionLens/Views/SettingsView.swift`
- Modify: `Tests/SessionLensCoreTests/Domain/SpendFormattingTests.swift`
- Modify: `README.md`
- Modify: `docs/design/sessionlens-design-inventory.md`
- Modify: `docs/superpowers/specs/2026-08-13-provider-spend-design.md`

**Interfaces:**
- Add `SpendFormatting.apiEquivalentText(_:)`, `SpendFormatting.coverageText(_:)`, and a combined accessibility-label helper that names actual spend, API-equivalent spend, token count, and rates-as-of.
- `SpendSummaryView` consumes `summary.apiEquivalent` and `model.pricingState` (or a status passed from `PopoverView`) without making network calls.

- [ ] **Step 1: Write failing formatting assertions**

```swift
@Test
func formatsIncludedPlanAndApiEquivalentSeparately() {
    let value = ApiEquivalentValue(
        costUSD: 12.4,
        tokens: 3_400_000,
        coverage: .detectedProviderModel,
        modelID: "codex-model",
        ratesAsOf: nil
    )

    #expect(SpendFormatting.apiEquivalentText(value) == "API eq. ~$12.40")
    #expect(SpendFormatting.coverageText(value) == "Detected model estimate")
}
```

- [ ] **Step 2: Run the focused formatting test to verify it fails**

Run: `zsh scripts/test.sh --filter SpendFormattingTests`

Expected: FAIL because the API-equivalent formatting helpers do not exist.

- [ ] **Step 3: Implement compact three-line period cells**

Keep the existing actual spend line (`Included with plan`, exact, estimated, or `—`). Add the API-equivalent line and token-count line, preserving the current week/month/total columns. Use subdued secondary styling for provenance and status. Do not reuse `tokens/$` for the hypothetical value.

- [ ] **Step 4: Add accessible labels and pricing status copy**

Make each cell announce actual spend, API-equivalent estimate, token count, coverage, and rates-as-of. Add a compact live/cached/unavailable status under the section title. Update Privacy settings and README to state that only public pricing metadata is fetched and usage/credentials remain local. Replace the old “does not call a network API” claim with the precise pricing-only exception.

- [ ] **Step 5: Run formatting tests and commit**

Run: `zsh scripts/test.sh --filter SpendFormattingTests`

Expected: PASS, including existing actual-spend formatting tests.

```bash
git add Sources/SessionLens/Views/SpendSummaryView.swift \
  Sources/SessionLensCore/Domain/SpendFormatting.swift \
  Sources/SessionLens/Views/SettingsView.swift \
  Tests/SessionLensCoreTests/Domain/SpendFormattingTests.swift \
  README.md docs/design/sessionlens-design-inventory.md \
  docs/superpowers/specs/2026-08-13-provider-spend-design.md
git commit -m "feat: show API-equivalent usage comparison"
```

### Task 7: Full verification and packaged-app smoke check

**Files:**
- Modify: `docs/qa/verification-report.md` with the new local evidence and pricing-cache behavior.
- No implementation files should change during this task unless a verification-only defect is found.

- [ ] **Step 1: Run the complete test suite**

Run: `zsh scripts/test.sh`

Expected: all existing and new tests pass with zero failures. If a test fails, fix the smallest in-scope defect, rerun the focused test, and rerun the full suite.

- [ ] **Step 2: Run static and privacy checks**

Run: `git diff --check`, `rg -n "https?://" Sources/SessionLensCore Sources/SessionLens`, and `zsh scripts/test.sh --filter PrivacyBoundaryTests`. Confirm the only production URL is `https://models.dev/api.json`, the HTTP transport is injectable, and no persisted property contains a forbidden privacy fragment.

- [ ] **Step 3: Package and verify the app**

Run: `zsh scripts/package_app.sh` then `zsh scripts/verify_bundle.sh dist/SessionLens.app`.

Expected: the signed bundle verifier passes and contains the existing app/helper resources.

- [ ] **Step 4: Perform a local smoke check**

Launch the fresh `dist/SessionLens.app`, open the popover, and verify each provider row shows tokens plus actual spend and API-equivalent status. Temporarily make the pricing cache unavailable and verify provider usage still refreshes and the UI says `API equivalent unavailable`. Restore the cache/network and verify the catalog date/status changes without changing actual provider spend.

- [ ] **Step 5: Record evidence and commit**

```bash
git add docs/qa/verification-report.md
git commit -m "test: verify API-equivalent comparison"
```
