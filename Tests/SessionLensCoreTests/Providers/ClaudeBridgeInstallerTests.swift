import Foundation
import Testing
@testable import SessionLensCore

@Suite
struct ClaudeBridgeInstallerTests {
    @Test
    func installPreservesExistingStatusLineAndUninstallRestoresIt() throws {
        let fixture = try TemporaryClaudeSettings(
            existingStatusLine: [
                "type": "command",
                "command": "~/.claude/statusline.sh",
                "padding": 2,
                "refreshInterval": 5,
            ]
        )
        defer { fixture.remove() }
        let installer = ClaudeBridgeInstaller(
            paths: fixture.paths,
            helperSource: fixture.helperSource
        )

        try installer.install()

        #expect(try installer.status() == .installed)
        let configuration = try fixture.configuration()
        #expect(configuration.previousCommand == "~/.claude/statusline.sh")
        let installed = try fixture.statusLine()
        #expect(installed["type"] as? String == "command")
        #expect(installed["padding"] as? Int == 2)
        #expect(installed["refreshInterval"] as? Int == 5)
        #expect(
            installed["command"] as? String
                == ClaudeBridgeInstaller.shellQuote(fixture.paths.installedHelperURL.path)
        )
        #expect(
            try Data(contentsOf: fixture.paths.installedHelperURL)
                == Data("bridge-binary".utf8)
        )

        try installer.uninstall()

        #expect(try installer.status() == .notInstalled)
        let restored = try fixture.statusLine()
        #expect(restored["type"] as? String == "command")
        #expect(restored["command"] as? String == "~/.claude/statusline.sh")
        #expect(restored["padding"] as? Int == 2)
        #expect(restored["refreshInterval"] as? Int == 5)
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.configurationURL.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.backupURL.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.installedHelperURL.path))
    }

    @Test
    func uninstallRemovesWrapperWhenNoStatusLineExisted() throws {
        let fixture = try TemporaryClaudeSettings(existingStatusLine: nil)
        defer { fixture.remove() }
        let installer = ClaudeBridgeInstaller(
            paths: fixture.paths,
            helperSource: fixture.helperSource
        )

        try installer.install()
        try installer.uninstall()

        #expect(try fixture.settings()["statusLine"] == nil)
        #expect(try fixture.settings()["theme"] as? String == "dark")
    }

    @Test
    func uninstallFailsClosedAfterUserEditsWrapper() throws {
        let fixture = try TemporaryClaudeSettings(existingStatusLine: nil)
        defer { fixture.remove() }
        let installer = ClaudeBridgeInstaller(
            paths: fixture.paths,
            helperSource: fixture.helperSource
        )
        try installer.install()
        try fixture.replaceStatusLine(
            with: ["type": "command", "command": "~/my-new-statusline.sh"]
        )

        #expect(throws: ClaudeBridgeInstallError.settingsChangedAfterInstall) {
            try installer.uninstall()
        }

        #expect(try installer.status() == .settingsChanged)
        #expect(
            try fixture.statusLine()["command"] as? String
                == "~/my-new-statusline.sh"
        )
        #expect(FileManager.default.fileExists(atPath: fixture.paths.configurationURL.path))
        #expect(FileManager.default.fileExists(atPath: fixture.paths.backupURL.path))
    }

    @Test
    func uninstallPreservesUnrelatedSettingsChangedAfterInstall() throws {
        let fixture = try TemporaryClaudeSettings(
            existingStatusLine: [
                "type": "command", "command": "printf old",
            ]
        )
        defer { fixture.remove() }
        let installer = ClaudeBridgeInstaller(
            paths: fixture.paths,
            helperSource: fixture.helperSource
        )
        try installer.install()
        try fixture.changeSetting(key: "theme", value: "light")

        try installer.uninstall()

        #expect(try fixture.settings()["theme"] as? String == "light")
        #expect(try fixture.statusLine()["command"] as? String == "printf old")
    }

    @Test
    func malformedSettingsFailClosedBeforeCreatingInstallerArtifacts() throws {
        let fixture = try TemporaryClaudeSettings(existingStatusLine: nil)
        defer { fixture.remove() }
        try Data("not-json".utf8).write(to: fixture.paths.settingsURL)
        let installer = ClaudeBridgeInstaller(
            paths: fixture.paths,
            helperSource: fixture.helperSource
        )

        #expect(throws: ClaudeBridgeInstallError.invalidSettings) {
            try installer.install()
        }

        #expect(!FileManager.default.fileExists(atPath: fixture.paths.bridgeDirectory.path))
        #expect(try Data(contentsOf: fixture.paths.settingsURL) == Data("not-json".utf8))
    }

    @Test
    func installerNeverTouchesOtherClaudeStateOrSessionLensCache() throws {
        let fixture = try TemporaryClaudeSettings(existingStatusLine: nil)
        defer { fixture.remove() }
        let privateState = fixture.root.appendingPathComponent(".claude.json")
        let projectSettings = fixture.root.appendingPathComponent(
            "project/.claude/settings.json"
        )
        let cache = fixture.paths.bridgeDirectory.appendingPathComponent(
            "claude-usage.json"
        )
        try FileManager.default.createDirectory(
            at: projectSettings.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("private-state".utf8).write(to: privateState)
        try Data("project-state".utf8).write(to: projectSettings)
        try FileManager.default.createDirectory(
            at: fixture.paths.bridgeDirectory,
            withIntermediateDirectories: true
        )
        try Data("normalized-cache".utf8).write(to: cache)
        let installer = ClaudeBridgeInstaller(
            paths: fixture.paths,
            helperSource: fixture.helperSource
        )

        try installer.install()
        try installer.uninstall()

        #expect(try Data(contentsOf: privateState) == Data("private-state".utf8))
        #expect(try Data(contentsOf: projectSettings) == Data("project-state".utf8))
        #expect(!FileManager.default.fileExists(atPath: cache.path))
    }

    @Test
    func missingOrModifiedHelperReportsConflictAndCannotBeUninstalled() throws {
        let fixture = try TemporaryClaudeSettings(existingStatusLine: nil)
        defer { fixture.remove() }
        let installer = ClaudeBridgeInstaller(
            paths: fixture.paths,
            helperSource: fixture.helperSource
        )

        try installer.install()
        try Data("modified-helper".utf8).write(
            to: fixture.paths.installedHelperURL,
            options: .atomic
        )

        #expect(try installer.status() == .settingsChanged)
        #expect(throws: ClaudeBridgeInstallError.settingsChangedAfterInstall) {
            try installer.uninstall()
        }
    }
}

private final class TemporaryClaudeSettings {
    let root: URL
    let paths: ClaudeBridgePaths
    let helperSource: URL

    init(existingStatusLine: [String: Any]?) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        let claudeDirectory = root.appendingPathComponent(".claude", isDirectory: true)
        let bridgeDirectory = root.appendingPathComponent(
            "Application Support/SessionLens/Bridge with 'quote",
            isDirectory: true
        )
        paths = ClaudeBridgePaths(
            settingsURL: claudeDirectory.appendingPathComponent("settings.json"),
            bridgeDirectory: bridgeDirectory
        )
        helperSource = root.appendingPathComponent("built-helper")
        try FileManager.default.createDirectory(
            at: claudeDirectory,
            withIntermediateDirectories: true
        )
        var settings: [String: Any] = [
            "theme": "dark",
            "permissions": ["allow": ["Read"]],
        ]
        if let existingStatusLine {
            settings["statusLine"] = existingStatusLine
        }
        try writeJSONObject(settings, to: paths.settingsURL)
        try Data("bridge-binary".utf8).write(to: helperSource)
    }

    func settings() throws -> [String: Any] {
        let value = try JSONSerialization.jsonObject(
            with: Data(contentsOf: paths.settingsURL)
        )
        return try #require(value as? [String: Any])
    }

    func statusLine() throws -> [String: Any] {
        try #require(settings()["statusLine"] as? [String: Any])
    }

    func configuration() throws -> ClaudeBridgeConfiguration {
        try JSONDecoder().decode(
            ClaudeBridgeConfiguration.self,
            from: Data(contentsOf: paths.configurationURL)
        )
    }

    func replaceStatusLine(with value: [String: Any]) throws {
        var current = try settings()
        current["statusLine"] = value
        try writeJSONObject(current, to: paths.settingsURL)
    }

    func changeSetting(key: String, value: Any) throws {
        var current = try settings()
        current[key] = value
        try writeJSONObject(current, to: paths.settingsURL)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    private func writeJSONObject(_ object: Any, to url: URL) throws {
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: url, options: .atomic)
    }
}
