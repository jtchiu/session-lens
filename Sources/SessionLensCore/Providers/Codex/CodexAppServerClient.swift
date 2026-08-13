import Darwin
import Foundation

public enum JSONLTransportError: Error, Equatable {
    case notStarted
    case launchFailed
    case writeFailed
    case timedOut
    case endOfFile
    case malformedJSON
}

public protocol JSONLTransport: Sendable {
    func start() async throws
    func send(_ object: [String: JSONValue]) async throws
    func nextObject(timeout: Duration) async throws -> [String: JSONValue]
    func stop() async
}

public enum CodexAppServerClientError: Error, Equatable {
    case malformedResponse
    case serverError(code: Int?, message: String?)
}

public actor CodexAppServerClient: CodexAccountReading {
    private enum Method: String, CaseIterable {
        case initialize
        case initialized
        case readRateLimits = "account/rateLimits/read"
        case readUsage = "account/usage/read"
    }

    public nonisolated static let allowedMethods = Set(
        Method.allCases.map(\.rawValue)
    )

    private static let optOutNotificationMethods = [
        "thread/started",
        "thread/status/changed",
        "thread/archived",
        "thread/unarchived",
        "thread/closed",
        "thread/name/updated",
        "turn/started",
        "turn/completed",
        "turn/diff/updated",
        "turn/plan/updated",
        "item/started",
        "item/completed",
        "item/agentMessage/delta",
        "item/commandExecution/outputDelta",
        "item/fileChange/outputDelta",
        "item/mcpToolCall/progress",
        "item/reasoning/summaryTextDelta",
        "item/reasoning/summaryPartAdded",
        "item/reasoning/textDelta",
        "rawResponseItem/completed",
    ]

    private let transport: any JSONLTransport
    private let requestTimeout: Duration
    private var isConnected = false
    private var nextRequestID = 1
    private var requestLocked = false
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []

    public init(
        transport: any JSONLTransport,
        requestTimeout: Duration = .seconds(8)
    ) {
        self.transport = transport
        self.requestTimeout = requestTimeout
    }

    public func connect() async throws {
        await acquireRequestLock()
        defer { releaseRequestLock() }
        try await connectLocked()
    }

    public func readUsage() async throws -> CodexAccountUsageResponse {
        try await readAccountMethod(
            .readUsage,
            as: CodexAccountUsageResponse.self
        )
    }

    public func readRateLimits() async throws -> CodexRateLimitsResponse {
        try await readAccountMethod(
            .readRateLimits,
            as: CodexRateLimitsResponse.self
        )
    }

    public func shutdown() async {
        await acquireRequestLock()
        defer { releaseRequestLock() }
        await resetTransportLocked()
    }

    private func readAccountMethod<Response: Decodable>(
        _ method: Method,
        as type: Response.Type
    ) async throws -> Response {
        await acquireRequestLock()
        defer { releaseRequestLock() }

        do {
            try await connectLocked()
            let result = try await sendRequestLocked(method: method)
            let data = try JSONEncoder().encode(JSONValue.object(result))
            return try JSONDecoder().decode(type, from: data)
        } catch {
            await resetTransportLocked()
            throw error
        }
    }

    private func connectLocked() async throws {
        guard !isConnected else { return }
        do {
            try await transport.start()
            _ = try await sendRequestLocked(
                method: .initialize,
                params: [
                    "clientInfo": .object([
                        "name": .string("sessionlens"),
                        "title": .string("SessionLens"),
                        "version": .string("0.1.0"),
                    ]),
                    "capabilities": .object([
                        "experimentalApi": .bool(false),
                        "requestAttestation": .bool(false),
                        "optOutNotificationMethods": .array(
                            Self.optOutNotificationMethods.map(JSONValue.string)
                        ),
                    ]),
                ]
            )
            try await transport.send([
                "method": .string(Method.initialized.rawValue)
            ])
            isConnected = true
        } catch {
            await resetTransportLocked()
            throw error
        }
    }

    private func sendRequestLocked(
        method: Method,
        params: [String: JSONValue]? = nil
    ) async throws -> [String: JSONValue] {
        let requestID = nextRequestID
        nextRequestID += 1
        var request: [String: JSONValue] = [
            "id": .number(Double(requestID)),
            "method": .string(method.rawValue),
        ]
        if let params {
            request["params"] = .object(params)
        }
        try await transport.send(request)

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: requestTimeout)
        while true {
            let remaining = clock.now.duration(to: deadline)
            guard remaining > .zero else { throw JSONLTransportError.timedOut }
            let object = try await transport.nextObject(timeout: remaining)
            guard Self.requestID(in: object) == requestID else { continue }

            if case .object(let error)? = object["error"] {
                throw CodexAppServerClientError.serverError(
                    code: Self.integer(in: error["code"]),
                    message: Self.string(in: error["message"])
                )
            }
            guard case .object(let result)? = object["result"] else {
                throw CodexAppServerClientError.malformedResponse
            }
            return result
        }
    }

    private func acquireRequestLock() async {
        if !requestLocked {
            requestLocked = true
            return
        }
        await withCheckedContinuation { continuation in
            requestWaiters.append(continuation)
        }
    }

    private func releaseRequestLock() {
        if requestWaiters.isEmpty {
            requestLocked = false
        } else {
            requestWaiters.removeFirst().resume()
        }
    }

    private func resetTransportLocked() async {
        isConnected = false
        await transport.stop()
    }

    private static func requestID(in object: [String: JSONValue]) -> Int? {
        integer(in: object["id"])
    }

    private static func integer(in value: JSONValue?) -> Int? {
        guard case .number(let number)? = value,
            number.rounded(.towardZero) == number
        else {
            return nil
        }
        return Int(exactly: number)
    }

    private static func string(in value: JSONValue?) -> String? {
        guard case .string(let string)? = value else { return nil }
        return string
    }
}

public actor FoundationJSONLTransport: JSONLTransport {
    private let executable: URL
    private let arguments: [String]
    private var process: Process?
    private var standardInput: Pipe?
    private var standardOutput: Pipe?
    private var standardError: Pipe?
    private var lines: JSONLLineBuffer?

    public init(
        executable: URL,
        arguments: [String] = ["app-server", "--stdio"]
    ) {
        self.executable = executable
        self.arguments = arguments
    }

    public func start() async throws {
        guard process == nil else { return }

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let errorPipe = Pipe()
        let lines = JSONLLineBuffer()

        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errorPipe
        process.environment = ProcessInfo.processInfo.environment

        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                lines.finish()
            } else {
                lines.append(data)
            }
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }
        process.terminationHandler = { _ in lines.finish() }

        do {
            try process.run()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            lines.finish()
            throw JSONLTransportError.launchFailed
        }

        try? input.fileHandleForReading.close()
        try? output.fileHandleForWriting.close()
        try? errorPipe.fileHandleForWriting.close()
        self.process = process
        standardInput = input
        standardOutput = output
        standardError = errorPipe
        self.lines = lines
    }

    public func send(_ object: [String: JSONValue]) async throws {
        guard let standardInput else { throw JSONLTransportError.notStarted }
        do {
            var data = try JSONEncoder().encode(object)
            data.append(0x0A)
            try standardInput.fileHandleForWriting.write(contentsOf: data)
        } catch {
            throw JSONLTransportError.writeFailed
        }
    }

    public func nextObject(timeout: Duration) async throws -> [String: JSONValue] {
        guard let lines else { throw JSONLTransportError.notStarted }
        switch await lines.next(timeout: timeout) {
        case .line(let data):
            do {
                return try JSONDecoder().decode([String: JSONValue].self, from: data)
            } catch {
                throw JSONLTransportError.malformedJSON
            }
        case .timedOut:
            throw JSONLTransportError.timedOut
        case .endOfFile:
            throw JSONLTransportError.endOfFile
        }
    }

    public func stop() async {
        let process = self.process
        standardOutput?.fileHandleForReading.readabilityHandler = nil
        standardError?.fileHandleForReading.readabilityHandler = nil
        try? standardInput?.fileHandleForWriting.close()
        try? standardOutput?.fileHandleForReading.close()
        try? standardError?.fileHandleForReading.close()
        lines?.finish()

        if let process, process.isRunning {
            process.terminate()
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .milliseconds(100))
            while process.isRunning && clock.now < deadline {
                try? await Task.sleep(for: .milliseconds(5))
            }
            if process.isRunning {
                Darwin.kill(process.processIdentifier, SIGKILL)
            }
            process.waitUntilExit()
        }

        self.process = nil
        standardInput = nil
        standardOutput = nil
        standardError = nil
        lines = nil
    }
}

private final class JSONLLineBuffer: @unchecked Sendable {
    enum Outcome: Sendable {
        case line(Data)
        case timedOut
        case endOfFile
    }

    private let lock = NSLock()
    private var pending = Data()
    private var queuedLines: [Data] = []
    private var waiterOrder: [UUID] = []
    private var waiters: [UUID: CheckedContinuation<Outcome, Never>] = [:]
    private var finished = false

    func append(_ data: Data) {
        var deliveries: [(CheckedContinuation<Outcome, Never>, Outcome)] = []
        lock.lock()
        pending.append(data)
        while let newline = pending.firstIndex(of: 0x0A) {
            var line = Data(pending[..<newline])
            pending.removeSubrange(...newline)
            if line.last == 0x0D { line.removeLast() }
            guard !line.isEmpty else { continue }

            if let waiterID = waiterOrder.first {
                waiterOrder.removeFirst()
                if let continuation = waiters.removeValue(forKey: waiterID) {
                    deliveries.append((continuation, .line(line)))
                }
            } else {
                queuedLines.append(line)
            }
        }
        lock.unlock()
        for (continuation, outcome) in deliveries {
            continuation.resume(returning: outcome)
        }
    }

    func finish() {
        var continuations: [CheckedContinuation<Outcome, Never>] = []
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        continuations = Array(waiters.values)
        waiters.removeAll()
        waiterOrder.removeAll()
        lock.unlock()
        for continuation in continuations {
            continuation.resume(returning: .endOfFile)
        }
    }

    func next(timeout: Duration) async -> Outcome {
        let waiterID = UUID()
        return await withCheckedContinuation { continuation in
            lock.lock()
            if !queuedLines.isEmpty {
                let line = queuedLines.removeFirst()
                lock.unlock()
                continuation.resume(returning: .line(line))
                return
            }
            if finished {
                lock.unlock()
                continuation.resume(returning: .endOfFile)
                return
            }
            waiterOrder.append(waiterID)
            waiters[waiterID] = continuation
            lock.unlock()

            Task { [weak self] in
                try? await Task.sleep(for: max(.zero, timeout))
                self?.expire(waiterID)
            }
        }
    }

    private func expire(_ waiterID: UUID) {
        let continuation: CheckedContinuation<Outcome, Never>?
        lock.lock()
        continuation = waiters.removeValue(forKey: waiterID)
        waiterOrder.removeAll { $0 == waiterID }
        lock.unlock()
        continuation?.resume(returning: .timedOut)
    }
}
