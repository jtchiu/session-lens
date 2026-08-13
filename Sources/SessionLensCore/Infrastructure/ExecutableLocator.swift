import Foundation

public enum ToolExecutable: String, Sendable {
    case opencode
    case claude
    case codex
    case sqlite3

    fileprivate var executableName: String { rawValue }

    fileprivate var fixedCandidates: [String] {
        switch self {
        case .opencode:
            ["/opt/homebrew/bin/opencode", "/usr/local/bin/opencode"]
        case .claude:
            ["/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        case .codex:
            [
                "/Applications/ChatGPT.app/Contents/Resources/codex",
                "/opt/homebrew/bin/codex",
                "/usr/local/bin/codex",
            ]
        case .sqlite3:
            ["/usr/bin/sqlite3"]
        }
    }
}

public protocol ExecutableFileSystem: Sendable {
    func isExecutableFile(atPath path: String) -> Bool
}

public struct FoundationExecutableFileSystem: ExecutableFileSystem {
    public init() {}

    public func isExecutableFile(atPath path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }
}

public protocol ExecutableLocating: Sendable {
    func resolve(_ executable: ToolExecutable) -> URL?
    func candidates(_ executable: ToolExecutable) -> [URL]
}

public struct ExecutableLocator: ExecutableLocating {
    private let fileSystem: any ExecutableFileSystem
    private let environmentPath: String

    public init(
        fileSystem: any ExecutableFileSystem = FoundationExecutableFileSystem(),
        environmentPath: String = ProcessInfo.processInfo.environment["PATH"] ?? ""
    ) {
        self.fileSystem = fileSystem
        self.environmentPath = environmentPath
    }

    public func resolve(_ executable: ToolExecutable) -> URL? {
        for candidate in candidates(executable) {
            let standardizedPath = candidate.standardizedFileURL.path
            guard fileSystem.isExecutableFile(atPath: standardizedPath) else {
                continue
            }
            return URL(fileURLWithPath: standardizedPath)
        }

        return nil
    }

    public func candidates(_ executable: ToolExecutable) -> [URL] {
        var seen: Set<String> = []
        let pathCandidates = environmentPath
            .split(separator: ":", omittingEmptySubsequences: true)
            .map(String.init)
            .filter { $0.hasPrefix("/") }
            .map { "\($0)/\(executable.executableName)" }

        return (executable.fixedCandidates + pathCandidates).compactMap { path in
            let url = URL(fileURLWithPath: path).standardizedFileURL
            return seen.insert(url.path).inserted ? url : nil
        }
    }
}
