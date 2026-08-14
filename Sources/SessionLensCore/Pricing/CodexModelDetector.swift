import Foundation

public protocol PricingFileSystem: Sendable {
    func readIfExists(_ url: URL) -> String?
}

public struct FoundationPricingFileSystem: PricingFileSystem {
    public init() {}

    public func readIfExists(_ url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }
}

public enum CodexModelDetector {
    public static func live(
        homeDirectory: URL,
        fileSystem: any PricingFileSystem = FoundationPricingFileSystem()
    ) -> String? {
        let configurationURL = homeDirectory.appending(path: ".codex/config.toml")
        guard let configuration = fileSystem.readIfExists(configurationURL) else { return nil }
        return detect(configuration: configuration)
    }

    public static func detect(configuration: String) -> String? {
        for line in configuration.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            if trimmed.hasPrefix("[") { return nil }
            guard let equals = trimmed.firstIndex(of: "="),
                  trimmed[..<equals].trimmingCharacters(in: .whitespacesAndNewlines) == "model"
            else {
                continue
            }
            return quotedModel(String(trimmed[trimmed.index(after: equals)...]))
        }
        return nil
    }

    private static func quotedModel(_ assignment: String) -> String? {
        let value = assignment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.first == "\"" else { return nil }
        let afterOpeningQuote = value.index(after: value.startIndex)
        guard let closingQuote = value[afterOpeningQuote...].firstIndex(of: "\"") else { return nil }
        let trailing = value[value.index(after: closingQuote)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard trailing.isEmpty || trailing.hasPrefix("#") else { return nil }
        let modelID = value[afterOpeningQuote..<closingQuote].trimmingCharacters(in: .whitespacesAndNewlines)
        return modelID.isEmpty ? nil : modelID
    }
}
