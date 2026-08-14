import Foundation
import Testing

@testable import SessionLensCore

@Suite
struct PricingCatalogClientTests {
    @Test
    func decoderKeepsUsableRatesAndIgnoresUnrelatedFields() throws {
        let catalog = try PricingCatalogDecoder.decode(
            PricingFixtures.catalogJSON,
            fetchedAt: PricingFixtures.day(1)
        )

        #expect(catalog.models == PricingFixtures.catalog.models)
        #expect(catalog.updatedAt == PricingFixtures.day(0))
    }

    @Test
    func decoderRetainsValidSiblingFieldsAndModelsWhenKnownFieldsAreMalformed() throws {
        let catalog = try PricingCatalogDecoder.decode(
            PricingFixtures.lossyCatalogJSON,
            fetchedAt: PricingFixtures.day(1)
        )

        #expect(catalog.models.count == 2)
        #expect(catalog.model(providerID: "lossy", modelID: "kept-input")?.rate == .init(inputPerMillion: 4))
        #expect(catalog.model(providerID: "lossy", modelID: "kept-output")?.rate == .init(outputPerMillion: 7))
        #expect(catalog.model(providerID: "lossy", modelID: "discarded") == nil)
    }

    @Test
    func freshCacheAvoidsTransport() async throws {
        let transport = FakePricingTransport(response: .failure(FakePricingTransport.Failure.requested))
        let cacheURL = try TestCacheFile.write(PricingFixtures.cacheData())
        defer { TestCacheFile.remove(cacheURL) }
        let client = PricingCatalogClient(
            cacheURL: cacheURL,
            transport: transport,
            now: { PricingFixtures.day(1) },
            ttl: 86_400
        )

        let state = await client.refreshIfNeeded(now: PricingFixtures.day(1))

        #expect(state.source == .cached)
        #expect(state.catalog?.models == PricingFixtures.catalog.models)
        #expect(await transport.fetchCount() == 0)
    }

    @Test
    func liveResponseNormalizesAndPersistsCatalog() async throws {
        let cacheURL = TestCacheFile.emptyURL()
        defer { TestCacheFile.remove(cacheURL) }
        let client = PricingCatalogClient(
            cacheURL: cacheURL,
            transport: FakePricingTransport(
                response: .response(.init(
                    statusCode: 200,
                    data: PricingFixtures.catalogJSON,
                    etag: "live-etag",
                    lastModified: "Wed, 01 Jan 2025 00:00:00 GMT"
                ))
            ),
            now: { PricingFixtures.day(1) }
        )

        let state = await client.refreshIfNeeded(now: PricingFixtures.day(1))
        let persistedCache = try PricingCacheRecord.decode(Data(contentsOf: cacheURL))

        #expect(state.source == .live)
        #expect(state.catalog == PricingFixtures.catalog)
        #expect(persistedCache.sourceURL == URLSessionPricingCatalogTransport.endpoint.absoluteString)
        #expect(persistedCache.etag == "live-etag")
        #expect(persistedCache.lastModified == "Wed, 01 Jan 2025 00:00:00 GMT")
    }

    @Test
    func staleCacheUsesConditionalFetchAndKeepsCatalogOnFailure() async throws {
        let transport = FakePricingTransport(
            response: .response(.init(statusCode: 503, data: Data(), etag: nil, lastModified: nil))
        )
        let cacheURL = try TestCacheFile.write(PricingFixtures.cacheData())
        defer { TestCacheFile.remove(cacheURL) }
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
        let persistedCache = try PricingCacheRecord.decode(Data(contentsOf: cacheURL))
        #expect(persistedCache.catalog == PricingFixtures.catalog)
        #expect(persistedCache.etag == "fixture-etag")
        #expect(persistedCache.validatedAt == PricingFixtures.day(1))
    }

    @Test
    func notModifiedResponseKeepsCachedCatalog() async throws {
        let transport = FakePricingTransport(
            response: .response(.init(statusCode: 304, data: Data(), etag: "new-etag", lastModified: nil))
        )
        let cacheURL = try TestCacheFile.write(PricingFixtures.cacheData())
        defer { TestCacheFile.remove(cacheURL) }
        let client = PricingCatalogClient(
            cacheURL: cacheURL,
            transport: transport,
            now: { PricingFixtures.day(2) },
            ttl: 86_400
        )

        let state = await client.refreshIfNeeded(now: PricingFixtures.day(2))

        #expect(state.source == .cached)
        #expect(state.catalog == PricingFixtures.catalog)
        #expect(try PricingCacheRecord.decode(Data(contentsOf: cacheURL)).etag == "new-etag")
    }

    @Test
    func nonSuccessWithoutCacheIsUnavailable() async throws {
        let state = await unavailableState(
            response: .response(.init(statusCode: 500, data: Data(), etag: nil, lastModified: nil))
        )

        #expect(state.source == .unavailable)
        #expect(state.catalog == nil)
        #expect(state.message != nil)
    }

    @Test
    func transportFailureWithoutCacheIsUnavailable() async throws {
        let state = await unavailableState(response: .failure(FakePricingTransport.Failure.requested))

        #expect(state.source == .unavailable)
        #expect(state.catalog == nil)
        #expect(state.message != nil)
    }

    @Test
    func staleCacheSurvivesTransportFailure() async throws {
        let cacheURL = try TestCacheFile.write(PricingFixtures.cacheData())
        defer { TestCacheFile.remove(cacheURL) }
        let client = PricingCatalogClient(
            cacheURL: cacheURL,
            transport: FakePricingTransport(response: .failure(FakePricingTransport.Failure.requested)),
            now: { PricingFixtures.day(2) },
            ttl: 86_400
        )

        let state = await client.refreshIfNeeded(now: PricingFixtures.day(2))

        #expect(state.source == .cached)
        #expect(state.catalog == PricingFixtures.catalog)
        #expect(try PricingCacheRecord.decode(Data(contentsOf: cacheURL)).etag == "fixture-etag")
    }

    @Test
    func invalidJSONWithoutCacheIsUnavailable() async throws {
        let state = await unavailableState(
            response: .response(.init(statusCode: 200, data: Data("not-json".utf8), etag: nil, lastModified: nil))
        )

        #expect(state.source == .unavailable)
        #expect(state.catalog == nil)
        #expect(state.message != nil)
    }

    @Test
    func staleCacheSurvivesInvalidJSON() async throws {
        let cacheURL = try TestCacheFile.write(PricingFixtures.cacheData())
        defer { TestCacheFile.remove(cacheURL) }
        let client = PricingCatalogClient(
            cacheURL: cacheURL,
            transport: FakePricingTransport(
                response: .response(.init(statusCode: 200, data: Data("not-json".utf8), etag: nil, lastModified: nil))
            ),
            now: { PricingFixtures.day(2) },
            ttl: 86_400
        )

        let state = await client.refreshIfNeeded(now: PricingFixtures.day(2))

        #expect(state.source == .cached)
        #expect(state.catalog == PricingFixtures.catalog)
        #expect(try PricingCacheRecord.decode(Data(contentsOf: cacheURL)).etag == "fixture-etag")
    }

    private func unavailableState(response: FakePricingTransport.Response) async -> PricingCatalogState {
        let cacheURL = TestCacheFile.emptyURL()
        defer { TestCacheFile.remove(cacheURL) }
        let client = PricingCatalogClient(
            cacheURL: cacheURL,
            transport: FakePricingTransport(response: response),
            now: { PricingFixtures.day(1) }
        )

        return await client.refreshIfNeeded(now: PricingFixtures.day(1))
    }

    @Test
    func stateReadsCacheWithoutNetwork() async throws {
        let transport = FakePricingTransport(response: .failure(FakePricingTransport.Failure.requested))
        let cacheURL = try TestCacheFile.write(PricingFixtures.cacheData())
        defer { TestCacheFile.remove(cacheURL) }
        let client = PricingCatalogClient(
            cacheURL: cacheURL,
            transport: transport,
            now: { PricingFixtures.day(2) }
        )

        let state = await client.state(now: PricingFixtures.day(2))

        #expect(state.source == .cached)
        #expect(state.catalog == PricingFixtures.catalog)
        #expect(await transport.fetchCount() == 0)
    }

    @Test
    func catalogRefreshRecomputesApiEquivalentSpendWithoutChangingActualSpendOrSnapshots() async throws {
        let now = PricingFixtures.day(1)
        let snapshot = ProviderSnapshot(
            provider: .opencode,
            observedAt: now,
            health: .ready,
            tokens: nil,
            costDisplay: .exactUSD(7),
            dailyBuckets: [],
            quotaWindows: [],
            modelBreakdowns: [
                ModelUsage(
                    providerID: "openai",
                    modelID: "gpt-test",
                    tokens: TokenBreakdown(
                        input: 1_000_000,
                        output: 0,
                        reasoning: 0,
                        cacheRead: 0,
                        cacheWrite: 0
                    ),
                    costUSD: 7
                )
            ]
        )
        let snapshots: [ProviderID: ProviderSnapshot] = [.opencode: snapshot]
        let dailyBuckets: [ProviderID: [UsageBucket]] = [
            .opencode: [UsageBucket(day: now, tokens: 1_000_000, costUSD: 7)]
        ]
        let unavailableCacheURL = TestCacheFile.emptyURL()
        defer { TestCacheFile.remove(unavailableCacheURL) }
        let unavailableClient = PricingCatalogClient(
            cacheURL: unavailableCacheURL,
            transport: FakePricingTransport(response: .failure(FakePricingTransport.Failure.timeout)),
            now: { now }
        )

        let unavailableState = await unavailableClient.refreshIfNeeded(now: now)
        let unavailableSummary = SpendSummaryLoader.makeSummary(
            now: now,
            historyRetentionDays: 30,
            snapshots: snapshots,
            dailyBuckets: dailyBuckets,
            samples: [],
            catalogState: unavailableState
        )

        let liveCacheURL = TestCacheFile.emptyURL()
        defer { TestCacheFile.remove(liveCacheURL) }
        let liveClient = PricingCatalogClient(
            cacheURL: liveCacheURL,
            transport: FakePricingTransport(
                response: .response(.init(
                    statusCode: 200,
                    data: PricingFixtures.catalogJSON,
                    etag: nil,
                    lastModified: nil
                ))
            ),
            now: { now }
        )
        let liveState = await liveClient.refreshIfNeeded(now: now)
        let liveSummary = SpendSummaryLoader.makeSummary(
            now: now,
            historyRetentionDays: 30,
            snapshots: snapshots,
            dailyBuckets: dailyBuckets,
            samples: [],
            catalogState: liveState
        )

        #expect(unavailableState.source == .unavailable)
        #expect(unavailableSummary.providers[.opencode]?.week.costUSD == 7)
        #expect(unavailableSummary.apiEquivalent.providers[.opencode]?.week.costUSD == nil)
        #expect(liveState.source == .live)
        #expect(liveSummary.providers[.opencode]?.week.costUSD == 7)
        #expect(liveSummary.apiEquivalent.providers[.opencode]?.week.costUSD == 1.5)
        #expect(snapshots == [.opencode: snapshot])
    }
}

private enum PricingFixtures {
    static func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_735_689_600 + Double(offset * 86_400))
    }

    static let catalogJSON = Data(
        #"""
        {
          "updated_at": "2025-01-01T00:00:00Z",
          "openai": {
            "id": "openai",
            "models": {
              "gpt-test": {
                "id": "gpt-test",
                "cost": {"input": 1.5, "output": 6, "cache_read": 0.3, "extra": 100},
                "unknown": "ignored"
              },
              "discarded": {"id": "discarded", "cost": {"input": -1}}
            }
          },
          "anthropic": {
            "models": {
              "claude-test": {
                "cost": {"input": 3, "output": 15, "reasoning": 8, "cache_write": 3.75}
              }
            }
          },
          "unrelated": ["ignored"]
        }
        """#.utf8
    )

    static let lossyCatalogJSON = Data(
        #"""
        {
          "lossy": {
            "id": "lossy",
            "models": {
              "kept-output": {
                "id": "kept-output",
                "cost": {"input": "bad", "output": 7, "cache_read": "also-bad"}
              },
              "kept-input": {
                "id": "kept-input",
                "cost": {"input": 4, "output": []}
              },
              "discarded": {
                "id": "discarded",
                "cost": {"input": "bad", "output": -2}
              },
              "malformed-model": "not-an-object"
            }
          }
        }
        """#.utf8
    )

    static let catalog = PricingCatalog(
        models: [
            .init(
                providerID: "anthropic",
                modelID: "claude-test",
                rate: .init(inputPerMillion: 3, outputPerMillion: 15, reasoningPerMillion: 8, cacheWritePerMillion: 3.75)
            ),
            .init(
                providerID: "openai",
                modelID: "gpt-test",
                rate: .init(inputPerMillion: 1.5, outputPerMillion: 6, cacheReadPerMillion: 0.3)
            ),
        ],
        updatedAt: day(0),
        fetchedAt: day(1)
    )

    static func cacheData() throws -> Data {
        try PricingCacheRecord(catalog: catalog, etag: "fixture-etag", lastModified: "Wed, 01 Jan 2025 00:00:00 GMT").encode()
    }
}

private actor FakePricingTransport: PricingCatalogTransport {
    enum Failure: Error { case requested, timeout }

    enum Response: Sendable {
        case response(PricingCatalogHTTPResponse)
        case failure(Failure)
    }

    private let response: Response
    private var etags: [String?] = []

    init(response: Response) {
        self.response = response
    }

    func fetch(ifNoneMatch: String?) async throws -> PricingCatalogHTTPResponse {
        etags.append(ifNoneMatch)
        switch response {
        case let .response(response): return response
        case .failure: throw Failure.requested
        }
    }

    func fetchCount() -> Int { etags.count }
    func lastETag() -> String? { etags.last ?? nil }
}

private enum TestCacheFile {
    static func emptyURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("pricing-catalog-\(UUID().uuidString).json")
    }

    static func write(_ data: Data) throws -> URL {
        let url = emptyURL()
        try data.write(to: url)
        return url
    }

    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
