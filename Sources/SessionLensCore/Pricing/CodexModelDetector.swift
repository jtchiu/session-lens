import Foundation

public protocol PricingFileSystem: Sendable {
    /// Returns only the allowlisted top-level Codex model setting.
    ///
    /// Implementations must not load or retain the full configuration file.
    func readTopLevelModelIfExists(_ url: URL) -> String?
}

public struct FoundationPricingFileSystem: PricingFileSystem {
    public init() {}

    public func readTopLevelModelIfExists(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let chunkSize = 4 * 1024
        let maximumScanBytes = 64 * 1024
        var scannedBytes = 0
        var line = Data()
        var skippingOversizedLine = false

        func consume(_ line: Data) -> String? {
            guard let text = String(data: line, encoding: .utf8) else { return nil }
            return CodexModelDetector.modelFromTopLevelLine(text)
        }

        while scannedBytes < maximumScanBytes {
            let requestedBytes = min(chunkSize, maximumScanBytes - scannedBytes)
            let chunk: Data?
            do {
                chunk = try handle.read(upToCount: requestedBytes)
            } catch {
                return nil
            }
            guard let chunk, !chunk.isEmpty else { break }
            scannedBytes += chunk.count

            for byte in chunk {
                if byte == 0x0A {
                    if !skippingOversizedLine, let modelID = consume(line) {
                        return modelID
                    }
                    if !skippingOversizedLine,
                       CodexModelDetector.isTopLevelSection(line)
                    {
                        return nil
                    }
                    line.removeAll(keepingCapacity: true)
                    skippingOversizedLine = false
                } else if !skippingOversizedLine {
                    if line.count < chunkSize {
                        line.append(byte)
                    } else {
                        line.removeAll(keepingCapacity: true)
                        skippingOversizedLine = true
                    }
                }
            }
        }

        guard !skippingOversizedLine, !line.isEmpty else { return nil }
        if let modelID = consume(line) { return modelID }
        return nil
    }
}

public enum CodexModelDetector {
    public static func live(
        homeDirectory: URL,
        fileSystem: any PricingFileSystem = FoundationPricingFileSystem()
    ) -> String? {
        let configurationURL = homeDirectory.appending(path: ".codex/config.toml")
        return fileSystem.readTopLevelModelIfExists(configurationURL)
    }

    public static func detect(configuration: String) -> String? {
        for line in configuration.split(whereSeparator: \.isNewline) {
            let text = String(line)
            if let modelID = modelFromTopLevelLine(text) { return modelID }
            if isTopLevelSection(Data(text.utf8)) { return nil }
        }
        return nil
    }

    fileprivate static func modelFromTopLevelLine(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix("[") { return nil }
        guard let equals = trimmed.firstIndex(of: "="),
              trimmed[..<equals].trimmingCharacters(in: .whitespacesAndNewlines) == "model"
        else {
            return nil
        }
        return quotedModel(String(trimmed[trimmed.index(after: equals)...]))
    }

    fileprivate static func isTopLevelSection(_ line: Data) -> Bool {
        guard let text = String(data: line, encoding: .utf8) else { return false }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[")
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
