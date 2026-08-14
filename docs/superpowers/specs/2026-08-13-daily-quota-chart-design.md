# Daily quota remaining chart

## Problem

The quota chart currently reads only the last five hours of refresh samples and labels its x-axis by hour. That makes a weekly quota look like a refresh-rate graph rather than a useful history of depletion.

## Approved design

Keep raw quota observations unchanged for alerts and persistence, but present the chart as one point per calendar day. For each provider and selected quota duration, use the latest valid observation in each day. The chart uses the existing `UsageChartRange` selector (7, 30, or 90 days), with the same range controlling both the daily usage and quota-remaining charts.

The chart remains expressed as remaining capacity (100 minus the persisted used percentage). Missing days stay missing; the UI must not invent zeroes or interpolate provider state. The x-axis uses calendar dates, not times of day. The chart title and accessibility value continue to describe remaining capacity.

## Data flow

`SnapshotRepository` will expose daily quota history from its existing normalized `SnapshotRecord` rows. It will select the latest valid point per calendar day within the requested date range, preserving reset identity, provenance, and remaining-capacity conversion. `AppModel` will load/reload the selected range and choose the weekly window first, falling back to the provider's first available window. No provider adapters or persisted schemas change.

## Interaction and states

Changing the range immediately reloads the quota history. A single point shows the existing insufficient-history message; no points show the existing empty state. Provider failures continue to use the last-good persisted history and do not fabricate daily values.

## Verification

- Add a repository regression test proving multiple same-day observations collapse to the latest point and points from adjacent days remain distinct.
- Add AppModel/UI-facing coverage proving the selected range is passed to history loading and the chart no longer requests a five-hour window.
- Run the full Swift test suite, package the app, verify the bundle, and run `git diff --check`.
