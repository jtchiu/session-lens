import Foundation
import Testing
@testable import SessionLensCore

@Suite
struct OpenCodeProviderTests {
    @Test
    func sqlUsesOnlySessionAggregateColumns() {
        let sql = OpenCodeProvider.fixedAggregateSQL.lowercased()

        #expect(sql.contains("from session"))
        for forbidden in [
            "message", "part", "session_input", "prompt", "title", "directory",
            "credential", " data",
        ] {
            #expect(!sql.contains(forbidden), "forbidden SQL token: \(forbidden)")
        }
    }

    @Test
    func providerNormalizesSqliteJSONRows() async {
        let process = FakeProcessRunner(stdout: Fixtures.openCodeRowsJSON)
        let provider = OpenCodeProvider(
            databaseURL: Fixtures.openCodeDatabaseURL,
            process: process,
            sqliteURL: Fixtures.sqliteURL
        )

        let snapshot = await provider.refresh(at: Fixtures.now)

        #expect(snapshot.provider == .opencode)
        #expect(snapshot.health == .ready)
        #expect(snapshot.tokens?.total == 4_200)
        #expect(snapshot.costUSD == 1.25)
        #expect(snapshot.dailyBuckets.count == 2)
        #expect(snapshot.modelBreakdowns.count == 1)
        #expect(snapshot.quotaWindows.isEmpty)
    }

    @Test
    func providerRunsOnlyTheFixedReadOnlyQuery() async {
        let process = FakeProcessRunner(stdout: Data("[]".utf8))
        let provider = OpenCodeProvider(
            databaseURL: Fixtures.openCodeDatabaseURL,
            process: process,
            sqliteURL: Fixtures.sqliteURL
        )

        _ = await provider.refresh(at: Fixtures.now)
        let requests = await process.requests()

        #expect(requests.count == 1)
        #expect(requests.first?.executable == Fixtures.sqliteURL)
        #expect(
            requests.first?.arguments
                == [
                    "-readonly",
                    "-json",
                    Fixtures.openCodeDatabaseURL.path,
                    OpenCodeProvider.fixedAggregateSQL,
                ]
        )
        #expect(requests.first?.stdin.isEmpty == true)
    }

    @Test
    func missingDatabaseRequiresSetupWithoutLaunchingSqlite() async {
        let process = FakeProcessRunner(stdout: Fixtures.openCodeRowsJSON)
        let provider = OpenCodeProvider(
            databaseURL: URL(
                fileURLWithPath: "/definitely/not/a/sessionlens-opencode.db"
            ),
            process: process,
            sqliteURL: Fixtures.sqliteURL
        )

        let snapshot = await provider.refresh(at: Fixtures.now)

        #expect(snapshot.health == .setupRequired)
        #expect(snapshot.tokens == nil)
        #expect(await process.requests().isEmpty)
    }

    @Test
    func emptyDatabaseIsAReadyExactZeroAggregate() async {
        let provider = OpenCodeProvider(
            databaseURL: Fixtures.openCodeDatabaseURL,
            process: FakeProcessRunner(stdout: Data("[]".utf8)),
            sqliteURL: Fixtures.sqliteURL
        )

        let snapshot = await provider.refresh(at: Fixtures.now)

        #expect(snapshot.health == .ready)
        #expect(snapshot.tokens?.total == 0)
        #expect(snapshot.costUSD == 0)
        #expect(snapshot.dailyBuckets.isEmpty)
    }

    @Test
    func schemaDriftReturnsMalformedWithoutFabricatingZeroes() async {
        let provider = OpenCodeProvider(
            databaseURL: Fixtures.openCodeDatabaseURL,
            process: FakeProcessRunner(
                stderr: Data("no such column: tokens_reasoning".utf8),
                exitCode: 1
            ),
            sqliteURL: Fixtures.sqliteURL
        )

        let snapshot = await provider.refresh(at: Fixtures.now)

        #expect(snapshot.health == .malformedData)
        #expect(snapshot.tokens == nil)
        #expect(snapshot.costUSD == nil)
    }

    @Test
    func busyDatabaseRetriesOnceBeforeReturningNormalizedRows() async {
        let process = FakeProcessRunner(results: [
            ProcessResult(
                stdout: Data(),
                stderr: Data("database is locked".utf8),
                termination: .exited(1)
            ),
            ProcessResult(
                stdout: Fixtures.openCodeRowsJSON,
                stderr: Data(),
                termination: .exited(0)
            ),
        ])
        let provider = OpenCodeProvider(
            databaseURL: Fixtures.openCodeDatabaseURL,
            process: process,
            sqliteURL: Fixtures.sqliteURL
        )

        let snapshot = await provider.refresh(at: Fixtures.now)

        #expect(snapshot.health == .ready)
        #expect(snapshot.costUSD == 1.25)
        #expect((await process.requests()).count == 2)
    }

    @Test
    func processTimeoutReturnsUnavailableWithoutFabricatingMetrics() async {
        let provider = OpenCodeProvider(
            databaseURL: Fixtures.openCodeDatabaseURL,
            process: FakeProcessRunner(
                result: ProcessResult(
                    stdout: Data(),
                    stderr: Data(),
                    termination: .timedOut
                )
            ),
            sqliteURL: Fixtures.sqliteURL
        )

        let snapshot = await provider.refresh(at: Fixtures.now)

        #expect(snapshot.health == .timedOut)
        #expect(snapshot.tokens == nil)
        #expect(snapshot.costUSD == nil)
    }
}
