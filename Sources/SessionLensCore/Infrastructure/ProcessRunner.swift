import Darwin
import Foundation

public struct ProcessRequest: Sendable {
    public let executable: URL
    public let arguments: [String]
    public let stdin: Data
    public let timeout: Duration
    public let environment: [String: String]

    public init(
        executable: URL,
        arguments: [String] = [],
        stdin: Data = Data(),
        timeout: Duration = .seconds(5),
        environment: [String: String] = [:]
    ) {
        self.executable = executable
        self.arguments = arguments
        self.stdin = stdin
        self.timeout = timeout
        self.environment = environment
    }
}

public struct ProcessResult: Sendable, Equatable {
    public enum Termination: Sendable, Equatable {
        case exited(Int32)
        case timedOut
        case launchFailed
    }

    public let stdout: Data
    public let stderr: Data
    public let termination: Termination

    public init(stdout: Data, stderr: Data, termination: Termination) {
        self.stdout = stdout
        self.stderr = stderr
        self.termination = termination
    }
}

public protocol ProcessExecuting: Sendable {
    func run(_ request: ProcessRequest) async -> ProcessResult
}

public struct FoundationProcessRunner: ProcessExecuting {
    private let stdoutLimit: Int
    private let stderrLimit: Int
    private let pollingInterval: Duration
    private let terminationGracePeriod: Duration

    public init(
        stderrLimit: Int,
        stdoutLimit: Int = 16 * 1_024 * 1_024,
        pollingInterval: Duration = .milliseconds(5),
        terminationGracePeriod: Duration = .milliseconds(100)
    ) {
        self.stdoutLimit = max(0, stdoutLimit)
        self.stderrLimit = max(0, stderrLimit)
        self.pollingInterval = pollingInterval
        self.terminationGracePeriod = terminationGracePeriod
    }

    public func run(_ request: ProcessRequest) async -> ProcessResult {
        let process = Process()
        let standardInput = Pipe()
        let standardOutput = Pipe()
        let standardError = Pipe()

        process.executableURL = request.executable
        process.arguments = request.arguments
        process.standardInput = standardInput
        process.standardOutput = standardOutput
        process.standardError = standardError
        process.environment = ProcessInfo.processInfo.environment.merging(
            request.environment,
            uniquingKeysWith: { _, override in override }
        )

        let stdoutHandle = SendableFileHandle(standardOutput.fileHandleForReading)
        let stderrHandle = SendableFileHandle(standardError.fileHandleForReading)
        let stdoutLimit = self.stdoutLimit
        let stderrLimit = self.stderrLimit
        let stdoutTask = Task.detached(priority: .utility) {
            Self.drain(stdoutHandle, retainingAtMost: stdoutLimit)
        }
        let stderrTask = Task.detached(priority: .utility) {
            Self.drain(stderrHandle, retainingAtMost: stderrLimit)
        }

        do {
            try process.run()
        } catch {
            Self.closeUnusedPipeEnds(
                standardInput: standardInput,
                standardOutput: standardOutput,
                standardError: standardError
            )
            return await ProcessResult(
                stdout: stdoutTask.value,
                stderr: stderrTask.value,
                termination: .launchFailed
            )
        }

        try? standardInput.fileHandleForReading.close()
        try? standardOutput.fileHandleForWriting.close()
        try? standardError.fileHandleForWriting.close()
        if !request.stdin.isEmpty {
            try? standardInput.fileHandleForWriting.write(contentsOf: request.stdin)
        }
        try? standardInput.fileHandleForWriting.close()

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: max(.zero, request.timeout))
        while process.isRunning && clock.now < deadline {
            try? await Task.sleep(for: pollingInterval)
        }

        let timedOut = process.isRunning
        if timedOut {
            process.terminate()
            let graceDeadline = clock.now.advanced(by: terminationGracePeriod)
            while process.isRunning && clock.now < graceDeadline {
                try? await Task.sleep(for: pollingInterval)
            }
            if process.isRunning {
                Darwin.kill(process.processIdentifier, SIGKILL)
            }
        }

        process.waitUntilExit()
        let stdout = await stdoutTask.value
        let stderr = await stderrTask.value

        return ProcessResult(
            stdout: stdout,
            stderr: stderr,
            termination: timedOut ? .timedOut : .exited(process.terminationStatus)
        )
    }

    private static func drain(
        _ handle: SendableFileHandle,
        retainingAtMost limit: Int
    ) -> Data {
        defer { try? handle.value.close() }
        var retained = Data()

        while true {
            let chunk: Data
            do {
                guard let next = try handle.value.read(upToCount: 64 * 1_024),
                    !next.isEmpty
                else {
                    break
                }
                chunk = next
            } catch {
                break
            }

            let remaining = limit - retained.count
            guard remaining > 0 else { continue }
            retained.append(contentsOf: chunk.prefix(remaining))
        }

        return retained
    }

    private static func closeUnusedPipeEnds(
        standardInput: Pipe,
        standardOutput: Pipe,
        standardError: Pipe
    ) {
        try? standardInput.fileHandleForReading.close()
        try? standardInput.fileHandleForWriting.close()
        try? standardOutput.fileHandleForWriting.close()
        try? standardError.fileHandleForWriting.close()
    }
}

private final class SendableFileHandle: @unchecked Sendable {
    let value: FileHandle

    init(_ value: FileHandle) {
        self.value = value
    }
}
