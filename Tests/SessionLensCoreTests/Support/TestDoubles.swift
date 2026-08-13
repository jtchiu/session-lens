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
