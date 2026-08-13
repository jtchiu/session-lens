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
