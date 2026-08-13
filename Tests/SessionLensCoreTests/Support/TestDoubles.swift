import Foundation
@testable import SessionLensCore

final class FakeExecutableFileSystem: ExecutableFileSystem, @unchecked Sendable {
    private let executablePaths: Set<String>
    private let lock = NSLock()
    private var recordedProbes: [String] = []

    init(executablePaths: Set<String>) {
        self.executablePaths = executablePaths
    }

    var probedPaths: [String] {
        lock.withLock { recordedProbes }
    }

    func isExecutableFile(atPath path: String) -> Bool {
        lock.withLock {
            recordedProbes.append(path)
            return executablePaths.contains(path)
        }
    }
}

actor FakeProcessRunner: ProcessExecuting {
    private let result: ProcessResult
    private var recordedRequests: [ProcessRequest] = []

    init(
        stdout: Data = Data(),
        stderr: Data = Data(),
        exitCode: Int32 = 0
    ) {
        self.result = ProcessResult(
            stdout: stdout,
            stderr: stderr,
            termination: .exited(exitCode)
        )
    }

    init(result: ProcessResult) {
        self.result = result
    }

    func run(_ request: ProcessRequest) async -> ProcessResult {
        recordedRequests.append(request)
        return result
    }

    func requests() -> [ProcessRequest] {
        recordedRequests
    }
}

enum FakeJSONLEvent: Sendable {
    case object([String: JSONValue])
    case timeout
    case endOfFile
    case malformed
}

actor FakeJSONLTransport: JSONLTransport {
    private var events: [FakeJSONLEvent]
    private var sentObjects: [[String: JSONValue]] = []
    private var starts = 0
    private var stops = 0

    init(events: [FakeJSONLEvent]) {
        self.events = events
    }

    func start() async throws {
        starts += 1
    }

    func send(_ object: [String: JSONValue]) async throws {
        sentObjects.append(object)
    }

    func nextObject(timeout: Duration) async throws -> [String: JSONValue] {
        guard !events.isEmpty else { throw JSONLTransportError.endOfFile }
        switch events.removeFirst() {
        case let .object(object):
            return object
        case .timeout:
            throw JSONLTransportError.timedOut
        case .endOfFile:
            throw JSONLTransportError.endOfFile
        case .malformed:
            throw JSONLTransportError.malformedJSON
        }
    }

    func stop() async {
        stops += 1
    }

    func sentMethods() -> [String] {
        sentObjects.compactMap { object in
            guard case let .string(method) = object["method"] else { return nil }
            return method
        }
    }

    func sentRequestIDs() -> [Int] {
        sentObjects.compactMap { object in
            guard case let .number(id) = object["id"] else { return nil }
            return Int(id)
        }
    }

    func startCount() -> Int { starts }
    func stopCount() -> Int { stops }
}

struct FakeCodexClient: CodexAccountReading {
    enum Failure: Error {
        case requested
    }

    let rateLimits: CodexRateLimitsResponse
    let usage: CodexAccountUsageResponse
    let failsRateLimits: Bool
    let failsUsage: Bool

    init(
        rateLimits: CodexRateLimitsResponse = Fixtures.codexTwoWindowLimits,
        usage: CodexAccountUsageResponse = Fixtures.codexUsage,
        failsRateLimits: Bool = false,
        failsUsage: Bool = false
    ) {
        self.rateLimits = rateLimits
        self.usage = usage
        self.failsRateLimits = failsRateLimits
        self.failsUsage = failsUsage
    }

    func readUsage() async throws -> CodexAccountUsageResponse {
        if failsUsage { throw Failure.requested }
        return usage
    }

    func readRateLimits() async throws -> CodexRateLimitsResponse {
        if failsRateLimits { throw Failure.requested }
        return rateLimits
    }
}

final class FakeClaudeBridgeStore: ClaudeCacheStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var caches: [ClaudeNormalizedCache?]

    init(caches: [ClaudeNormalizedCache?]) {
        self.caches = caches
    }

    func read() throws -> ClaudeNormalizedCache? {
        lock.withLock {
            guard !caches.isEmpty else { return nil }
            return caches.removeFirst()
        }
    }

    func write(_ cache: ClaudeNormalizedCache) throws {
        lock.withLock {
            caches.append(cache)
        }
    }
}
