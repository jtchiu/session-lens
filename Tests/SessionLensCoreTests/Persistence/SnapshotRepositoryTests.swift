import Foundation
import Testing

@testable import SessionLensCore

@Suite
@MainActor
struct SnapshotRepositoryTests {
    @Test
    func repositoryRoundTripsAndDeduplicatesSpendSamples() throws {
        let repository = try SnapshotRepository.inMemory()
        let sample = ProviderSpendSample(
            provider: .claude,
            observedAt: Fixtures.now,
            scopeID: "hashed-session",
            cumulativeCostUSD: 1.25,
            cumulativeTokens: 10_000,
            provenance: .estimated
        )
        let snapshot = ProviderSnapshot(
            provider: .claude,
            observedAt: Fixtures.now,
            health: .ready,
            tokens: nil,
            costDisplay: .estimatedUSD(1.25),
            dailyBuckets: [],
            quotaWindows: [],
            modelBreakdowns: [],
            costSample: sample
        )

        try repository.record(snapshot)
        try repository.record(snapshot)

        #expect(try repository.spendSampleRecordCount() == 1)
        #expect(try repository.spendSamples().first == sample)
        #expect(try repository.latest(provider: .claude)?.costSample == sample)
    }

    @Test
    func pruneAndClearHistoryManageSpendSamples() throws {
        let repository = try SnapshotRepository.inMemory()
        func snapshot(at date: Date, cost: Double) -> ProviderSnapshot {
            let sample = ProviderSpendSample(
                provider: .claude,
                observedAt: date,
                scopeID: "session",
                cumulativeCostUSD: cost,
                cumulativeTokens: Int(cost * 100),
                provenance: .estimated
            )
            return ProviderSnapshot(
                provider: .claude,
                observedAt: date,
                health: .ready,
                tokens: nil,
                costDisplay: .estimatedUSD(cost),
                dailyBuckets: [],
                quotaWindows: [],
                modelBreakdowns: [],
                costSample: sample
            )
        }

        try repository.record(snapshot(at: Fixtures.day(80), cost: 1))
        try repository.record(snapshot(at: Fixtures.day(95), cost: 2))
        try repository.prune(now: Fixtures.day(100), historyRetentionDays: 10)

        #expect(try repository.spendSampleRecordCount() == 1)
        #expect(try repository.spendSamples().first?.observedAt == Fixtures.day(95))

        try repository.clearHistory()

        #expect(try repository.spendSampleRecordCount() == 0)
    }

    @Test @MainActor
    func repositoryPreservesEstimatedCostProvenance() throws {
        let repository = try SnapshotRepository.inMemory()
        let snapshot = Fixtures.aggregateSnapshot(
            provider: .claude,
            costDisplay: .estimatedUSD(0.42)
        )

        try repository.record(snapshot)

        #expect(try repository.latest(provider: .claude)?.costDisplay == .estimatedUSD(0.42))
    }

  @Test
  func repositoryRoundTripsOnlyNormalizedSnapshot() throws {
    let repository = try SnapshotRepository.inMemory()
    let snapshot = Fixtures.codexSnapshot(
      observedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )

    try repository.record(snapshot)

    #expect(try repository.latest(provider: .codex) == snapshot)
  }

  @Test
  func repositoryRoundTripsNormalizedModelBreakdowns() throws {
    let repository = try SnapshotRepository.inMemory()
    let breakdown = ModelUsage(
      providerID: "openai",
      modelID: "gpt-5",
      tokens: TokenBreakdown(
        input: 100,
        output: 50,
        reasoning: 20,
        cacheRead: 10,
        cacheWrite: 5
      ),
      costUSD: 0.42
    )
    let snapshot = ProviderSnapshot(
      provider: .opencode,
      observedAt: Fixtures.now,
      health: .ready,
      tokens: breakdown.tokens,
      costDisplay: .exactUSD(0.42),
      dailyBuckets: [],
      quotaWindows: [],
      modelBreakdowns: [breakdown]
    )

    try repository.record(snapshot)

    #expect(try repository.latest(provider: .opencode)?.modelBreakdowns == [breakdown])
  }

  @Test
  func persistentRepositoryUsesLocalSQLiteStore() throws {
    let rootURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("SessionLensTests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: rootURL) }
    let repository = try SnapshotRepository.persistent(
      applicationSupportURL: rootURL
    )
    let snapshot = Fixtures.codexSnapshot()

    try repository.record(snapshot)

    #expect(repository.storeURL?.lastPathComponent == "usage.sqlite")
    #expect(
      repository.storeURL.map {
        FileManager.default.fileExists(atPath: $0.path)
      } == true
    )
    #expect(try repository.latest(provider: .codex) == snapshot)
  }

  @Test
  func pruneKeepsOneYearOfDailyBucketsAndNinetyDaysOfSnapshots() throws {
    let repository = try SnapshotRepository.inMemory()
    let old = Fixtures.aggregateSnapshot(
      provider: .opencode,
      observedAt: Fixtures.day(0),
      dailyBuckets: [
        UsageBucket(day: Fixtures.day(0), tokens: 100, costUSD: 0.10)
      ]
    )
    let recent = Fixtures.aggregateSnapshot(
      provider: .opencode,
      observedAt: Fixtures.day(400),
      dailyBuckets: [
        UsageBucket(day: Fixtures.day(400), tokens: 200, costUSD: 0.20)
      ]
    )
    try repository.record(old)
    try repository.record(recent)

    try repository.prune(now: Fixtures.day(400))

    #expect(try repository.snapshotRecordCount() == 1)
    #expect(try repository.dailyUsageRecordCount() == 1)
    #expect(try repository.latest(provider: .opencode) == recent)
  }

  @Test
  func pruneHonorsConfiguredRetentionAndDropsOldNotificationKeys() throws {
    let repository = try SnapshotRepository.inMemory()
    let now = Fixtures.day(100)
    try repository.record(
      Fixtures.aggregateSnapshot(
        provider: .codex,
        observedAt: Fixtures.day(80),
        dailyBuckets: [
          UsageBucket(day: Fixtures.day(80), tokens: 80, costUSD: nil)
        ]
      )
    )
    try repository.record(
      Fixtures.aggregateSnapshot(
        provider: .codex,
        observedAt: Fixtures.day(95),
        dailyBuckets: [
          UsageBucket(day: Fixtures.day(95), tokens: 95, costUSD: nil)
        ]
      )
    )
    try repository.markNotification("old", at: Fixtures.day(80))
    try repository.markNotification("new", at: Fixtures.day(95))

    try repository.prune(now: now, historyRetentionDays: 10)

    #expect(try repository.snapshotRecordCount() == 1)
    #expect(try repository.dailyUsageRecordCount() == 1)
    #expect(!(try repository.hasNotification("old")))
    #expect(try repository.hasNotification("new"))
  }

  @Test
  func dailyUsageReturnsOnlyRequestedProviderAndRange() throws {
    let repository = try SnapshotRepository.inMemory()
    try repository.record(
      Fixtures.aggregateSnapshot(
        provider: .opencode,
        dailyBuckets: [
          UsageBucket(day: Fixtures.day(-2), tokens: 10, costUSD: 0.01),
          UsageBucket(day: Fixtures.day(0), tokens: 20, costUSD: 0.02),
        ]
      )
    )
    try repository.record(
      Fixtures.aggregateSnapshot(
        provider: .codex,
        dailyBuckets: [
          UsageBucket(day: Fixtures.day(0), tokens: 999, costUSD: nil)
        ]
      )
    )

    let buckets = try repository.dailyUsage(
      provider: .opencode,
      range: Fixtures.day(-1)...Fixtures.day(1)
    )

    #expect(
      buckets
        == [UsageBucket(day: Fixtures.day(0), tokens: 20, costUSD: 0.02)]
    )
  }

  @Test
  func quotaHistoryUsesLogicalDurationAcrossResetIdentityChanges() throws {
    let repository = try SnapshotRepository.inMemory()
    for (offset, percent) in [(0, 20.0), (1, 36.0), (2, 4.0)] {
      let quota = QuotaWindow(
        id: "codex:10080:reset-\(offset)",
        label: "Weekly",
        durationMinutes: 10_080,
        usedPercent: percent,
        resetsAt: Fixtures.day(offset + 2),
        provenance: .exactProvider
      )
      try repository.record(
        Fixtures.aggregateSnapshot(
          provider: .codex,
          observedAt: Fixtures.now.addingTimeInterval(Double(offset * 60)),
          quotaWindows: [quota]
        )
      )
    }

    let points = try repository.quotaHistory(
      provider: .codex,
      durationMinutes: 10_080,
      range: Fixtures.now...Fixtures.now.addingTimeInterval(180)
    )

    #expect(points.map(\.usedPercent) == [20, 36, 4])
    #expect(points.map(\.observedAt) == [
      Fixtures.now,
      Fixtures.now.addingTimeInterval(60),
      Fixtures.now.addingTimeInterval(120),
    ])
  }

  @Test
  func dailyQuotaHistoryUsesLatestObservationPerCalendarDay() throws {
    let repository = try SnapshotRepository.inMemory()
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let firstDay = calendar.date(
      from: DateComponents(year: 2026, month: 8, day: 10, hour: 9)
    )!
    let latestFirstDay = firstDay.addingTimeInterval(60 * 60)
    let secondDay = calendar.date(byAdding: .day, value: 1, to: firstDay)!

    func snapshot(
      observedAt: Date,
      usedPercent: Double,
      resetsAt: Date?,
      provenance: MetricProvenance
    ) -> ProviderSnapshot {
      Fixtures.aggregateSnapshot(
        provider: .codex,
        observedAt: observedAt,
        quotaWindows: [
          QuotaWindow(
            id: "codex:10080:reset-\(observedAt.timeIntervalSince1970)",
            label: "Weekly",
            durationMinutes: 10_080,
            usedPercent: usedPercent,
            resetsAt: resetsAt,
            provenance: provenance
          )
        ]
      )
    }

    try repository.record(snapshot(
      observedAt: firstDay,
      usedPercent: 20,
      resetsAt: calendar.date(byAdding: .day, value: 3, to: firstDay),
      provenance: .exactProvider
    ))
    try repository.record(snapshot(
      observedAt: latestFirstDay,
      usedPercent: 36,
      resetsAt: calendar.date(byAdding: .day, value: 4, to: firstDay),
      provenance: .localBudget
    ))
    try repository.record(snapshot(
      observedAt: secondDay,
      usedPercent: 44,
      resetsAt: calendar.date(byAdding: .day, value: 5, to: firstDay),
      provenance: .estimated
    ))

    let points = try repository.dailyQuotaHistory(
      provider: .codex,
      durationMinutes: 10_080,
      range: firstDay...secondDay,
      calendar: calendar
    )

    #expect(points.map(\.usedPercent) == [36, 44])
    #expect(points.map(\.observedAt) == [latestFirstDay, secondDay])
    #expect(points[0].resetsAt == calendar.date(byAdding: .day, value: 4, to: firstDay))
    #expect(points[0].provenance == .localBudget)
    #expect(points[1].resetsAt == calendar.date(byAdding: .day, value: 5, to: firstDay))
    #expect(points[1].provenance == .estimated)
  }

  @Test
  func notificationKeysAreDurablyDeduplicated() throws {
    let repository = try SnapshotRepository.inMemory()

    try repository.markNotification("codex:weekly:80", at: Fixtures.now)
    try repository.markNotification("codex:weekly:80", at: Fixtures.day(1))

    #expect(try repository.hasNotification("codex:weekly:80"))
    #expect(try repository.notificationRecordCount() == 1)
  }

  @Test
  func clearHistoryRemovesUsageAndNotificationRecords() throws {
    let repository = try SnapshotRepository.inMemory()
    try repository.record(Fixtures.codexSnapshot())
    try repository.markNotification("codex:weekly:80", at: Fixtures.now)

    try repository.clearHistory()

    #expect(try repository.latest(provider: .codex) == nil)
    #expect(!(try repository.hasNotification("codex:weekly:80")))
    #expect(try repository.dailyUsageRecordCount() == 0)
  }
}
