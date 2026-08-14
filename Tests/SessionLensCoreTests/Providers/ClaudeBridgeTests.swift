import Foundation
import Testing
@testable import SessionLensCore

@Suite
struct ClaudeBridgeTests {
    @Test
    func statusPayloadDecodingCannotRepresentSensitiveFields() throws {
        let payload = try JSONDecoder().decode(
            ClaudeStatusPayload.self,
            from: Fixtures.claudeOfficialStatusLineJSON
        )
        let normalized = payload.normalized(observedAt: Fixtures.now)
        let encoded = try JSONEncoder().encode(normalized)
        let text = String(decoding: encoded, as: UTF8.self)

        #expect(normalized.sessionHash.count == 64)
        #expect(!text.contains("session-secret"))
        for forbidden in [
            "cwd", "transcript", "workspace", "session_name", "prompt",
            "source", "git", "agent",
        ] {
            #expect(!text.contains(forbidden), "persisted forbidden field: \(forbidden)")
        }

        let object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        #expect(Set(object.keys).isSubset(of: ClaudeNormalizedCache.allowedKeys))
    }

    @Test
    func normalizationKeepsOnlyDocumentedAggregateValues() throws {
        let payload = try JSONDecoder().decode(
            ClaudeStatusPayload.self,
            from: Fixtures.claudeOfficialStatusLineJSON
        )

        let cache = payload.normalized(observedAt: Fixtures.now)

        #expect(cache.modelID == "claude-opus-4-1")
        #expect(cache.modelDisplayName == "Opus 4.1")
        #expect(cache.contextTokens?.input == 8_500)
        #expect(cache.contextTokens?.output == 1_200)
        #expect(cache.contextTokens?.cacheWrite == 5_000)
        #expect(cache.contextTokens?.cacheRead == 2_000)
        #expect(cache.contextTokens?.total == 16_700)
        #expect(cache.reportedSessionTokenTotal == 16_700)
        #expect(cache.estimatedSessionCostUSD == 0.01234)
        #expect(cache.fiveHour?.usedPercent == 23.5)
        #expect(cache.sevenDay?.usedPercent == 41.2)
        #expect(cache.version == "2.1.90")
    }

    @Test
    func liveContextTokensAreNotMisrepresentedAsCumulativeDeltas() async {
        let secondCache = Fixtures.claudeCache(
            tokens: 140,
            sessionCostUSD: 1.4,
            reportedSessionTokenTotal: 140
        )
        let store = FakeClaudeBridgeStore(
            caches: [
                Fixtures.claudeCache(tokens: 100, sessionCostUSD: 1.0),
                secondCache,
            ]
        )
        let provider = ClaudeProvider(store: store)

        _ = await provider.refresh(at: Fixtures.now)
        let second = await provider.refresh(
            at: Fixtures.now.addingTimeInterval(60)
        )

        #expect(second.tokens?.total == 140)
        #expect(second.costDisplay == .estimatedUSD(1.4))
        #expect(second.costSample?.provider == .claude)
        #expect(second.costSample?.scopeID == secondCache.sessionHash)
        #expect(second.costSample?.cumulativeCostUSD == 1.4)
        #expect(second.costSample?.cumulativeTokens == 140)
        #expect(second.dailyBuckets.isEmpty)
    }

    @Test
    func liveContextOnlyPayloadDoesNotCreateHistoricalTokenTotal() throws {
        let payload = try JSONDecoder().decode(
            ClaudeStatusPayload.self,
            from: Data(
                #"""
                {
                  "session_id": "session-secret",
                  "cost": {"total_cost_usd": 1.0},
                  "context_window": {
                    "current_usage": {
                      "input_tokens": 8500,
                      "output_tokens": 1200,
                      "cache_creation_input_tokens": 5000,
                      "cache_read_input_tokens": 2000
                    }
                  }
                }
                """#.utf8
            )
        )

        #expect(payload.normalized(observedAt: Fixtures.now).reportedSessionTokenTotal == nil)
    }

    @Test
    func resetCostBecomesFreshEstimatedValueNotNegativeDelta() async {
        let store = FakeClaudeBridgeStore(
            caches: [
                Fixtures.claudeCache(tokens: 140, sessionCostUSD: 1.4),
                Fixtures.claudeCache(
                    tokens: 20,
                    sessionCostUSD: 0.2,
                    sessionHash: "new-session-hash"
                ),
            ]
        )
        let provider = ClaudeProvider(store: store)

        _ = await provider.refresh(at: Fixtures.now)
        let reset = await provider.refresh(
            at: Fixtures.now.addingTimeInterval(60)
        )

        #expect(reset.tokens?.total == 20)
        #expect(reset.costDisplay == .estimatedUSD(0.2))
        #expect(reset.costUSD == 0.2)
    }

    @Test
    func staleCachePreservesValuesButMarksProviderAndQuotasStale() async {
        let cache = Fixtures.claudeCache(
            tokens: 100,
            sessionCostUSD: 0.5,
            observedAt: Fixtures.now
        )
        let provider = ClaudeProvider(
            store: FakeClaudeBridgeStore(caches: [cache])
        )

        let snapshot = await provider.refresh(
            at: Fixtures.now.addingTimeInterval(301)
        )

        #expect(snapshot.health == .stale)
        #expect(snapshot.tokens?.total == 100)
        #expect(snapshot.quotaWindows.allSatisfy { $0.provenance == .stale })
    }

    @Test
    func missingCacheRequiresExplicitBridgeSetup() async {
        let provider = ClaudeProvider(
            store: FakeClaudeBridgeStore(caches: [nil])
        )

        let snapshot = await provider.refresh(at: Fixtures.now)

        #expect(snapshot.health == .setupRequired)
        #expect(snapshot.tokens == nil)
        #expect(snapshot.costDisplay == .unavailable)
    }

    @Test
    func bridgeStoreRoundTripsAtomicallyWithUserOnlyPermissions() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ClaudeBridgeStore(bridgeDirectory: root)
        let cache = Fixtures.claudeCache(tokens: 123, sessionCostUSD: 0.75)

        try store.write(cache)

        #expect(try store.read() == cache)
        let directoryMode = try permissionMode(at: root)
        let fileMode = try permissionMode(at: store.cacheURL)
        #expect(directoryMode == 0o700)
        #expect(fileMode == 0o600)
    }

    @Test
    func forwarderWithoutPreviousCommandReturnsNoOutput() async throws {
        let process = FakeProcessRunner(stdout: Data("unexpected".utf8))
        let forwarder = ExistingStatusLineForwarder(
            configurationURL: URL(fileURLWithPath: "/definitely/not/config.json"),
            process: process
        )

        let output = try await forwarder.forward(originalInput: Data("{}".utf8))

        #expect(output.isEmpty)
        #expect(await process.requests().isEmpty)
    }

    @Test
    func forwarderSendsUntouchedJSONAndReturnsOnlyPriorStdout() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let configurationURL = directory.appendingPathComponent("config.json")
        let configuration = ClaudeBridgeConfiguration(
            previousCommand: "~/.claude/statusline.sh"
        )
        try JSONEncoder().encode(configuration).write(to: configurationURL)
        let original = Fixtures.claudeOfficialStatusLineJSON
        let process = FakeProcessRunner(
            stdout: Data("legacy output\n".utf8),
            stderr: Data("private diagnostic".utf8)
        )
        let forwarder = ExistingStatusLineForwarder(
            configurationURL: configurationURL,
            process: process
        )

        let output = try await forwarder.forward(originalInput: original)
        let requests = await process.requests()

        #expect(output == Data("legacy output\n".utf8))
        #expect(requests.count == 1)
        #expect(requests.first?.executable.path == "/bin/zsh")
        #expect(requests.first?.arguments == ["-lc", "~/.claude/statusline.sh"])
        #expect(requests.first?.stdin == original)
    }

    @Test
    func bridgePipelineForwardsEvenWhenPayloadCaptureFails() async {
        let input = Data("malformed".utf8)
        let output = await ClaudeBridgePipeline.captureAndForward(
            input: input,
            capture: { _ in throw ClaudeBridgeInstallError.invalidSettings },
            forward: { input }
        )

        #expect(output == input)
    }

    private func permissionMode(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let number = try #require(attributes[.posixPermissions] as? NSNumber)
        return number.intValue & 0o777
    }
}
