import Foundation
import Testing

@testable import SessionLensCore

@Suite
@MainActor
struct SnapshotRepositoryTests {
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
