import CryptoKit
import Foundation

public struct ClaudeBridgePaths: Sendable {
    public static let live: ClaudeBridgePaths = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return ClaudeBridgePaths(
            settingsURL: home.appendingPathComponent(".claude/settings.json"),
            bridgeDirectory: home.appendingPathComponent(
                "Library/Application Support/SessionLens/Bridge"
            )
        )
    }()

    public let settingsURL: URL
    public let bridgeDirectory: URL

    public init(settingsURL: URL, bridgeDirectory: URL) {
        self.settingsURL = settingsURL
        self.bridgeDirectory = bridgeDirectory
    }

    public var installedHelperURL: URL {
        bridgeDirectory.appendingPathComponent("SessionLensClaudeBridge")
    }

    public var configurationURL: URL {
        bridgeDirectory.appendingPathComponent("claude-bridge-config.json")
    }

    public var backupURL: URL {
        bridgeDirectory.appendingPathComponent("claude-statusline-backup.json")
    }
}

public enum ClaudeBridgeInstallStatus: Equatable, Sendable {
    case notInstalled
    case installed
    case settingsChanged
}

public enum ClaudeBridgeInstallError: Error, Equatable {
    case invalidSettings
    case invalidStatusLine
    case alreadyInstalled
    case notInstalled
    case missingHelper
    case invalidMetadata
    case settingsChangedAfterInstall
}

public struct ClaudeBridgeInstaller {
    private struct BackupEnvelope: Codable, Sendable {
        let hadStatusLine: Bool
        let statusLineJSON: Data?
    }

    private let paths: ClaudeBridgePaths
    private let helperSource: URL
    private let fileManager: FileManager

    public init(
        paths: ClaudeBridgePaths = .live,
        helperSource: URL,
        fileManager: FileManager = .default
    ) {
        self.paths = paths
        self.helperSource = helperSource
        self.fileManager = fileManager
    }

    public func status() throws -> ClaudeBridgeInstallStatus {
        guard fileManager.fileExists(atPath: paths.configurationURL.path) else {
            return .notInstalled
        }
        let configuration = try readConfiguration()
        guard let expected = configuration.installedStatusLineChecksum else {
            throw ClaudeBridgeInstallError.invalidMetadata
        }
        guard fileManager.fileExists(atPath: paths.installedHelperURL.path) else {
            return .settingsChanged
        }
        if let expectedHelper = configuration.helperChecksum,
            try Self.checksum(forFileAt: paths.installedHelperURL) != expectedHelper
        {
            return .settingsChanged
        }
        let settings = try readSettings()
        guard let statusLine = settings["statusLine"] else {
            return .settingsChanged
        }
        return try Self.checksum(forJSONObject: statusLine) == expected
            ? .installed
            : .settingsChanged
    }

    public func install() throws {
        guard fileManager.fileExists(atPath: helperSource.path) else {
            throw ClaudeBridgeInstallError.missingHelper
        }
        guard !fileManager.fileExists(atPath: paths.configurationURL.path) else {
            throw ClaudeBridgeInstallError.alreadyInstalled
        }

        var settings = try readSettings()
        let existingStatusLine = settings["statusLine"]
        if let existingStatusLine,
            !(existingStatusLine is [String: Any])
        {
            throw ClaudeBridgeInstallError.invalidStatusLine
        }
        let previousCommand = (existingStatusLine as? [String: Any])?["command"]
            as? String
        let installedStatusLine = Self.installedStatusLine(
            preserving: existingStatusLine as? [String: Any],
            helperURL: paths.installedHelperURL
        )
        let checksum = try Self.checksum(forJSONObject: installedStatusLine)
        let backup = BackupEnvelope(
            hadStatusLine: existingStatusLine != nil,
            statusLineJSON: try existingStatusLine.map(Self.canonicalJSONData)
        )
        let configuration = ClaudeBridgeConfiguration(
            previousCommand: previousCommand,
            installedStatusLineChecksum: checksum,
            helperChecksum: try Self.checksum(forFileAt: helperSource)
        )

        try createBridgeDirectory()
        do {
            try replaceHelper()
            try writeProtected(
                try JSONEncoder.sorted.encode(backup),
                to: paths.backupURL,
                mode: 0o600
            )
            try writeProtected(
                try JSONEncoder.sorted.encode(configuration),
                to: paths.configurationURL,
                mode: 0o600
            )
            settings["statusLine"] = installedStatusLine
            try writeSettings(settings)
        } catch {
            try? fileManager.removeItem(at: paths.configurationURL)
            try? fileManager.removeItem(at: paths.backupURL)
            try? fileManager.removeItem(at: paths.installedHelperURL)
            throw error
        }
    }

    public func uninstall() throws {
        guard fileManager.fileExists(atPath: paths.configurationURL.path),
            fileManager.fileExists(atPath: paths.backupURL.path)
        else {
            throw ClaudeBridgeInstallError.notInstalled
        }
        let configuration = try readConfiguration()
        guard let expected = configuration.installedStatusLineChecksum else {
            throw ClaudeBridgeInstallError.invalidMetadata
        }
        guard fileManager.fileExists(atPath: paths.installedHelperURL.path) else {
            throw ClaudeBridgeInstallError.settingsChangedAfterInstall
        }
        if let expectedHelper = configuration.helperChecksum,
            try Self.checksum(forFileAt: paths.installedHelperURL) != expectedHelper
        {
            throw ClaudeBridgeInstallError.settingsChangedAfterInstall
        }
        var settings = try readSettings()
        guard let currentStatusLine = settings["statusLine"],
            try Self.checksum(forJSONObject: currentStatusLine) == expected
        else {
            throw ClaudeBridgeInstallError.settingsChangedAfterInstall
        }
        let backup = try JSONDecoder().decode(
            BackupEnvelope.self,
            from: Data(contentsOf: paths.backupURL)
        )

        if backup.hadStatusLine {
            guard let data = backup.statusLineJSON else {
                throw ClaudeBridgeInstallError.invalidMetadata
            }
            settings["statusLine"] = try JSONSerialization.jsonObject(with: data)
        } else {
            settings.removeValue(forKey: "statusLine")
        }
        try writeSettings(settings)
        try fileManager.removeItem(at: paths.configurationURL)
        try fileManager.removeItem(at: paths.backupURL)
        if fileManager.fileExists(atPath: paths.installedHelperURL.path) {
            try fileManager.removeItem(at: paths.installedHelperURL)
        }
        let cacheURL = paths.bridgeDirectory.appendingPathComponent(
            "claude-usage.json"
        )
        if fileManager.fileExists(atPath: cacheURL.path) {
            try fileManager.removeItem(at: cacheURL)
        }
    }

    public static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func installedStatusLine(
        preserving previous: [String: Any]?,
        helperURL: URL
    ) -> [String: Any] {
        var value = previous ?? [:]
        value["type"] = "command"
        value["command"] = shellQuote(helperURL.path)
        return value
    }

    private func readSettings() throws -> [String: Any] {
        if !fileManager.fileExists(atPath: paths.settingsURL.path) {
            return [:]
        }
        do {
            let object = try JSONSerialization.jsonObject(
                with: Data(contentsOf: paths.settingsURL)
            )
            guard let settings = object as? [String: Any] else {
                throw ClaudeBridgeInstallError.invalidSettings
            }
            return settings
        } catch let error as ClaudeBridgeInstallError {
            throw error
        } catch {
            throw ClaudeBridgeInstallError.invalidSettings
        }
    }

    private func readConfiguration() throws -> ClaudeBridgeConfiguration {
        do {
            return try JSONDecoder().decode(
                ClaudeBridgeConfiguration.self,
                from: Data(contentsOf: paths.configurationURL)
            )
        } catch {
            throw ClaudeBridgeInstallError.invalidMetadata
        }
    }

    private func writeSettings(_ settings: [String: Any]) throws {
        let parent = paths.settingsURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: parent,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try Self.canonicalJSONData(settings).write(
            to: paths.settingsURL,
            options: .atomic
        )
    }

    private func createBridgeDirectory() throws {
        try fileManager.createDirectory(
            at: paths.bridgeDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: paths.bridgeDirectory.path
        )
    }

    private func replaceHelper() throws {
        if fileManager.fileExists(atPath: paths.installedHelperURL.path) {
            try fileManager.removeItem(at: paths.installedHelperURL)
        }
        try fileManager.copyItem(
            at: helperSource,
            to: paths.installedHelperURL
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: paths.installedHelperURL.path
        )
    }

    private func writeProtected(_ data: Data, to url: URL, mode: Int) throws {
        try data.write(to: url, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: mode],
            ofItemAtPath: url.path
        )
    }

    private static func checksum(forJSONObject object: Any) throws -> String {
        SHA256.hash(data: try canonicalJSONData(object))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func checksum(forFileAt url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func canonicalJSONData(_ object: Any) throws -> Data {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw ClaudeBridgeInstallError.invalidSettings
        }
        return try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        )
    }
}

private extension JSONEncoder {
    static var sorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
