import Foundation

public struct ResolvedModelRate: Hashable, Sendable {
    public let modelID: String
    public let rate: PricingRate
    public let coverage: PricingCoverage

    public init(modelID: String, rate: PricingRate, coverage: PricingCoverage) {
        self.modelID = modelID
        self.rate = rate
        self.coverage = coverage
    }
}

public enum ModelRateResolver {
    public static func resolve(
        provider: ProviderID,
        providerID: String?,
        modelID: String?,
        latestModelID: String?,
        catalog: PricingCatalog,
        catalogIsStale: Bool
    ) -> ResolvedModelRate? {
        let configuredProviderID = normalizedIdentifier(providerID)
        let configuredModelID = normalizedIdentifier(modelID)

        if let resolved = match(
            providerID: configuredProviderID,
            modelID: configuredModelID,
            catalog: catalog,
            coverage: .modelAttributed,
            catalogIsStale: catalogIsStale
        ) {
            return resolved
        }

        if provider == .opencode,
           let alias = providerModelAlias(configuredModelID),
           let resolved = match(
               providerID: alias.providerID,
               modelID: alias.modelID,
               catalog: catalog,
               coverage: .detectedProviderModel,
               catalogIsStale: catalogIsStale
           ) {
            return resolved
        }

        if provider == .codex,
           let resolved = match(
               providerID: "openai",
               modelID: configuredModelID,
               catalog: catalog,
               coverage: .detectedProviderModel,
               catalogIsStale: catalogIsStale
           ) {
            return resolved
        }

        let latest = providerModelAlias(normalizedIdentifier(latestModelID))
        let latestProviderID = latest?.providerID ?? configuredProviderID
        let latestModelID = latest?.modelID ?? normalizedIdentifier(latestModelID)
        if let resolved = match(
            providerID: latestProviderID,
            modelID: latestModelID,
            catalog: catalog,
            coverage: .latestKnownModel,
            catalogIsStale: catalogIsStale
        ) {
            return resolved
        }

        if provider == .codex {
            return match(
                providerID: "openai",
                modelID: latestModelID,
                catalog: catalog,
                coverage: .latestKnownModel,
                catalogIsStale: catalogIsStale
            )
        }
        return nil
    }

    private static func match(
        providerID: String?,
        modelID: String?,
        catalog: PricingCatalog,
        coverage: PricingCoverage,
        catalogIsStale: Bool
    ) -> ResolvedModelRate? {
        guard let providerID, let modelID,
              let model = catalog.model(providerID: providerID, modelID: modelID)
        else {
            return nil
        }
        return ResolvedModelRate(
            modelID: model.modelID,
            rate: model.rate,
            coverage: catalogIsStale ? .catalogStale : coverage
        )
    }

    private static func normalizedIdentifier(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private static func providerModelAlias(_ value: String?) -> (providerID: String, modelID: String)? {
        guard let value,
              let separator = value.firstIndex(of: "/")
        else {
            return nil
        }
        let providerID = String(value[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
        let modelID = String(value[value.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !providerID.isEmpty, !modelID.isEmpty else { return nil }
        return (providerID, modelID)
    }
}
