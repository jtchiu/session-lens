import Foundation
import Testing

@testable import SessionLensCore

@Suite
struct ModelRateResolverTests {
    @Test
    func resolvesExactNormalizedProviderAndModel() {
        let resolved = ModelRateResolver.resolve(
            provider: .claude,
            providerID: "  anthropic / ",
            modelID: " claude-CaseSensitive ",
            latestModelID: nil,
            catalog: catalog,
            catalogIsStale: false
        )

        #expect(resolved == .init(
            modelID: "claude-CaseSensitive",
            rate: .init(inputPerMillion: 3),
            coverage: .modelAttributed
        ))
    }

    @Test
    func resolvesOpenCodeModelAliasWhenProviderIsNotSeparatelyPresent() {
        let resolved = ModelRateResolver.resolve(
            provider: .opencode,
            providerID: nil,
            modelID: " openai / gpt-test ",
            latestModelID: nil,
            catalog: catalog,
            catalogIsStale: false
        )

        #expect(resolved == .init(
            modelID: "gpt-test",
            rate: .init(inputPerMillion: 1),
            coverage: .detectedProviderModel
        ))
    }

    @Test
    func resolvesLatestKnownModelAfterCurrentModelIsUnknown() {
        let resolved = ModelRateResolver.resolve(
            provider: .claude,
            providerID: "anthropic",
            modelID: "unknown-model",
            latestModelID: " anthropic / claude-CaseSensitive ",
            catalog: catalog,
            catalogIsStale: false
        )

        #expect(resolved == .init(
            modelID: "claude-CaseSensitive",
            rate: .init(inputPerMillion: 3),
            coverage: .latestKnownModel
        ))
    }

    @Test
    func labelsAnyResolvedRateAsStaleWhenCatalogIsStale() {
        let resolved = ModelRateResolver.resolve(
            provider: .claude,
            providerID: "anthropic",
            modelID: "claude-CaseSensitive",
            latestModelID: nil,
            catalog: catalog,
            catalogIsStale: true
        )

        #expect(resolved?.coverage == .catalogStale)
    }

    @Test
    func resolvesCodexConfiguredModelThroughOpenAIAlias() {
        let resolved = ModelRateResolver.resolve(
            provider: .codex,
            providerID: "codex",
            modelID: "gpt-test",
            latestModelID: nil,
            catalog: catalog,
            catalogIsStale: false
        )

        #expect(resolved == .init(
            modelID: "gpt-test",
            rate: .init(inputPerMillion: 1),
            coverage: .detectedProviderModel
        ))
    }

    @Test
    func doesNotFuzzyMatchUnknownModels() {
        let resolved = ModelRateResolver.resolve(
            provider: .claude,
            providerID: "anthropic",
            modelID: "claude",
            latestModelID: nil,
            catalog: catalog,
            catalogIsStale: false
        )

        #expect(resolved == nil)
    }

    @Test
    func detectsQuotedTopLevelCodexModelWithWhitespaceAndComments() {
        let detected = CodexModelDetector.detect(configuration: #"""
        # local configuration
          model = "gpt-5.1-codex" # active model
        project_doc_path = "/Users/example/project"
        """#)

        #expect(detected == "gpt-5.1-codex")
    }

    @Test(arguments: [
        "model = gpt-5.1-codex",
        "model = 'gpt-5.1-codex'",
        "model = \"unterminated",
        "[profiles.work]\nmodel = \"gpt-5.1-codex\"",
        "project_path = \"/Users/example/project\"",
    ])
    func rejectsMissingMalformedOrNonTopLevelCodexModel(_ configuration: String) {
        #expect(CodexModelDetector.detect(configuration: configuration) == nil)
    }

    @Test
    func liveReadsOnlyTopLevelCodexModelMetadataThroughInjectedFileSystem() {
        let home = URL(fileURLWithPath: "/tmp/sessionlens-home", isDirectory: true)
        let config = home.appending(path: ".codex/config.toml")
        let fileSystem = FakePricingFileSystem(models: [config: "gpt-test"])

        #expect(CodexModelDetector.live(homeDirectory: home, fileSystem: fileSystem) == "gpt-test")
        #expect(fileSystem.readURLs == [config])
    }

    @Test
    func boundedCodexConfigReaderStopsBeforeNestedSections() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sessionlens-codex-" + UUID().uuidString, isDirectory: true)
        let config = root.appendingPathComponent("config.toml")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try #"""
        model = "gpt-test"

[profiles.work]
model = "should-not-be-read"
project_path = "/Users/example/project"
"""#.write(to: config, atomically: true, encoding: .utf8)

        #expect(
            FoundationPricingFileSystem().readTopLevelModelIfExists(config) == "gpt-test"
        )
    }

    private let catalog = PricingCatalog(
        models: [
            .init(providerID: "openai", modelID: "gpt-test", rate: .init(inputPerMillion: 1)),
            .init(providerID: "anthropic", modelID: "claude-CaseSensitive", rate: .init(inputPerMillion: 3)),
        ],
        updatedAt: nil,
        fetchedAt: Date(timeIntervalSince1970: 0)
    )
}
