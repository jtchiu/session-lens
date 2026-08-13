import Foundation

public protocol ClaudeCacheStoring: Sendable {
    func read() throws -> ClaudeNormalizedCache?
    func write(_ cache: ClaudeNormalizedCache) throws
}

public struct ClaudeBridgeConfiguration: Codable, Equatable, Sendable {
    public let previousCommand: String?
    public let installedStatusLineChecksum: String?

    public init(
        previousCommand: String?,
        installedStatusLineChecksum: String? = nil
    ) {
        self.previousCommand = previousCommand
        self.installedStatusLineChecksum = installedStatusLineChecksum
    }
}

public struct ClaudeBridgeStore: ClaudeCacheStoring, @unchecked Sendable {
    public static let live = ClaudeBridgeStore(
        bridgeDirectory: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/SessionLens/Bridge")
    )

    public let bridgeDirectory: URL
    public let cacheURL: URL
    public let configurationURL: URL

    public init(bridgeDirectory: URL) {
        self.bridgeDirectory = bridgeDirectory
        self.cacheURL = bridgeDirectory.appendingPathComponent("claude-usage.json")
        self.configurationURL = bridgeDirectory.appendingPathComponent(
            "claude-bridge-config.json"
        )
    }

    public func read() throws -> ClaudeNormalizedCache? {
        guard FileManager.default.fileExists(atPath: cacheURL.path) else {
            return nil
        }
        return try JSONDecoder().decode(
            ClaudeNormalizedCache.self,
            from: Data(contentsOf: cacheURL)
        )
    }

    public func write(_ cache: ClaudeNormalizedCache) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: bridgeDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: bridgeDirectory.path
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(cache).write(to: cacheURL, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: cacheURL.path
        )
    }
}

public enum ExistingStatusLineForwarderError: Error, Equatable {
    case launchFailed
    case timedOut
}

public struct ExistingStatusLineForwarder: Sendable {
    public static let live = ExistingStatusLineForwarder(
        configurationURL: ClaudeBridgeStore.live.configurationURL,
        process: FoundationProcessRunner(
            stderrLimit: 4_096,
            stdoutLimit: 1_048_576
        )
    )

    private let configurationURL: URL
    private let process: any ProcessExecuting

    public init(
        configurationURL: URL,
        process: any ProcessExecuting
    ) {
        self.configurationURL = configurationURL
        self.process = process
    }

    public func forward(originalInput: Data) async throws -> Data {
        guard FileManager.default.fileExists(atPath: configurationURL.path) else {
            return Data()
        }
        let configuration = try JSONDecoder().decode(
            ClaudeBridgeConfiguration.self,
            from: Data(contentsOf: configurationURL)
        )
        guard let command = configuration.previousCommand, !command.isEmpty else {
            return Data()
        }

        let result = await process.run(
            ProcessRequest(
                executable: URL(fileURLWithPath: "/bin/zsh"),
                arguments: ["-lc", command],
                stdin: originalInput,
                timeout: .seconds(5)
            )
        )
        switch result.termination {
        case .exited:
            return result.stdout
        case .launchFailed:
            throw ExistingStatusLineForwarderError.launchFailed
        case .timedOut:
            throw ExistingStatusLineForwarderError.timedOut
        }
    }
}
