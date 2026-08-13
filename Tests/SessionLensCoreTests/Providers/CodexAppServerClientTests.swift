import Foundation
import Testing
@testable import SessionLensCore

@Suite
struct CodexAppServerClientTests {
    @Test
    func foundationTransportRoundTripsOneJSONLine() async throws {
        let transport = FoundationJSONLTransport(
            executable: URL(fileURLWithPath: "/bin/cat"),
            arguments: []
        )
        try await transport.start()
        let object: [String: JSONValue] = [
            "id": .number(1),
            "method": .string("local/echo"),
        ]

        let echoed: [String: JSONValue]
        do {
            try await transport.send(object)
            echoed = try await transport.nextObject(timeout: .seconds(1))
        } catch {
            await transport.stop()
            throw error
        }
        await transport.stop()

        #expect(echoed == object)
    }

    @Test
    func foundationTransportIdleReadTimesOutPromptly() async throws {
        let transport = FoundationJSONLTransport(
            executable: URL(fileURLWithPath: "/bin/cat"),
            arguments: []
        )
        try await transport.start()
        let clock = ContinuousClock()
        let startedAt = clock.now
        var timedOut = false

        do {
            _ = try await transport.nextObject(timeout: .milliseconds(30))
        } catch JSONLTransportError.timedOut {
            timedOut = true
        }
        await transport.stop()

        #expect(timedOut)
        #expect(startedAt.duration(to: clock.now) < .seconds(1))
    }

    @Test
    func clientInitializesBeforeAccountRequests() async throws {
        let transport = FakeJSONLTransport(events: [
            .object(Fixtures.codexInitializeResponse(id: 1)),
            .object(Fixtures.codexRateLimitResponse(id: 2)),
        ])
        let client = CodexAppServerClient(transport: transport)

        _ = try await client.readRateLimits()
        let methods = await transport.sentMethods()
        let ids = await transport.sentRequestIDs()

        #expect(
            Array(methods.prefix(3))
                == ["initialize", "initialized", "account/rateLimits/read"]
        )
        #expect(ids == [1, 2])
    }

    @Test
    func clientNeverSendsThreadOrTranscriptMethods() async throws {
        let transport = FakeJSONLTransport(events: [
            .object(Fixtures.codexInitializeResponse(id: 1)),
            .object(Fixtures.codexUsageResponse(id: 2)),
        ])
        let client = CodexAppServerClient(transport: transport)

        _ = try await client.readUsage()
        let methods = Set(await transport.sentMethods())

        #expect(
            methods.isSubset(
                of: ["initialize", "initialized", "account/usage/read"]
            )
        )
        #expect(!methods.contains(where: { $0.contains("thread") }))
        #expect(!methods.contains(where: { $0.contains("turn") }))
        #expect(!methods.contains(where: { $0.contains("item") }))
    }

    @Test
    func clientIgnoresNotificationsWhileMatchingResponseID() async throws {
        let transport = FakeJSONLTransport(events: [
            .object(Fixtures.codexInitializeResponse(id: 1)),
            .object([
                "method": .string("thread/started"),
                "params": .object(["thread": .string("must-be-ignored")]),
            ]),
            .object(Fixtures.codexRateLimitResponse(id: 2)),
        ])
        let client = CodexAppServerClient(transport: transport)

        let response = try await client.readRateLimits()

        #expect(response.rateLimits.primary?.usedPercent == 42)
    }

    @Test
    func timeoutStopsTransportAndReconnectsNextRequest() async throws {
        let transport = FakeJSONLTransport(events: [
            .object(Fixtures.codexInitializeResponse(id: 1)),
            .timeout,
            .object(Fixtures.codexInitializeResponse(id: 3)),
            .object(Fixtures.codexRateLimitResponse(id: 4)),
        ])
        let client = CodexAppServerClient(transport: transport)

        var didThrow = false
        do {
            _ = try await client.readRateLimits()
        } catch {
            didThrow = true
        }
        let response = try await client.readRateLimits()

        #expect(didThrow)
        #expect(response.rateLimits.secondary?.usedPercent == 36)
        #expect(await transport.startCount() == 2)
        #expect(await transport.stopCount() == 1)
        #expect(await transport.sentRequestIDs() == [1, 2, 3, 4])
    }

    @Test
    func usageDTOIgnoresUnknownSensitiveFields() throws {
        let data = Data(
            #"""
            {
              "summary": {"lifetimeTokens": 10, "thread": "secret"},
              "dailyUsageBuckets": [],
              "transcript": "must-not-survive"
            }
            """#.utf8
        )

        let decoded = try JSONDecoder().decode(
            CodexAccountUsageResponse.self,
            from: data
        )
        let encoded = String(
            decoding: try JSONEncoder().encode(decoded),
            as: UTF8.self
        )

        #expect(decoded.summary.lifetimeTokens == 10)
        #expect(!encoded.contains("thread"))
        #expect(!encoded.contains("transcript"))
        #expect(!encoded.contains("secret"))
    }
}
