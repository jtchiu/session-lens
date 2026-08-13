# SessionLens Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and verify a free, local-only native SwiftUI macOS 14+ menu-bar app that reports OpenCode, Claude Code, and Codex aggregate usage, costs, quota windows, history, charts, and notifications without reading prompts or source code.

**Architecture:** A SwiftPM workspace contains a testable `SessionLensCore` library, the SwiftUI `SessionLens` menu-bar executable, and a narrow `SessionLensClaudeBridge` helper. Provider adapters normalize allowlisted local data into immutable snapshots, an actor coordinates refresh and persistence, and SwiftUI renders the same domain model without provider-specific parsing.

**Tech Stack:** Swift 6.3, SwiftUI, Swift Charts, programmatic Core Data, AppKit, ServiceManagement, UserNotifications, CryptoKit, Foundation `Process`, Swift Testing, Swift Package Manager, `/usr/bin/sqlite3`, ImageGen, and native macOS visual QA.

## Global Constraints

- Target macOS 14 Sonoma and later.
- Use the original product name **SessionLens** and original artwork; do not copy SessionWatcher branding, assets, or code.
- Ship as a free unsigned personal-use `.app`; do not add licensing, payments, analytics, cloud sync, or an app-owned backend.
- Do not intentionally inspect or persist prompts, responses, reasoning, source code, diffs, command output, credentials, project names, working-directory paths, or transcript contents.
- Codex access is limited to app-server initialization plus `account/rateLimits/read` and `account/usage/read`.
- OpenCode access is limited to a constant read-only query over aggregate `session` columns.
- Claude status-line ingestion uses an allowlisted normalized cache and preserves an existing user status-line command.
- Every uncertain metric carries exact, local aggregate, local budget, estimated, stale, or unavailable provenance.
- Missing or broken providers must not prevent other providers from refreshing.
- Follow test-driven development: observe each focused test fail before writing its production implementation.
- Commit after every task only when its focused and cumulative tests pass.

## File map

### Package and build

- `Package.swift` — products, macOS floor, targets, resources, and tests.
- `Resources/Info.plist` — app-bundle metadata and `LSUIElement`.
- `Sources/SessionLens/Resources/SessionLensIcon.png` — original runtime icon resource.
- `Sources/SessionLens/Resources/SessionLens.icns` — generated bundle icon.
- `scripts/package_app.sh` — release build and `.app` assembly.
- `scripts/build_icon.sh` — deterministic PNG-to-ICNS conversion.
- `README.md` — build, launch, privacy, provider setup, and verification instructions.

### Core domain and infrastructure

- `Sources/SessionLensCore/Domain/ProviderID.swift` — provider identity and display metadata.
- `Sources/SessionLensCore/Domain/UsageModels.swift` — snapshots, quota windows, tokens, buckets, provenance, and health.
- `Sources/SessionLensCore/Infrastructure/ExecutableLocator.swift` — bounded executable discovery.
- `Sources/SessionLensCore/Infrastructure/ProcessRunner.swift` — timeout-aware subprocess abstraction.
- `Sources/SessionLensCore/Persistence/PersistenceModels.swift` — programmatic Core Data aggregate records.
- `Sources/SessionLensCore/Persistence/SnapshotRepository.swift` — persistence, retention, and history clearing.

### Provider adapters

- `Sources/SessionLensCore/Providers/UsageProvider.swift` — adapter protocol.
- `Sources/SessionLensCore/Providers/OpenCode/OpenCodeProvider.swift` — fixed SQLite query and normalization.
- `Sources/SessionLensCore/Providers/OpenCode/OpenCodeModels.swift` — SQLite JSON rows and provider/model decoding.
- `Sources/SessionLensCore/Providers/Codex/CodexAppServerClient.swift` — supervised JSONL app-server client.
- `Sources/SessionLensCore/Providers/Codex/CodexWireModels.swift` — allowlisted account response DTOs.
- `Sources/SessionLensCore/Providers/Codex/CodexProvider.swift` — account response normalization.
- `Sources/SessionLensCore/Providers/Claude/ClaudeStatusPayload.swift` — official status-line allowlist DTOs.
- `Sources/SessionLensCore/Providers/Claude/ClaudeBridgeStore.swift` — atomic normalized cache read/write.
- `Sources/SessionLensCore/Providers/Claude/ClaudeProvider.swift` — bridge-cache normalization and deltas.
- `Sources/SessionLensCore/Providers/Claude/ClaudeBridgeInstaller.swift` — reversible status-line wrapper installation.
- `Sources/SessionLensClaudeBridge/main.swift` — helper stdin allowlist, atomic cache write, and prior-command forwarding.

### Coordination and notifications

- `Sources/SessionLensCore/Coordination/UsageCoordinator.swift` — concurrent refresh, no-overlap, last-good, and staleness.
- `Sources/SessionLensCore/Notifications/NotificationEvaluator.swift` — pure threshold/reset crossing logic.
- `Sources/SessionLensCore/Notifications/NotificationScheduler.swift` — `UNUserNotificationCenter` adapter.
- `Sources/SessionLensCore/Settings/AppSettings.swift` — persisted user settings and provider mappings.

### App and UI

- `Sources/SessionLens/SessionLensApp.swift` — scenes and menu-bar lifecycle.
- `Sources/SessionLens/AppModel.swift` — main-actor UI state and commands.
- `Sources/SessionLens/DesignSystem.swift` — visual tokens and provider colors.
- `Sources/SessionLensCore/App/MenuBarSummary.swift` — urgent/active/icons/minimal label selection.
- `Sources/SessionLens/Views/PopoverView.swift` — primary composition.
- `Sources/SessionLens/Views/ProviderTabs.swift` — provider selector.
- `Sources/SessionLens/Views/QuotaSection.swift` — quota rows and provenance.
- `Sources/SessionLens/Views/UsageCharts.swift` — rate and daily charts.
- `Sources/SessionLens/Views/TokenSummaryView.swift` — aggregate token and cost table.
- `Sources/SessionLens/Views/EmptyAndErrorViews.swift` — missing, stale, unavailable, and setup states.
- `Sources/SessionLens/Views/SettingsView.swift` — five settings sections.
- `Sources/SessionLensCore/App/LaunchAtLoginController.swift` — `SMAppService` wrapper.
- `Sources/SessionLens/PreviewFixtures.swift` — synthetic visual QA fixtures only.

### Tests

- `Tests/SessionLensCoreTests/Domain/UsageModelsTests.swift`
- `Tests/SessionLensCoreTests/Persistence/SnapshotRepositoryTests.swift`
- `Tests/SessionLensCoreTests/Providers/OpenCodeProviderTests.swift`
- `Tests/SessionLensCoreTests/Providers/CodexAppServerClientTests.swift`
- `Tests/SessionLensCoreTests/Providers/CodexProviderTests.swift`
- `Tests/SessionLensCoreTests/Providers/ClaudeBridgeTests.swift`
- `Tests/SessionLensCoreTests/Providers/ClaudeBridgeInstallerTests.swift`
- `Tests/SessionLensCoreTests/Coordination/UsageCoordinatorTests.swift`
- `Tests/SessionLensCoreTests/Notifications/NotificationEvaluatorTests.swift`
- `Tests/SessionLensCoreTests/Settings/AppSettingsTests.swift`
- `Tests/SessionLensCoreTests/Privacy/PrivacyBoundaryTests.swift`
- `Tests/SessionLensCoreTests/Support/TestDoubles.swift`
- `Tests/SessionLensCoreTests/Support/Fixtures.swift`
- `Tests/SessionLensCoreTests/App/MenuBarSummaryTests.swift`
- `Tests/SessionLensCoreTests/App/LaunchAtLoginControllerTests.swift`

---

### Task 1: Generate and accept the complete visual concept

**Files:**
- Create: `docs/design/sessionlens-popover-concept.png`
- Create: `docs/design/sessionlens-settings-concept.png`
- Create: `docs/design/sessionlens-icon-source.png`
- Create: `docs/design/sessionlens-design-inventory.md`

**Interfaces:**
- Consumes: the committed design in `docs/superpowers/specs/2026-08-12-sessionlens-design.md`.
- Produces: the accepted native-size visual source of truth and the exact design-token inventory used by Tasks 9–11.

- [ ] **Step 1: Invoke the ImageGen skill and generate the primary popover concept**

Use this exact brief, preserving all visible copy and provider semantics:

```text
Create a native macOS 14 menu-bar popover concept for an original personal app named SessionLens. Render one complete 390x640 point light-mode product screen, straight-on, sharp and readable. This is real compact utility UI, not a marketing website and not a screenshot pasted inside a laptop.

Top: original bar-and-aperture SessionLens mark, provider segmented selector with OpenCode, Claude, Codex, availability dots, and a small refresh control. Selected provider is Codex. Below: exact weekly quota at 36%, reset countdown, provenance shown only where needed; a restrained usage-rate line chart; daily usage chart with 7d/30d/90d control; token summary showing Today and Last 7 Days; cost row reading Included with plan; footer with freshness, Settings, Quit. Use native macOS materials, SF Pro-like typography, hairline separators, 12pt surfaces, blue Codex accent, warm coral Claude accent, violet OpenCode accent, restrained semantic amber/red. No nested card grid, no fake metrics beyond the supplied copy, no SessionWatcher branding, no hero treatment, no decorative badges, no browser chrome. Ensure every label is code-native and readable for implementation.
```

- [ ] **Step 2: Inspect the generated popover at original resolution**

Use `view_image` with `detail: original`. Reject and regenerate if any label is unreadable, content is clipped, hierarchy differs from the spec, or the surface looks like a webpage instead of a native popover.

- [ ] **Step 3: Generate the complete Settings concept**

```text
Using the exact visual system from the accepted SessionLens popover, create one complete 760x560 point native macOS Settings window. Use a left sidebar with General, Providers, Menu Bar, Notifications, Privacy; Providers is selected. The main area shows OpenCode detected with aggregate read-only source, Claude Code missing with an Install Bridge action, Codex connected with exact account usage, and an OpenCode provider-to-quota mapping control. Include concise privacy explanations and no sales copy. Use real macOS window chrome, system typography, hairline separators, precise controls, light mode, original SessionLens branding, and no SessionWatcher assets.
```

- [ ] **Step 4: Generate the original app icon source**

```text
Create a 1024x1024 original macOS app icon for SessionLens: a graphite rounded-square tile with a clean luminous aperture made from three ascending usage bars and one subtle blue lens highlight. Minimal, premium, legible at 16px, centered, no letters, no text, no copied SessionWatcher icon geometry, no transparency outside the standard rounded tile, no mockup background.
```

- [ ] **Step 5: Write the design inventory**

Record the following exact headings and fill them from the accepted images:

```markdown
# SessionLens Design Inventory

## Accepted images
## Allowed visible copy
## Layout geometry
## Light and dark palette
## Typography
## Spacing and radii
## Icon inventory
## Component families and states
## Chart styling
## Motion and reduced motion
## Intentional differences from SessionWatcher
```

- [ ] **Step 6: Obtain user acceptance of the two screen concepts and icon**

Show all three images. Record requested changes by regenerating the relevant complete surface, then update `sessionlens-design-inventory.md` to match the accepted images.

- [ ] **Step 7: Commit the accepted visual design**

```bash
git add docs/design
git commit -m "design: define SessionLens native interface"
```

Expected: the commit contains both complete screen concepts, the icon source, and the matching inventory.

---

### Task 2: Create the Swift package and domain model

**Files:**
- Create: `Package.swift`
- Create: `Sources/SessionLensCore/Domain/ProviderID.swift`
- Create: `Sources/SessionLensCore/Domain/UsageModels.swift`
- Create: `Sources/SessionLensCore/Providers/UsageProvider.swift`
- Create: `Sources/SessionLens/main.swift`
- Create: `Sources/SessionLensClaudeBridge/main.swift`
- Create: `Tests/SessionLensCoreTests/Domain/UsageModelsTests.swift`
- Create: `Tests/SessionLensCoreTests/Support/Fixtures.swift`

**Interfaces:**
- Consumes: no implementation task dependencies.
- Produces: `ProviderID`, `MetricProvenance`, `ProviderHealth`, `CostDisplay`, `TokenBreakdown`, `UsageBucket`, `ModelUsage`, `QuotaWindow`, `ProviderSnapshot`, `UsageState`, and `UsageProvider.refresh(at:)`.

- [ ] **Step 1: Create the package manifest and failing domain tests**

Use a macOS 14 package with library, app, bridge, and one test target:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SessionLens",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SessionLensCore", targets: ["SessionLensCore"]),
        .executable(name: "SessionLens", targets: ["SessionLens"]),
        .executable(name: "SessionLensClaudeBridge", targets: ["SessionLensClaudeBridge"]),
    ],
    targets: [
        .target(name: "SessionLensCore"),
        .executableTarget(name: "SessionLens", dependencies: ["SessionLensCore"]),
        .executableTarget(name: "SessionLensClaudeBridge", dependencies: ["SessionLensCore"]),
        .testTarget(name: "SessionLensCoreTests", dependencies: ["SessionLensCore"]),
    ]
)
```

Write tests that require clamped percentages and stable urgency:

```swift
func testQuotaWindowClampsProviderPercentage() {
    let window = QuotaWindow(
        id: "weekly", label: "Weekly", durationMinutes: 10_080,
        usedPercent: 112, resetsAt: nil, provenance: .exactProvider
    )
    XCTAssertEqual(window.usedPercent, 100)
}

func testUnavailableMetricNeverBecomesZero() {
    let snapshot = ProviderSnapshot.unavailable(provider: .claude, health: .toolMissing)
    XCTAssertNil(snapshot.primaryQuota?.usedPercent)
    XCTAssertNil(snapshot.costUSD)
}
```

- [ ] **Step 2: Run the focused test and confirm the missing-type failure**

Run: `swift test --filter UsageModelsTests`

Expected: FAIL because `QuotaWindow` and `ProviderSnapshot` do not exist.

- [ ] **Step 3: Implement the immutable domain types**

Use `Codable`, `Hashable`, and `Sendable` structs/enums. `QuotaWindow` must clamp non-nil percentages to `0...100`, and `ProviderSnapshot.unavailable` must leave metrics nil:

```swift
public struct QuotaWindow: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let durationMinutes: Int?
    public let usedPercent: Double?
    public let resetsAt: Date?
    public let provenance: MetricProvenance

    public init(id: String, label: String, durationMinutes: Int?, usedPercent: Double?, resetsAt: Date?, provenance: MetricProvenance) {
        self.id = id
        self.label = label
        self.durationMinutes = durationMinutes
        self.usedPercent = usedPercent.map { min(100, max(0, $0)) }
        self.resetsAt = resetsAt
        self.provenance = provenance
    }
}
```

Lock the remaining shared interfaces to these fields:

```swift
public enum ProviderID: String, CaseIterable, Codable, Hashable, Sendable {
    case opencode, claude, codex
}

public enum MetricProvenance: String, Codable, Hashable, Sendable {
    case exactProvider, exactLocalAggregate, localBudget, estimated, stale, unavailable
}

public enum ProviderHealth: String, Codable, Hashable, Sendable {
    case ready, setupRequired, toolMissing, stale, malformedData, timedOut, temporarilyUnavailable
}

public enum CostDisplay: Codable, Hashable, Sendable {
    case exactUSD(Double)
    case includedWithPlan
    case unavailable
}

public struct TokenBreakdown: Codable, Hashable, Sendable {
    public let input: Int
    public let output: Int
    public let reasoning: Int
    public let cacheRead: Int
    public let cacheWrite: Int
    public var total: Int { input + output + reasoning + cacheRead + cacheWrite }
}

public struct UsageBucket: Codable, Hashable, Sendable, Identifiable {
    public let day: Date
    public let tokens: Int
    public let costUSD: Double?
    public var id: Date { day }
}

public struct ModelUsage: Codable, Hashable, Sendable, Identifiable {
    public let providerID: String?
    public let modelID: String
    public let tokens: TokenBreakdown
    public let costUSD: Double?
    public var id: String { [providerID, modelID].compactMap { $0 }.joined(separator: "/") }
}

public struct ProviderSnapshot: Codable, Hashable, Sendable, Identifiable {
    public let provider: ProviderID
    public let observedAt: Date
    public var health: ProviderHealth
    public let tokens: TokenBreakdown?
    public let costDisplay: CostDisplay
    public let dailyBuckets: [UsageBucket]
    public let quotaWindows: [QuotaWindow]
    public let modelBreakdowns: [ModelUsage]
    public var id: ProviderID { provider }
    public var costUSD: Double? { if case .exactUSD(let value) = costDisplay { value } else { nil } }
    public var primaryQuota: QuotaWindow? { quotaWindows.first }
}

public struct UsageState: Sendable, Equatable {
    public var snapshots: [ProviderID: ProviderSnapshot]
    public subscript(provider: ProviderID) -> ProviderSnapshot? { snapshots[provider] }
}
```

Give `ProviderSnapshot` a designated initializer and `unavailable(provider:health:observedAt:)` factory that uses `.unavailable`, empty arrays, and nil tokens. Add provider display names and abbreviations as computed properties without storing extra identity data.

Define the adapter protocol exactly:

```swift
public protocol UsageProvider: Sendable {
    var id: ProviderID { get }
    func refresh(at now: Date) async -> ProviderSnapshot
}
```

Define `CostDisplay` as `exactUSD(Double)`, `includedWithPlan`, or `unavailable`, and define `UsageState` as a `Sendable` value with `snapshots: [ProviderID: ProviderSnapshot]` plus a provider subscript. Add temporary executable entry points so the package is buildable from the first task:

```swift
// Sources/SessionLens/main.swift
print("SessionLens foundation")

// Sources/SessionLensClaudeBridge/main.swift
import Foundation
FileHandle.standardOutput.write(Data())
```

`Fixtures.swift` defines the shared deterministic `now`, `day(_:)`, `quota(_:)`, unavailable snapshots, and aggregate snapshot constructors used by later tests. Later tasks extend this same file with provider-specific byte fixtures rather than creating real-user data.

- [ ] **Step 4: Run the focused and cumulative tests**

Run: `swift test --filter UsageModelsTests && swift test`

Expected: PASS.

- [ ] **Step 5: Commit the package foundation**

```bash
git add Package.swift Sources/SessionLensCore Tests/SessionLensCoreTests/Domain
git commit -m "feat: add SessionLens domain foundation"
```

---

### Task 3: Add process isolation and executable discovery

**Files:**
- Create: `Sources/SessionLensCore/Infrastructure/ExecutableLocator.swift`
- Create: `Sources/SessionLensCore/Infrastructure/ProcessRunner.swift`
- Create: `Tests/SessionLensCoreTests/Infrastructure/ProcessRunnerTests.swift`
- Create: `Tests/SessionLensCoreTests/Support/TestDoubles.swift`

**Interfaces:**
- Consumes: `ProviderHealth` from Task 2.
- Produces: `ExecutableLocating.resolve(_:)`, `ProcessExecuting.run(_:)`, `ProcessRequest`, and `ProcessResult` for provider adapters.

- [ ] **Step 1: Write failing locator and timeout tests**

```swift
func testLocatorUsesOnlyExplicitCandidatesAndPathEntries() throws {
    let fileSystem = FakeExecutableFileSystem(executablePaths: ["/opt/homebrew/bin/opencode"])
    let locator = ExecutableLocator(fileSystem: fileSystem, environmentPath: "/usr/bin:/opt/homebrew/bin")
    XCTAssertEqual(locator.resolve(.opencode), URL(fileURLWithPath: "/opt/homebrew/bin/opencode"))
    XCTAssertFalse(fileSystem.probedPaths.contains("/tmp/opencode"))
}

func testRunnerReturnsTimedOutWithoutUnboundedStderr() async {
    let runner = FoundationProcessRunner(stderrLimit: 1024)
    let result = await runner.run(.init(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["2"], timeout: .milliseconds(50)))
    XCTAssertEqual(result.termination, .timedOut)
    XCTAssertLessThanOrEqual(result.stderr.count, 1024)
}
```

- [ ] **Step 2: Run the focused tests and confirm missing infrastructure failures**

Run: `swift test --filter ProcessRunnerTests`

Expected: FAIL because the locator and runner are undefined.

- [ ] **Step 3: Implement bounded discovery and subprocess execution**

Search only `PATH` plus these fixed candidates:

```swift
public enum ToolExecutable: Sendable {
    case opencode, claude, codex, sqlite3

    var fixedCandidates: [String] {
        switch self {
        case .opencode: return ["/opt/homebrew/bin/opencode", "/usr/local/bin/opencode"]
        case .claude: return ["/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        case .codex: return ["/Applications/ChatGPT.app/Contents/Resources/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
        case .sqlite3: return ["/usr/bin/sqlite3"]
        }
    }
}
```

`FoundationProcessRunner` must use `Process`, close stdin, read stdout/stderr concurrently, terminate at the deadline, truncate stderr to the configured byte limit, and return data rather than throwing raw process errors.

Use these exact transport values:

```swift
public struct ProcessRequest: Sendable {
    public let executable: URL
    public let arguments: [String]
    public let stdin: Data
    public let timeout: Duration
    public let environment: [String: String]
}

public struct ProcessResult: Sendable, Equatable {
    public enum Termination: Sendable, Equatable { case exited(Int32), timedOut, launchFailed }
    public let stdout: Data
    public let stderr: Data
    public let termination: Termination
}

public protocol ProcessExecuting: Sendable {
    func run(_ request: ProcessRequest) async -> ProcessResult
}
```

Provide default empty stdin/environment values in `ProcessRequest.init`, so adapter calls specify only what differs.

- [ ] **Step 4: Run the focused and cumulative tests**

Run: `swift test --filter ProcessRunnerTests && swift test`

Expected: PASS with the timeout test completing in under one second.

- [ ] **Step 5: Commit the process boundary**

```bash
git add Sources/SessionLensCore/Infrastructure Tests/SessionLensCoreTests/Infrastructure Tests/SessionLensCoreTests/Support
git commit -m "feat: isolate provider subprocesses"
```

---

### Task 4: Persist normalized aggregate history with Core Data

**Files:**
- Create: `Sources/SessionLensCore/Persistence/PersistenceModels.swift`
- Create: `Sources/SessionLensCore/Persistence/SnapshotRepository.swift`
- Create: `Tests/SessionLensCoreTests/Persistence/SnapshotRepositoryTests.swift`

**Interfaces:**
- Consumes: `ProviderSnapshot`, `UsageBucket`, and `ProviderID` from Task 2.
- Produces: `SnapshotRepository.record(_:)`, `latest(provider:)`, `dailyUsage(provider:range:)`, `markNotification(_:)`, `hasNotification(_:)`, `prune(now:)`, and `clearHistory()`.

- [ ] **Step 1: Write failing in-memory repository tests**

```swift
func testRepositoryRoundTripsOnlyNormalizedSnapshot() throws {
    let repository = try SnapshotRepository.inMemory()
    let snapshot = Fixtures.codexSnapshot(observedAt: .init(timeIntervalSince1970: 1_700_000_000))
    try repository.record(snapshot)
    XCTAssertEqual(try repository.latest(provider: .codex), snapshot)
}

func testPruneKeepsDailyBucketsForOneYearAndDropsOldQuotaObservations() throws {
    let repository = try SnapshotRepository.inMemory()
    try repository.seedRetentionFixture()
    try repository.prune(now: Fixtures.day(400))
    XCTAssertEqual(try repository.quotaObservationCount(olderThanDays: 90), 0)
    XCTAssertEqual(try repository.dailyBucketCount(olderThanDays: 365), 0)
}
```

- [ ] **Step 2: Run the focused tests and confirm the missing repository failure**

Run: `swift test --filter SnapshotRepositoryTests`

Expected: FAIL because `SnapshotRepository` is undefined.

- [ ] **Step 3: Implement aggregate-only Core Data records**

Use separate `NSManagedObject` classes with a programmatic `NSManagedObjectModel` and no generic raw-provider payload field. This preserves a native SQLite-backed store while remaining buildable with Command Line Tools, whose SwiftData SDK omits the `SwiftDataMacros` compiler plugin.

```swift
final class SnapshotRecord: NSManagedObject {
    @NSManaged var key: String
    var providerRaw: String
    var observedAt: Date
    var healthRaw: String
    var tokenData: Data?
    var costUSD: Double?
    var quotaData: Data
}
```

Encode only normalized `TokenBreakdown` and `[QuotaWindow]`. Add `DailyUsageRecord`, `NotificationRecord`, and `SettingsRecord`. Configure tests with an `NSInMemoryStoreType` persistent store and production with an `NSSQLiteStoreType` store under Application Support.

- [ ] **Step 4: Run focused and cumulative tests**

Run: `swift test --filter SnapshotRepositoryTests && swift test`

Expected: PASS.

- [ ] **Step 5: Commit persistence**

```bash
git add Sources/SessionLensCore/Persistence Tests/SessionLensCoreTests/Persistence
git commit -m "feat: persist aggregate usage history"
```

---

### Task 5: Implement the read-only OpenCode adapter

**Files:**
- Create: `Sources/SessionLensCore/Providers/OpenCode/OpenCodeModels.swift`
- Create: `Sources/SessionLensCore/Providers/OpenCode/OpenCodeProvider.swift`
- Create: `Tests/SessionLensCoreTests/Providers/OpenCodeProviderTests.swift`

**Interfaces:**
- Consumes: `UsageProvider`, `ProcessExecuting`, `ExecutableLocating`, and domain models.
- Produces: `OpenCodeProvider`, `OpenCodeProvider.fixedAggregateSQL`, and normalized OpenCode snapshots.

- [ ] **Step 1: Write failing SQL privacy and aggregation tests**

```swift
func testSQLUsesOnlySessionAggregateColumns() {
    let sql = OpenCodeProvider.fixedAggregateSQL.lowercased()
    XCTAssertTrue(sql.contains("from session"))
    for forbidden in ["message", "part", "session_input", "prompt", "title", "directory", "credential", " data"] {
        XCTAssertFalse(sql.contains(forbidden), "forbidden SQL token: \(forbidden)")
    }
}

func testProviderNormalizesSqliteJSONRows() async {
    let process = FakeProcessRunner(stdout: Fixtures.openCodeRowsJSON)
    let provider = OpenCodeProvider(databaseURL: Fixtures.openCodeDatabaseURL, process: process, sqliteURL: URL(fileURLWithPath: "/usr/bin/sqlite3"))
    let snapshot = await provider.refresh(at: Fixtures.now)
    XCTAssertEqual(snapshot.provider, .opencode)
    XCTAssertEqual(snapshot.tokens?.total, 4_200)
    XCTAssertEqual(snapshot.costUSD, 1.25)
    XCTAssertEqual(snapshot.dailyBuckets.count, 2)
}
```

- [ ] **Step 2: Run focused tests and confirm missing-adapter failure**

Run: `swift test --filter OpenCodeProviderTests`

Expected: FAIL because `OpenCodeProvider` is undefined.

- [ ] **Step 3: Implement the constant query and allowlisted row decoding**

Use this query exactly, changing only whitespace when needed:

```sql
SELECT
  date(time_updated / 1000, 'unixepoch', 'localtime') AS day,
  json_extract(model, '$.providerID') AS provider_id,
  json_extract(model, '$.id') AS model_id,
  SUM(cost) AS cost,
  SUM(tokens_input) AS tokens_input,
  SUM(tokens_output) AS tokens_output,
  SUM(tokens_reasoning) AS tokens_reasoning,
  SUM(tokens_cache_read) AS tokens_cache_read,
  SUM(tokens_cache_write) AS tokens_cache_write
FROM session
GROUP BY day, provider_id, model_id
ORDER BY day ASC, provider_id ASC, model_id ASC;
```

Invoke sqlite with arguments `-readonly -json <database-path> <query>`. Decode only matching `CodingKeys`. Treat a missing database as `.setupRequired`, missing aggregate columns as `.malformedData`, and no rows as a ready empty snapshot.

- [ ] **Step 4: Add a schema-drift test and pass it**

```swift
func testSchemaDriftReturnsMalformedWithoutFabricatingZeroes() async {
    let provider = OpenCodeProvider(databaseURL: Fixtures.openCodeDatabaseURL, process: FakeProcessRunner(stderr: Data("no such column".utf8), exitCode: 1), sqliteURL: Fixtures.sqliteURL)
    let snapshot = await provider.refresh(at: Fixtures.now)
    XCTAssertEqual(snapshot.health, .malformedData)
    XCTAssertNil(snapshot.tokens)
    XCTAssertNil(snapshot.costUSD)
}
```

Run: `swift test --filter OpenCodeProviderTests`

Expected: PASS.

- [ ] **Step 5: Commit OpenCode support**

```bash
git add Sources/SessionLensCore/Providers/OpenCode Tests/SessionLensCoreTests/Providers/OpenCodeProviderTests.swift
git commit -m "feat: read OpenCode aggregate usage"
```

---

### Task 6: Implement the supervised Codex app-server client

**Files:**
- Create: `Sources/SessionLensCore/Providers/Codex/CodexAppServerClient.swift`
- Create: `Sources/SessionLensCore/Providers/Codex/CodexWireModels.swift`
- Create: `Tests/SessionLensCoreTests/Providers/CodexAppServerClientTests.swift`
- Modify: `Tests/SessionLensCoreTests/Support/TestDoubles.swift`
- Modify: `Tests/SessionLensCoreTests/Support/Fixtures.swift`

**Interfaces:**
- Consumes: executable discovery and Foundation process primitives.
- Produces: actor `CodexAppServerClient`, protocol `CodexAccountReading`, `CodexAccountUsageResponse`, `CodexRateLimitsResponse`, `connect()`, `readUsage()`, `readRateLimits()`, and `shutdown()`.

- [ ] **Step 1: Write failing JSONL handshake and allowlist tests**

```swift
func testClientInitializesBeforeAccountRequests() async throws {
    let transport = FakeJSONLTransport(responses: Fixtures.codexHandshakeResponses)
    let client = CodexAppServerClient(transport: transport)
    _ = try await client.readRateLimits()
    XCTAssertEqual(transport.sentMethods.prefix(3), ["initialize", "initialized", "account/rateLimits/read"])
}

func testClientNeverSendsThreadMethods() async throws {
    let transport = FakeJSONLTransport(responses: Fixtures.codexUsageResponses)
    let client = CodexAppServerClient(transport: transport)
    _ = try await client.readUsage()
    XCTAssertTrue(Set(transport.sentMethods).isSubset(of: ["initialize", "initialized", "account/usage/read"]))
}
```

- [ ] **Step 2: Run focused tests and confirm missing-client failure**

Run: `swift test --filter CodexAppServerClientTests`

Expected: FAIL because the client and transport protocol are undefined.

- [ ] **Step 3: Implement request IDs, continuations, and process supervision**

Define the transport seam:

```swift
public protocol JSONLTransport: Sendable {
    func start() async throws
    func send(_ object: [String: JSONValue]) async throws
    func nextObject(timeout: Duration) async throws -> [String: JSONValue]
    func stop() async
}
```

`CodexAppServerClient` must initialize once per process, attach monotonically increasing request IDs, ignore notifications, match responses by ID, time out after eight seconds, and restart after EOF or malformed JSON. Initialization capabilities opt out of unrelated notifications.

Define the provider seam used by Task 7:

```swift
public protocol CodexAccountReading: Sendable {
    func readUsage() async throws -> CodexAccountUsageResponse
    func readRateLimits() async throws -> CodexRateLimitsResponse
}
```

The actor conforms to this protocol. Add `FakeJSONLTransport`, `FakeCodexClient`, the async throwing assertion helper, and the exact synthetic handshake/account response fixtures to the two shared support files.

DTOs decode only the documented account result fields: daily token buckets, lifetime summary, limit IDs/names, primary/secondary percentages, durations, reset timestamps, plan type, and reached state.

- [ ] **Step 4: Add timeout and restart tests**

```swift
func testTimeoutStopsTransportAndReconnectsNextRequest() async {
    let transport = FakeJSONLTransport(sequence: [.timeout, .response(Fixtures.codexRateLimitResponse)])
    let client = CodexAppServerClient(transport: transport)
    await XCTAssertThrowsErrorAsync { try await client.readRateLimits() }
    _ = try? await client.readRateLimits()
    XCTAssertEqual(transport.startCount, 2)
}
```

Run: `swift test --filter CodexAppServerClientTests`

Expected: PASS.

- [ ] **Step 5: Commit the Codex transport**

```bash
git add Sources/SessionLensCore/Providers/Codex Tests/SessionLensCoreTests/Providers/CodexAppServerClientTests.swift
git commit -m "feat: add Codex app-server client"
```

---

### Task 7: Normalize live Codex quotas and history

**Files:**
- Create: `Sources/SessionLensCore/Providers/Codex/CodexProvider.swift`
- Create: `Tests/SessionLensCoreTests/Providers/CodexProviderTests.swift`

**Interfaces:**
- Consumes: `CodexAppServerClient`, Codex DTOs, and domain models.
- Produces: `CodexProvider.refresh(at:)` and duration-based quota labels.

- [ ] **Step 1: Write failing normalization tests**

```swift
func testProviderNormalizesWeeklyAndFiveHourWindows() async {
    let client = FakeCodexClient(rateLimits: Fixtures.codexTwoWindowLimits, usage: Fixtures.codexUsage)
    let snapshot = await CodexProvider(client: client).refresh(at: Fixtures.now)
    XCTAssertEqual(snapshot.quotaWindows.map(\.label), ["5-hour", "Weekly"])
    XCTAssertEqual(snapshot.quotaWindows.map(\.usedPercent), [42, 36])
    XCTAssertEqual(snapshot.dailyBuckets.last?.tokens, 453_544_969)
    XCTAssertNil(snapshot.costUSD)
}

func testIncludedPlanCostLabelIsDomainStateNotFabricatedDollars() async {
    let snapshot = await CodexProvider(client: FakeCodexClient.standard).refresh(at: Fixtures.now)
    XCTAssertEqual(snapshot.costDisplay, .includedWithPlan)
}
```

- [ ] **Step 2: Run focused tests and confirm missing-provider failure**

Run: `swift test --filter CodexProviderTests`

Expected: FAIL because `CodexProvider` is undefined.

- [ ] **Step 3: Implement normalization**

Flatten primary and secondary windows across `rateLimitsByLimitId`, deduplicate identical duration/reset pairs, sort shortest duration first, and derive labels with this pure rule:

```swift
static func label(for minutes: Int?) -> String {
    switch minutes {
    case 300: "5-hour"
    case 10_080: "Weekly"
    case .some(let value): "\(value) min"
    case nil: "Quota"
    }
}
```

Map account daily buckets to local dates without inventing missing days. Use `.exactProvider` for quota and account tokens, and `.includedWithPlan` for cost display when `planType` is present and no dollar value exists.

- [ ] **Step 4: Run focused and cumulative tests**

Run: `swift test --filter CodexProviderTests && swift test`

Expected: PASS.

- [ ] **Step 5: Commit Codex normalization**

```bash
git add Sources/SessionLensCore/Providers/Codex/CodexProvider.swift Tests/SessionLensCoreTests/Providers/CodexProviderTests.swift
git commit -m "feat: normalize Codex quota and usage"
```

---

### Task 8: Build the privacy-preserving Claude bridge

**Files:**
- Create: `Sources/SessionLensCore/Providers/Claude/ClaudeStatusPayload.swift`
- Create: `Sources/SessionLensCore/Providers/Claude/ClaudeBridgeStore.swift`
- Create: `Sources/SessionLensCore/Providers/Claude/ClaudeProvider.swift`
- Modify: `Sources/SessionLensClaudeBridge/main.swift`
- Create: `Tests/SessionLensCoreTests/Providers/ClaudeBridgeTests.swift`
- Modify: `Tests/SessionLensCoreTests/Support/TestDoubles.swift`
- Modify: `Tests/SessionLensCoreTests/Support/Fixtures.swift`

**Interfaces:**
- Consumes: domain models and file-system/process seams.
- Produces: `ClaudeStatusPayload`, `ClaudeNormalizedCache`, `ClaudeBridgeStore`, `ClaudeProvider`, and the bridge executable.

- [ ] **Step 1: Write failing allowlist and delta tests**

```swift
func testStatusPayloadDecodingCannotRepresentSensitiveFields() throws {
    let payload = try JSONDecoder().decode(ClaudeStatusPayload.self, from: Fixtures.claudeOfficialStatusLineJSON)
    let normalized = payload.normalized(observedAt: Fixtures.now)
    let encoded = try JSONEncoder().encode(normalized)
    let text = String(decoding: encoded, as: UTF8.self)
    for forbidden in ["cwd", "transcript", "workspace", "session_name", "prompt", "source"] {
        XCTAssertFalse(text.contains(forbidden))
    }
}

func testCumulativeCountersBecomeNonNegativeDeltas() async {
    let store = FakeClaudeBridgeStore(caches: [Fixtures.claudeCache(tokens: 100), Fixtures.claudeCache(tokens: 140)])
    let provider = ClaudeProvider(store: store)
    _ = await provider.refresh(at: Fixtures.now)
    let second = await provider.refresh(at: Fixtures.now.addingTimeInterval(60))
    XCTAssertEqual(second.tokens?.total, 40)
}
```

- [ ] **Step 2: Run focused tests and confirm missing-bridge failure**

Run: `swift test --filter ClaudeBridgeTests`

Expected: FAIL because the Claude payload and bridge store are undefined.

- [ ] **Step 3: Implement explicit Codable allowlists and atomic storage**

`ClaudeStatusPayload.CodingKeys` may contain only `session_id`, `model`, `cost`, `context_window`, `rate_limits`, and `version`. Normalize the session ID to `SHA256` using CryptoKit and discard the original string. Define `ClaudeCacheStoring` with `read() throws -> ClaudeNormalizedCache?` and `write(_:) throws`; both the live and fake stores conform.

Write cache data atomically to `~/Library/Application Support/SessionLens/Bridge/claude-usage.json`, create the directory with mode `0700`, and set the file to `0600`. `ClaudeProvider` must mark snapshots stale after five minutes and handle counter resets by starting a new baseline rather than emitting negative usage.

- [ ] **Step 4: Implement the bridge executable and forwarding test**

The helper entry point must:

```swift
let input = FileHandle.standardInput.readDataToEndOfFile()
let payload = try JSONDecoder().decode(ClaudeStatusPayload.self, from: input)
try ClaudeBridgeStore.live.write(payload.normalized(observedAt: Date()))
try ExistingStatusLineForwarder.live.forward(originalInput: input)
```

Forwarding reads the prior command from `claude-bridge-config.json`, runs `/bin/zsh -lc <command>`, sends the untouched original JSON to stdin, and writes only the prior command's stdout to standard output. With no prior command, the helper exits successfully with empty stdout.

Run: `swift test --filter ClaudeBridgeTests`

Expected: PASS.

- [ ] **Step 5: Commit Claude ingestion**

```bash
git add Sources/SessionLensCore/Providers/Claude Sources/SessionLensClaudeBridge Tests/SessionLensCoreTests/Providers/ClaudeBridgeTests.swift
git commit -m "feat: ingest Claude usage privately"
```

---

### Task 9: Add reversible Claude bridge installation

**Files:**
- Create: `Sources/SessionLensCore/Providers/Claude/ClaudeBridgeInstaller.swift`
- Create: `Tests/SessionLensCoreTests/Providers/ClaudeBridgeInstallerTests.swift`

**Interfaces:**
- Consumes: packaged helper URL and Application Support bridge paths.
- Produces: `ClaudeBridgeInstaller.status()`, `install()`, and `uninstall()` with checksum-guarded restoration.

- [ ] **Step 1: Write failing preservation and conflict tests**

```swift
func testInstallPreservesExistingStatusLineAndUninstallRestoresIt() throws {
    let fileSystem = TemporaryClaudeSettings(existingCommand: "~/.claude/statusline.sh")
    let installer = ClaudeBridgeInstaller(paths: fileSystem.paths, helperSource: Fixtures.helperURL)
    try installer.install()
    XCTAssertEqual(fileSystem.bridgeConfig.previousCommand, "~/.claude/statusline.sh")
    try installer.uninstall()
    XCTAssertEqual(fileSystem.currentStatusLineCommand, "~/.claude/statusline.sh")
}

func testUninstallFailsClosedAfterUserEditsWrapper() throws {
    let fileSystem = TemporaryClaudeSettings(existingCommand: nil)
    let installer = ClaudeBridgeInstaller(paths: fileSystem.paths, helperSource: Fixtures.helperURL)
    try installer.install()
    fileSystem.replaceStatusLineCommand("~/my-new-statusline.sh")
    XCTAssertThrowsError(try installer.uninstall()) { error in
        XCTAssertEqual(error as? ClaudeBridgeInstallError, .settingsChangedAfterInstall)
    }
    XCTAssertEqual(fileSystem.currentStatusLineCommand, "~/my-new-statusline.sh")
}
```

- [ ] **Step 2: Run focused tests and confirm missing-installer failure**

Run: `swift test --filter ClaudeBridgeInstallerTests`

Expected: FAIL because `ClaudeBridgeInstaller` is undefined.

- [ ] **Step 3: Implement explicit install and checksum-guarded removal**

Parse `~/.claude/settings.json` with `JSONSerialization`. Preserve the prior `statusLine` object and previous command in SessionLens-owned backup/config files. Copy the packaged helper into SessionLens Application Support and set the wrapper command to its fully quoted path. Compute SHA256 over the installed `statusLine` JSON value and require the same checksum before restoring.

Write provider settings atomically. Never modify `.claude.json`, credentials, project settings, or transcript files.

- [ ] **Step 4: Run focused and cumulative tests**

Run: `swift test --filter ClaudeBridgeInstallerTests && swift test`

Expected: PASS.

- [ ] **Step 5: Commit the reversible installer**

```bash
git add Sources/SessionLensCore/Providers/Claude/ClaudeBridgeInstaller.swift Tests/SessionLensCoreTests/Providers/ClaudeBridgeInstallerTests.swift
git commit -m "feat: install Claude bridge safely"
```

---

### Task 10: Coordinate providers, persistence, staleness, and attribution

**Files:**
- Create: `Sources/SessionLensCore/Coordination/UsageCoordinator.swift`
- Create: `Sources/SessionLensCore/Settings/AppSettings.swift`
- Create: `Tests/SessionLensCoreTests/Coordination/UsageCoordinatorTests.swift`
- Create: `Tests/SessionLensCoreTests/Settings/AppSettingsTests.swift`

**Interfaces:**
- Consumes: three `UsageProvider`s and `SnapshotRepository`.
- Produces: `UsageCoordinator.refresh(at:)`, `currentState()`, `AppSettings`, and explicit OpenCode provider-to-quota mappings.

- [ ] **Step 1: Write failing concurrency and last-good tests**

```swift
func testRefreshRunsProvidersConcurrentlyAndReturnsAllStates() async {
    let providers = ProviderID.allCases.map { DelayedProvider(id: $0, delay: .milliseconds(80)) }
    let coordinator = UsageCoordinator(providers: providers, repository: try! .inMemory())
    let clock = ContinuousClock()
    let elapsed = await clock.measure { _ = await coordinator.refresh(at: Fixtures.now) }
    XCTAssertLessThan(elapsed, .milliseconds(180))
    let current = await coordinator.currentState()
    XCTAssertEqual(current.snapshots.count, 3)
}

func testFailureRetainsLastGoodSnapshotAndMarksItStale() async {
    let provider = SequencedProvider(id: .codex, snapshots: [Fixtures.codexSnapshot(), .unavailable(provider: .codex, health: .timedOut)])
    let coordinator = UsageCoordinator(providers: [provider], repository: try! .inMemory())
    _ = await coordinator.refresh(at: Fixtures.now)
    let state = await coordinator.refresh(at: Fixtures.now.addingTimeInterval(600))
    XCTAssertEqual(state.snapshots[.codex]?.health, .stale)
    XCTAssertEqual(state.snapshots[.codex]?.quotaWindows.first?.usedPercent, 36)
}
```

- [ ] **Step 2: Run focused tests and confirm missing-coordinator failure**

Run: `swift test --filter UsageCoordinatorTests`

Expected: FAIL because `UsageCoordinator` is undefined.

- [ ] **Step 3: Implement actor isolation, no overlap, and persistence**

Use `withTaskGroup(of: ProviderSnapshot.self)` for refresh. If a refresh is in progress, return the current state. Record successful snapshots, convert failed-provider last-good values to `.stale`, and never carry an unavailable value as zero.

`AppSettings` stores refresh interval, range, provider order, notification thresholds, display mode, retention, and mappings from exact OpenCode `providerID` strings to `.claude`, `.codex`, or nil. Default every mapping to nil.

- [ ] **Step 4: Add explicit attribution tests**

```swift
func testOpenCodeQuotaIsNotAttributedWithoutUserMapping() {
    let settings = AppSettings.defaults
    XCTAssertNil(settings.quotaProvider(forOpenCodeProviderID: "anthropic"))
}
```

Run: `swift test --filter UsageCoordinatorTests && swift test --filter AppSettingsTests`

Expected: PASS.

- [ ] **Step 5: Commit coordination and settings**

```bash
git add Sources/SessionLensCore/Coordination Sources/SessionLensCore/Settings Tests/SessionLensCoreTests/Coordination Tests/SessionLensCoreTests/Settings
git commit -m "feat: coordinate provider refreshes"
```

---

### Task 11: Implement deduplicated notifications

**Files:**
- Create: `Sources/SessionLensCore/Notifications/NotificationEvaluator.swift`
- Create: `Sources/SessionLensCore/Notifications/NotificationScheduler.swift`
- Create: `Tests/SessionLensCoreTests/Notifications/NotificationEvaluatorTests.swift`

**Interfaces:**
- Consumes: `ProviderSnapshot`, thresholds from `AppSettings`, and notification keys from `SnapshotRepository`.
- Produces: `NotificationEvent`, `NotificationEvaluator.events(provider:previous:current:thresholds:)`, and `NotificationScheduling.schedule(_:)`.

- [ ] **Step 1: Write failing crossing/reset tests**

```swift
func testThresholdFiresOnlyOnFirstCrossingWithinResetEpoch() {
    let evaluator = NotificationEvaluator()
    XCTAssertEqual(evaluator.events(provider: .codex, previous: Fixtures.quota(69), current: Fixtures.quota(71), thresholds: [70]).map(\.kind), [.threshold(70)])
    XCTAssertTrue(evaluator.events(provider: .codex, previous: Fixtures.quota(71), current: Fixtures.quota(75), thresholds: [70]).isEmpty)
}

func testResetFiresAfterPreviouslyNonzeroWindow() {
    let events = NotificationEvaluator().events(provider: .codex, previous: Fixtures.quota(92, reset: Fixtures.day(2)), current: Fixtures.quota(0, reset: Fixtures.day(9)), thresholds: [70, 90])
    XCTAssertEqual(events.map(\.kind), [.reset])
}

func testUnavailableAndStaleQuotasNeverNotify() {
    XCTAssertTrue(NotificationEvaluator().events(provider: .codex, previous: nil, current: Fixtures.staleQuota, thresholds: [70, 90]).isEmpty)
}
```

- [ ] **Step 2: Run focused tests and confirm missing-evaluator failure**

Run: `swift test --filter NotificationEvaluatorTests`

Expected: FAIL because `NotificationEvaluator` is undefined.

- [ ] **Step 3: Implement pure evaluation and the notification-center adapter**

Implement `events(provider:previous:current:thresholds:)` with the exact signature used above. Create keys from provider, optional account scope hash, quota ID, threshold/reset kind, and reset epoch. `UNNotificationScheduler` requests authorization only from the explicit enable flow, then schedules concise local notifications. Local-budget notification titles must include “Local budget.”

- [ ] **Step 4: Run focused and cumulative tests**

Run: `swift test --filter NotificationEvaluatorTests && swift test`

Expected: PASS.

- [ ] **Step 5: Commit notifications**

```bash
git add Sources/SessionLensCore/Notifications Tests/SessionLensCoreTests/Notifications
git commit -m "feat: add quota notifications"
```

---

### Task 12: Build the app model and menu-bar summary logic

**Files:**
- Create: `Sources/SessionLens/AppModel.swift`
- Create: `Sources/SessionLensCore/App/MenuBarSummary.swift`
- Create: `Sources/SessionLens/PreviewFixtures.swift`
- Create: `Tests/SessionLensCoreTests/App/MenuBarSummaryTests.swift`

**Interfaces:**
- Consumes: coordinator state, settings, notification scheduler, and provider snapshots.
- Produces: `AppModel`, `MenuBarSummary`, selected provider/range, refresh commands, and deterministic synthetic preview states.

- [ ] **Step 1: Write failing urgency tests**

```swift
func testUrgentModeChoosesHighestExactQuotaAheadOfLocalBudget() {
    let summary = MenuBarSummary.make(
        mode: .urgent,
        snapshots: [Fixtures.openCodeLocalBudget(95), Fixtures.codexSnapshot(percent: 72)],
        providerOrder: [.opencode, .claude, .codex]
    )
    XCTAssertEqual(summary.text, "CX 72%")
}

func testUnavailableDoesNotRenderAsZeroPercent() {
    let summary = MenuBarSummary.make(mode: .urgent, snapshots: [.unavailable(provider: .claude, health: .toolMissing)], providerOrder: ProviderID.allCases)
    XCTAssertFalse(summary.text.contains("0%"))
}
```

- [ ] **Step 2: Run focused tests and confirm missing-summary failure**

Run: `swift test --filter MenuBarSummaryTests`

Expected: FAIL because `MenuBarSummary` is undefined.

- [ ] **Step 3: Implement summary selection and `@MainActor AppModel`**

`AppModel` exposes published snapshots, selected provider, chart range, refresh state, provider order, display mode, and errors. It starts a cancellable timer task, refreshes when the popover opens if data is older than 15 seconds, passes normalized transitions to the notification evaluator, and never exposes provider wire payloads to views.

- [ ] **Step 4: Run focused and cumulative tests**

Run: `swift test --filter MenuBarSummaryTests && swift test`

Expected: PASS.

- [ ] **Step 5: Commit the app model**

```bash
git add Sources/SessionLens/AppModel.swift Sources/SessionLensCore/App/MenuBarSummary.swift Sources/SessionLens/PreviewFixtures.swift Tests/SessionLensCoreTests/App/MenuBarSummaryTests.swift
git commit -m "feat: add menu bar application state"
```

---

### Task 13: Implement the accepted popover faithfully

**Files:**
- Create: `Sources/SessionLens/DesignSystem.swift`
- Create: `Sources/SessionLens/Views/PopoverView.swift`
- Create: `Sources/SessionLens/Views/ProviderTabs.swift`
- Create: `Sources/SessionLens/Views/QuotaSection.swift`
- Create: `Sources/SessionLens/Views/UsageCharts.swift`
- Create: `Sources/SessionLens/Views/TokenSummaryView.swift`
- Create: `Sources/SessionLens/Views/EmptyAndErrorViews.swift`
- Create: `Sources/SessionLens/SessionLensApp.swift`
- Delete: `Sources/SessionLens/main.swift`

**Interfaces:**
- Consumes: accepted concept/inventory from Task 1 and `AppModel` from Task 12.
- Produces: the complete interactive 390x640 popover surface.

- [ ] **Step 1: Translate the accepted inventory into exact tokens**

Define named colors, spacing, radii, typography, chart styles, and icon sizes from `docs/design/sessionlens-design-inventory.md`. Keep these in `DesignSystem.swift`; no one-off literal may replace a repeated accepted value.

- [ ] **Step 2: Implement provider selection and state-dependent composition**

`PopoverView` must use this stable order:

```swift
VStack(spacing: 0) {
    ProviderTabs(selection: $model.selectedProvider, snapshots: model.snapshots)
    ProviderHeader(snapshot: model.selectedSnapshot, isRefreshing: model.isRefreshing, refresh: model.refresh)
    QuotaSection(snapshot: model.selectedSnapshot)
    UsageRateChart(snapshot: model.selectedSnapshot)
    DailyUsageChart(snapshot: model.selectedSnapshot, range: $model.chartRange)
    TokenSummaryView(snapshot: model.selectedSnapshot)
    PopoverFooter(lastUpdated: model.selectedSnapshot?.observedAt, openSettings: model.openSettings, quit: model.quit)
}
.frame(width: 390, height: 640)
```

Use separate designed branches for ready, empty, setup-required, stale, and unavailable states. Do not seed production state with preview fixture metrics.

- [ ] **Step 3: Make all primary controls experiential**

Verify in code that provider tabs change selection, range controls change chart data, refresh invokes `AppModel.refresh`, and Quit terminates the app. Expose the Settings command from the footer; Task 14 wires it to the Settings scene. Add accessibility labels with provider, metric, percentage, provenance, and reset time.

Create the first runnable scene shell in `SessionLensApp.swift` with the `MenuBarExtra` and `.menuBarExtraStyle(.window)`. Task 14 will add the Settings scene after its complete surface exists.

- [ ] **Step 4: Build and inspect the first native render**

Run: `swift build`

Expected: PASS.

Launch with preview fixtures enabled by the process argument `--visual-fixtures`. Capture the popover at 390x640 and inspect it against the accepted concept using `view_image` on both images.

- [ ] **Step 5: Repair every popover mismatch**

Record and resolve at least these comparison points in `docs/qa/fidelity-ledger.md`: visible copy, provider tabs, vertical geometry, typography, palette/material, quota rows, chart shapes, token table, footer, icon style, and light/dark behavior. Rebuild and recapture after every repair batch.

- [ ] **Step 6: Commit the faithful popover**

```bash
git add Sources/SessionLens/DesignSystem.swift Sources/SessionLens/Views Sources/SessionLens/SessionLensApp.swift Sources/SessionLens/main.swift docs/qa/fidelity-ledger.md
git commit -m "feat: build SessionLens usage popover"
```

---

### Task 14: Implement settings, launch at login, and app scenes

**Files:**
- Modify: `Sources/SessionLens/SessionLensApp.swift`
- Create: `Sources/SessionLens/Views/SettingsView.swift`
- Create: `Sources/SessionLensCore/App/LaunchAtLoginController.swift`
- Create: `Tests/SessionLensCoreTests/App/LaunchAtLoginControllerTests.swift`

**Interfaces:**
- Consumes: `AppModel`, settings, Claude installer, notifications, and accepted Settings concept.
- Produces: native menu-bar lifecycle, no normal Dock icon, five settings sections, explicit external-write actions, and launch-at-login behavior.

- [ ] **Step 1: Write failing launch-at-login seam tests**

```swift
func testEnablingLaunchAtLoginRegistersMainApp() throws {
    let service = FakeLoginService()
    let controller = LaunchAtLoginController(service: service)
    try controller.setEnabled(true)
    XCTAssertEqual(service.registerCount, 1)
}
```

- [ ] **Step 2: Run focused tests and confirm missing-controller failure**

Run: `swift test --filter LaunchAtLoginControllerTests`

Expected: FAIL because the controller is undefined.

- [ ] **Step 3: Extend the scene shell with Settings**

Use `MenuBarExtra` with `.menuBarExtraStyle(.window)` and a Settings window:

```swift
@main
struct SessionLensApp: App {
    @StateObject private var model = AppModel.live()

    var body: some Scene {
        MenuBarExtra { PopoverView(model: model) } label: { MenuBarLabel(summary: model.menuBarSummary) }
            .menuBarExtraStyle(.window)
        Settings { SettingsView(model: model) }
    }
}
```

Task 16's packaged `Info.plist` sets `LSUIElement` to true. During this task, Settings may activate AppKit only when opened.

- [ ] **Step 4: Implement all five Settings sections**

Follow the accepted Settings concept. Provider actions must show exact data sources. The Claude Install/Uninstall button requires a native confirmation explaining the write to `~/.claude/settings.json`; no bridge is installed automatically. Notification permission is requested only after its toggle is enabled. Clear History requires confirmation and deletes only SessionLens repository entities.

- [ ] **Step 5: Run tests and build**

Run: `swift test --filter LaunchAtLoginControllerTests && swift test && swift build`

Expected: PASS.

- [ ] **Step 6: Inspect Settings against the accepted concept**

Capture at 760x560 in light and dark appearance, use `view_image` on concept and render, and append fixed differences to `docs/qa/fidelity-ledger.md`.

- [ ] **Step 7: Commit scenes and settings**

```bash
git add Sources/SessionLens/SessionLensApp.swift Sources/SessionLens/Views/SettingsView.swift Sources/SessionLensCore/App/LaunchAtLoginController.swift Tests/SessionLensCoreTests/App/LaunchAtLoginControllerTests.swift docs/qa/fidelity-ledger.md
git commit -m "feat: add native settings and app lifecycle"
```

---

### Task 15: Enforce privacy and provider failure boundaries

**Files:**
- Create: `Tests/SessionLensCoreTests/Privacy/PrivacyBoundaryTests.swift`
- Modify: provider files identified by failing privacy tests.

**Interfaces:**
- Consumes: all adapters and persistence models.
- Produces: executable tests proving forbidden access is absent.

- [ ] **Step 1: Write the cross-cutting privacy audit tests**

```swift
func testOpenCodeQueryContainsOnlyAllowlistedIdentifiers() {
    let tokens = SQLIdentifierLexer.identifiers(in: OpenCodeProvider.fixedAggregateSQL)
    XCTAssertTrue(tokens.isSubset(of: OpenCodeProvider.allowedSQLIdentifiers))
}

func testCodexClientMethodAllowlistIsClosed() {
    XCTAssertEqual(CodexAppServerClient.allowedMethods, ["initialize", "initialized", "account/rateLimits/read", "account/usage/read"])
}

func testPersistentModelsHaveNoSensitivePropertyNames() {
    let names = PersistencePrivacyIntrospector.persistedPropertyNames
    XCTAssertTrue(names.isDisjoint(with: ["prompt", "response", "reasoning", "source", "diff", "command", "credential", "path", "project", "title", "transcript"]))
}

func testClaudeNormalizedCacheRejectsUnknownFieldsOnEncoding() throws {
    let encoded = try JSONEncoder().encode(Fixtures.claudeNormalizedCache)
    XCTAssertTrue(Set(try JSONKeys.topLevel(in: encoded)).isSubset(of: ClaudeNormalizedCache.allowedKeys))
}
```

- [ ] **Step 2: Run the privacy tests and observe any concrete failures**

Run: `swift test --filter PrivacyBoundaryTests`

Expected: FAIL until the lexer/introspector allowlists exist; no production relaxations are allowed to make forbidden identifiers pass.

- [ ] **Step 3: Add the closed allowlists and remove every forbidden access**

Expose immutable allowlists from the corresponding production types. If a failure finds a sensitive property or method, remove or rename the persisted access rather than expanding the allowlist.

- [ ] **Step 4: Run the complete test suite**

Run: `swift test`

Expected: PASS, including all privacy tests.

- [ ] **Step 5: Commit the privacy gate**

```bash
git add Tests/SessionLensCoreTests/Privacy Sources/SessionLensCore
git commit -m "test: enforce SessionLens privacy boundaries"
```

---

### Task 16: Package the unsigned personal app and original icon

**Files:**
- Create: `Resources/Info.plist`
- Create: `scripts/build_icon.sh`
- Create: `scripts/package_app.sh`
- Create: `scripts/verify_bundle.sh`
- Create: `README.md`
- Create: `.gitignore`
- Create: `Sources/SessionLens/Resources/SessionLensIcon.png`
- Create: `Sources/SessionLens/Resources/SessionLens.icns`
- Modify: `Package.swift`

**Interfaces:**
- Consumes: release binaries and accepted icon source.
- Produces: `dist/SessionLens.app` with main executable, helper, resources, icon, and correct metadata.

- [ ] **Step 1: Write the bundle-verification shell check before packaging**

Add `scripts/verify_bundle.sh` with exact checks:

```bash
#!/bin/zsh
set -euo pipefail
app_path="${1:?app path required}"
test -x "$app_path/Contents/MacOS/SessionLens"
test -x "$app_path/Contents/Helpers/SessionLensClaudeBridge"
test -f "$app_path/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$app_path/Contents/Info.plist" | grep -qx true
/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$app_path/Contents/Info.plist" | grep -qx 14.0
test -f "$app_path/Contents/Resources/SessionLens.icns"
```

Run: `zsh scripts/verify_bundle.sh dist/SessionLens.app`

Expected: FAIL because the bundle does not exist.

- [ ] **Step 2: Build the ICNS from the accepted 1024px source**

`build_icon.sh` copies the accepted 1024px source to `Sources/SessionLens/Resources/SessionLensIcon.png`, creates a temporary iconset with `sips` sizes 16, 32, 128, 256, 512 and each `@2x`, then calls `iconutil -c icns`. It writes `Sources/SessionLens/Resources/SessionLens.icns` and removes its temporary directory.

- [ ] **Step 3: Assemble the release app**

`package_app.sh` must:

1. run `swift build -c release --product SessionLens`;
2. run `swift build -c release --product SessionLensClaudeBridge`;
3. create `dist/SessionLens.app/Contents/{MacOS,Helpers,Resources}`;
4. copy the two executables to their fixed locations;
5. copy `Resources/Info.plist` and `SessionLens.icns`;
6. set executable modes;
7. run `scripts/verify_bundle.sh`.

At this task, add `.process("Resources")` to the `SessionLens` executable target in `Package.swift` now that the resource directory exists.

`.gitignore` includes `.build/`, `dist/`, `.DS_Store`, and temporary QA captures.

- [ ] **Step 4: Document the personal launch and provider setup**

README sections must be exactly:

```markdown
## What SessionLens reads
## What SessionLens never reads
## Requirements
## Build and package
## First launch of the unsigned app
## OpenCode setup
## Claude bridge setup and removal
## Codex setup
## Notifications
## Local data and clearing history
## Verification
```

- [ ] **Step 5: Build, package, and verify**

Run: `zsh scripts/package_app.sh && zsh scripts/verify_bundle.sh dist/SessionLens.app`

Expected: PASS and a double-clickable `dist/SessionLens.app`.

- [ ] **Step 6: Commit packaging and docs**

```bash
git add Package.swift Resources scripts Sources/SessionLens/Resources README.md .gitignore
git commit -m "build: package SessionLens macOS app"
```

---

### Task 17: Run live integrations and native visual QA

**Files:**
- Create: `docs/qa/verification-report.md`
- Modify: any source or test file implicated by a verified defect.

**Interfaces:**
- Consumes: packaged app, live Codex/OpenCode installations, synthetic Claude payloads, accepted concepts, and fidelity ledger.
- Produces: requirement-by-requirement verification evidence and the final repaired build.

- [ ] **Step 1: Run clean automated verification**

Run:

```bash
swift package clean
swift test
zsh scripts/package_app.sh
zsh scripts/verify_bundle.sh dist/SessionLens.app
```

Expected: every command exits 0.

- [ ] **Step 2: Verify live Codex account data without thread access**

Launch the packaged app, refresh Codex, and compare SessionLens values to a separately initialized local `codex app-server` call using `account/rateLimits/read` and `account/usage/read`. Record percentages, durations, resets, daily-bucket count, and observation time; redact account identity. Confirm app diagnostics contain no thread methods.

- [ ] **Step 3: Verify OpenCode read-only access**

Record the real OpenCode database modification timestamp, refresh SessionLens, and record it again. Confirm it is unchanged. Compare SessionLens aggregate totals with the fixed query executed independently through `/usr/bin/sqlite3 -readonly -json`. Confirm no content table appears in app diagnostics or the SQL allowlist.

- [ ] **Step 4: Verify Claude synthetic integration and live status honestly**

Feed an official-shaped synthetic status-line payload through the packaged helper and confirm the cache contains only allowlisted keys, the app updates exact quotas/tokens/cost, and an existing synthetic status-line command receives the original input and returns its output. If `claude` remains unavailable locally, write `Live Claude CLI: not installed; synthetic official-payload integration passed` in the report.

- [ ] **Step 5: Verify notifications and failure states**

Using visual fixture mode, trigger 69→70, 89→90, quota reset, stale, timeout, missing tool, schema drift, local budget, and unavailable quota. Confirm threshold/reset alerts deduplicate and unavailable/stale states send no alert.

- [ ] **Step 6: Perform native UI interaction QA**

Use the Computer Use skill to inspect and operate the real packaged app. Verify menu-bar presence, no normal Dock icon, popover open/close, three provider tabs, 7d/30d/90d controls, manual refresh, Settings, notification toggle behavior, Claude confirmation, Clear History confirmation, and Quit.

- [ ] **Step 7: Complete concept-to-render fidelity QA**

Capture popover at 390x640 and Settings at 760x560 in light and dark appearance. Use `view_image` on every accepted concept and corresponding latest screenshot. Update `docs/qa/fidelity-ledger.md` with at least five concrete comparison points per surface, all fixed mismatches, above-the-fold copy diff, and intentional deviations. Continue repairs until a skilled design agency would sign off.

- [ ] **Step 8: Audit every acceptance criterion**

In `verification-report.md`, create a table with all 13 acceptance criteria from the design spec and columns `Evidence`, `Result`, and `Notes`. A result may be `Proven`, `Not proven`, or `Contradicted`. Do not claim completion while any row is not `Proven`; live Claude installation is not a completion requirement because the spec explicitly accepts synthetic integration when the CLI is absent.

- [ ] **Step 9: Re-run verification after all repairs**

Run:

```bash
swift test
zsh scripts/package_app.sh
zsh scripts/verify_bundle.sh dist/SessionLens.app
if rg -n 'URLSession|import Network|NWConnection|CFHTTP' Sources; then exit 1; fi
git diff --check
git status --short
```

Expected: tests/package checks pass, no whitespace errors, and only intended verification documentation or repaired source changes remain.

- [ ] **Step 10: Commit verified repairs and evidence**

```bash
git add Sources Tests Resources scripts README.md docs/qa
git commit -m "test: verify SessionLens end to end"
```

Expected: the final commit contains the verification report, fidelity ledger, and any repairs proven necessary by runtime QA.
