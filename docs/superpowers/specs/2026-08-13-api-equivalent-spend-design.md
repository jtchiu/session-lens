# API-equivalent subscription comparison

**Status:** Approved design (2026-08-13)

## Goal

Make the existing **Spend & effectiveness** section answer two separate
questions for OpenCode, Claude Code, and Codex:

1. How many tokens were consumed this week, this month, and across retained
   history?
2. What would that consumption have cost if it had been billed through a
   metered API instead of the provider's subscription or included plan?

The second number is explicitly hypothetical. It must never replace a
provider-reported charge or turn Codex's subscription usage into a fabricated
bill.

## Context and constraints

The current summary already has weekly, monthly, and retained values with
provider-reported spend and token totals. Codex deliberately reports
`Included with plan` because its account endpoint does not expose an API
dollar amount. OpenCode exposes model-attributed aggregate rows, while Claude
provides session/model token metadata and cumulative samples. Codex currently
reports aggregate daily tokens without a model identifier.

The user approved automatic pricing retrieval and accepted an estimate when
historical model attribution is incomplete. Codex's model should be detected
from its local configuration when the account response does not provide one.

SessionLens remains a local usage reader. The only new network traffic is a
public pricing-catalog request; prompts, transcripts, usage records,
credentials, account identity, and project paths must never be sent.

## Recommended approach: hybrid estimator

Keep the existing trusted spend/consumption ledger and add three focused
components:

1. **Pricing catalog client** — fetch and cache the public Models.dev JSON
   catalog. OpenCode documents that its model catalog is built from Models.dev;
   the catalog contains per-million-token input, output, reasoning,
   cache-read, and cache-write rates. The client uses `URLSession`, an eight
   second timeout, ETag/Last-Modified when available, and a 24-hour refresh
   TTL. A valid cached catalog remains usable when the network is unavailable
   and is labeled with its age.
2. **Model/rate resolver and estimator** — normalize observed provider/model
   identifiers, resolve exact catalog entries when possible, and calculate an
   API-equivalent value from token categories. If a retained aggregate has no
   model attribution, use the latest model observed for that provider. If
   Codex has no model in its usage response, detect the configured Codex model
   locally and use it as the provider's latest model. Every fallback is
   represented in provenance and never presented as an exact provider charge.
3. **Comparison view model** — keep actual spend and API-equivalent spend as
   separate fields, with token consumption shown in the same period cells.
   This avoids changing the meaning of `SpendValue.costUSD` or the existing
   combined actual-spend total.

The design intentionally does not attempt a full historical per-model billing
ledger. New model-attributed observations may be retained as lightweight
metadata for better future estimates, but old aggregate history is estimated
using the latest known model as the user approved.

## Data model

Add domain types separate from `SpendValue`:

- `PricingCoverage`: `modelAttributed`, `latestKnownModel`,
  `detectedProviderModel`, `catalogStale`, and `unavailable`.
- `ApiEquivalentValue`: optional `costUSD`, optional `tokens`, coverage,
  optional resolved model identifier, and the catalog `ratesAsOf` timestamp.
- `ApiEquivalentPeriods`, `ProviderApiEquivalentSummary`, and
  `ApiEquivalentSummary`, mirroring the existing week/month/retained shape.

`SpendSummary` gains an `apiEquivalent` property. Existing provider cost,
provenance, and combined-dollar behavior remain unchanged. Codex's actual
value continues to be `Included with plan`; its API-equivalent value is shown
on a separate line and is always marked estimated.

The catalog decoder accepts only the pricing fields required for calculation:
provider ID, model ID, input, output, reasoning, cache-read, cache-write, and
the catalog update timestamp. Unknown fields are ignored. Rates are required
to be finite and non-negative; malformed entries are discarded individually.

## Cost calculation

For a model-attributed `TokenBreakdown`, calculate:

```text
input       / 1,000,000 * inputRate
output      / 1,000,000 * outputRate
reasoning   / 1,000,000 * reasoningRate (or outputRate when no separate rate)
cacheRead   / 1,000,000 * cacheReadRate
cacheWrite  / 1,000,000 * cacheWriteRate
```

Missing token categories are not invented. A model with no usable rate is
unpriced and contributes no false zero to the combined API-equivalent total.

For aggregate totals that contain only an uncategorized token count, use the
latest resolved model's documented input/output blend derived from the latest
available token breakdown for that provider. If no breakdown exists, use the
model's simple mean of input and output rates as a clearly labeled fallback.
If no finite input/output rates exist, the period is unavailable. This keeps
Codex useful while making the approximation visible rather than implying that
all aggregate tokens were input or output tokens.

The estimator sums only API-equivalent values with usable rates. A combined
period is unavailable when no provider has a usable estimate; it is marked
estimated when any included provider used a fallback or the catalog is stale.

## Pricing fetch and cache

`PricingCatalogClient` is an actor with a test-injected transport. It requests
only the fixed HTTPS Models.dev endpoint. The request contains no provider
usage, model history, account identifier, API key, or user input.

The cache is stored under SessionLens's local Application Support directory,
separately from usage history, with restrictive file permissions. The cached
record contains the decoded pricing entries, source URL, fetched timestamp,
catalog timestamp, and validators. A successful response replaces the cache
atomically. A timeout, non-success status, invalid JSON response, or invalid
rate leaves the previous cache untouched and exposes a non-blocking warning
state. If there is no valid cache, the comparison shows `API equivalent
unavailable` while actual local/provider spend remains usable.

Pricing refresh runs independently of provider refresh and never delays the
provider timeout path. The app may use a cached catalog immediately and
refresh it in the background when the TTL has elapsed. The comparison labels
the catalog as live, cached, or unavailable and includes its rates-as-of date.

## Model resolution

Resolution order is deterministic:

1. exact normalized provider/model ID from an observed model breakdown;
2. configured `modelID` alias for an OpenCode model, when present;
3. latest observed model for that provider retained by SessionLens;
4. Codex's locally detected configured model;
5. unavailable, with the unresolved identifier shown only as a redacted
   diagnostic if it is safe to display.

Local Codex model detection reads only the documented model setting, never
conversation or project content. A missing or malformed setting does not
prevent Codex usage refresh; it only makes the API-equivalent line
unavailable until another model identifier is observed.

## User interface

Keep the existing compact provider/period table, but make each period cell
show three distinct lines:

```text
Included with plan       actual provider spend
API eq. ~$12.40          hypothetical metered API cost
3.4M tokens              measured consumption
```

For metered providers, the first line remains their actual exact/estimated
charge and the second line is the API-equivalent estimate; they may differ.
For unknown data, use `—` or `API equivalent unavailable`, never `$0.00`.
The combined row keeps the current actual-spend semantics and adds a separate
combined API-equivalent line.

The section subtitle/status exposes `Live pricing`, `Cached pricing`, or
`Pricing unavailable`, plus the catalog rates-as-of date. Accessibility labels
name actual spend, API-equivalent spend, token count, and the estimate
coverage. The existing `tokens/$` line remains available for actual spend
where it is mathematically valid; it is not reused for API-equivalent values.

The Privacy/diagnostics settings copy is updated to explain that SessionLens
fetches public model pricing only, sends no usage data, and can operate with a
cached catalog or with the comparison unavailable.

## Error and privacy behavior

- Pricing fetch failures are non-fatal and never replace a good provider
  snapshot with stale pricing state.
- Unknown models, missing rates, and stale catalogs are visible in provenance.
- The app never logs raw pricing responses, request headers, credentials, or
  local configuration contents.
- Clear History removes usage history and spend samples but does not need to
  delete the public pricing cache; a separate cache reset is unnecessary for
  the comparison feature.
- No automatic provider billing, subscription-price inference, or account
  authentication is introduced.

## Verification plan

Core tests must cover:

1. catalog decoding, non-negative rate normalization, malformed-entry
   rejection, cache round trips, validators, TTL behavior, and stale fallback;
2. exact model resolution, OpenCode aliases, latest-model fallback, Codex
   configuration detection, and unknown-model behavior;
3. category-based pricing, reasoning/output fallback, uncategorized blended
   estimates, missing-rate handling, provenance, and combined totals;
4. backward-compatible `SpendSummary` encoding/decoding and history loading;
5. formatting/accessibility text for included-plan actual spend plus API
   equivalent and token consumption;
6. privacy boundaries proving the pricing request is fixed public metadata and
   contains no usage or credential fields;
7. full existing provider, persistence, UI-model, package, and bundle
   verification commands.

Acceptance is met when a Codex subscription row can show measured weekly,
monthly, and retained tokens alongside a detected-model API-equivalent USD
estimate; actual `Included with plan` remains intact; cached/offline pricing
is explicit; and no usage or credentials leave the Mac.

