import Foundation

public struct PricingCatalogHTTPResponse: Sendable {
    public let statusCode: Int
    public let data: Data
    public let etag: String?
    public let lastModified: String?

    public init(statusCode: Int, data: Data, etag: String?, lastModified: String?) {
        self.statusCode = statusCode
        self.data = data
        self.etag = etag
        self.lastModified = lastModified
    }
}

public protocol PricingCatalogTransport: Sendable {
    func fetch(ifNoneMatch: String?) async throws -> PricingCatalogHTTPResponse
}

public struct URLSessionPricingCatalogTransport: PricingCatalogTransport {
    public static let endpoint = URL(string: "https://models.dev/api.json")!

    public init() {}

    public func fetch(ifNoneMatch: String?) async throws -> PricingCatalogHTTPResponse {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let ifNoneMatch {
            request.setValue(ifNoneMatch, forHTTPHeaderField: "If-None-Match")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw PricingCatalogClientError.invalidResponse
        }
        return PricingCatalogHTTPResponse(
            statusCode: response.statusCode,
            data: data,
            etag: response.value(forHTTPHeaderField: "ETag"),
            lastModified: response.value(forHTTPHeaderField: "Last-Modified")
        )
    }
}

public actor PricingCatalogClient {
    private let cacheURL: URL
    private let transport: any PricingCatalogTransport
    private let currentDate: @Sendable () -> Date
    private let ttl: TimeInterval

    public init(
        cacheURL: URL,
        transport: any PricingCatalogTransport = URLSessionPricingCatalogTransport(),
        now: @escaping @Sendable () -> Date = Date.init,
        ttl: TimeInterval = 86_400
    ) {
        self.cacheURL = cacheURL
        self.transport = transport
        self.currentDate = now
        self.ttl = max(0, ttl)
    }

    public func state(now: Date? = nil) async -> PricingCatalogState {
        let now = now ?? currentDate()
        guard let cache = readCache() else {
            return PricingCatalogState(source: .unavailable, catalog: nil, message: "Pricing rates are unavailable.")
        }
        return cachedState(cache, now: now)
    }

    public func refreshIfNeeded(now: Date? = nil) async -> PricingCatalogState {
        let now = now ?? currentDate()
        let cache = readCache()
        if let cache, isFresh(cache, now: now) {
            return cachedState(cache, now: now)
        }

        do {
            let response = try await transport.fetch(ifNoneMatch: cache?.etag)
            if response.statusCode == 304, var cache {
                cache.validatedAt = now
                if let etag = response.etag { cache.etag = etag }
                if let lastModified = response.lastModified { cache.lastModified = lastModified }
                try writeCache(cache)
                return PricingCatalogState(source: .cached, catalog: cache.catalog)
            }
            guard (200 ... 299).contains(response.statusCode) else {
                return failedRefresh(cache)
            }

            let catalog = try PricingCatalogDecoder.decode(response.data, fetchedAt: now)
            let record = PricingCacheRecord(
                catalog: catalog,
                sourceURL: URLSessionPricingCatalogTransport.endpoint.absoluteString,
                etag: response.etag,
                lastModified: response.lastModified,
                validatedAt: now
            )
            try writeCache(record)
            return PricingCatalogState(source: .live, catalog: catalog)
        } catch {
            return failedRefresh(cache)
        }
    }

    private func cachedState(_ cache: PricingCacheRecord, now: Date) -> PricingCatalogState {
        let message = isFresh(cache, now: now) ? nil : "Pricing rates may be out of date."
        return PricingCatalogState(source: .cached, catalog: cache.catalog, message: message)
    }

    private func failedRefresh(_ cache: PricingCacheRecord?) -> PricingCatalogState {
        guard let cache else {
            return PricingCatalogState(source: .unavailable, catalog: nil, message: "Pricing rates are unavailable.")
        }
        return PricingCatalogState(source: .cached, catalog: cache.catalog, message: "Pricing rates may be out of date.")
    }

    private func isFresh(_ cache: PricingCacheRecord, now: Date) -> Bool {
        now.timeIntervalSince(cache.validatedAt) < ttl
    }

    private func readCache() -> PricingCacheRecord? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? PricingCacheRecord.decode(data)
    }

    private func writeCache(_ cache: PricingCacheRecord) throws {
        let data = try cache.encode()
        let fileManager = FileManager.default
        let directory = cacheURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporaryURL = directory.appendingPathComponent(".\(cacheURL.lastPathComponent).\(UUID().uuidString).tmp")
        defer { try? fileManager.removeItem(at: temporaryURL) }
        try data.write(to: temporaryURL, options: .withoutOverwriting)
        if fileManager.fileExists(atPath: cacheURL.path) {
            _ = try fileManager.replaceItemAt(cacheURL, withItemAt: temporaryURL)
        } else {
            try fileManager.moveItem(at: temporaryURL, to: cacheURL)
        }
    }
}

enum PricingCatalogClientError: Error {
    case invalidResponse
}

struct PricingCacheRecord: Codable, Sendable {
    let catalog: PricingCatalog
    let sourceURL: String
    var etag: String?
    var lastModified: String?
    var validatedAt: Date

    init(
        catalog: PricingCatalog,
        sourceURL: String = URLSessionPricingCatalogTransport.endpoint.absoluteString,
        etag: String?,
        lastModified: String?,
        validatedAt: Date? = nil
    ) {
        self.catalog = catalog
        self.sourceURL = sourceURL
        self.etag = etag
        self.lastModified = lastModified
        self.validatedAt = validatedAt ?? catalog.fetchedAt
    }

    func encode() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> Self {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Self.self, from: data)
    }
}

enum PricingCatalogDecoder {
    static func decode(_ data: Data, fetchedAt: Date) throws -> PricingCatalog {
        let document = try JSONDecoder().decode(ModelsDevDocument.self, from: data)
        let models = document.providers
            .flatMap { entry -> [PricingCatalogModel] in
                let (providerID, provider) = entry
                guard let providerModels = provider.models else { return [] }
                return providerModels.compactMap { fallbackModelID, model in
                    guard let rate = rate(from: model.cost) else { return nil }
                    return PricingCatalogModel(
                        providerID: provider.id ?? providerID,
                        modelID: model.id ?? fallbackModelID,
                        rate: rate
                    )
                }
            }
            .sorted { ($0.providerID, $0.modelID) < ($1.providerID, $1.modelID) }
        return PricingCatalog(models: models, updatedAt: document.updatedAt, fetchedAt: fetchedAt)
    }

    private static func rate(from cost: ModelsDevCost?) -> PricingRate? {
        guard let cost else { return nil }
        let input = usable(cost.input)
        let output = usable(cost.output)
        let reasoning = usable(cost.reasoning)
        let cacheRead = usable(cost.cacheRead)
        let cacheWrite = usable(cost.cacheWrite)
        guard input != nil || output != nil || reasoning != nil || cacheRead != nil || cacheWrite != nil else {
            return nil
        }
        return PricingRate(
            inputPerMillion: input,
            outputPerMillion: output,
            reasoningPerMillion: reasoning,
            cacheReadPerMillion: cacheRead,
            cacheWritePerMillion: cacheWrite
        )
    }

    private static func usable(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }
}

private struct ModelsDevDocument: Decodable {
    let providers: [String: ModelsDevProvider]
    let updatedAt: Date?

    init(from decoder: Decoder) throws {
        let root = try decoder.container(keyedBy: DynamicCodingKey.self)
        providers = Dictionary(
            uniqueKeysWithValues: root.allKeys.compactMap { key in
                guard let provider = try? root.decode(ModelsDevProvider.self, forKey: key),
                      provider.models != nil
                else { return nil }
                return (key.stringValue, provider)
            }
        )
        updatedAt = ["updated_at", "updatedAt", "updated"].lazy
            .compactMap { keyName in
                let key = DynamicCodingKey(stringValue: keyName)
                guard let string = try? root.decode(String.self, forKey: key) else { return nil }
                return ISO8601DateFormatter().date(from: string)
            }
            .first
    }
}

private struct ModelsDevProvider: Decodable {
    let id: String?
    let models: [String: ModelsDevModel]?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        id = try? container.decode(String.self, forKey: DynamicCodingKey(stringValue: "id"))
        guard container.contains(DynamicCodingKey(stringValue: "models")),
              let modelsContainer = try? container.nestedContainer(
                keyedBy: DynamicCodingKey.self,
                forKey: DynamicCodingKey(stringValue: "models")
              )
        else {
            models = nil
            return
        }
        models = Dictionary(
            uniqueKeysWithValues: modelsContainer.allKeys.compactMap { key in
                guard let model = try? modelsContainer.decode(ModelsDevModel.self, forKey: key) else {
                    return nil
                }
                return (key.stringValue, model)
            }
        )
    }
}

private struct ModelsDevModel: Decodable {
    let id: String?
    let cost: ModelsDevCost?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        id = try? container.decode(String.self, forKey: DynamicCodingKey(stringValue: "id"))
        cost = try? container.decode(ModelsDevCost.self, forKey: DynamicCodingKey(stringValue: "cost"))
    }
}

private struct ModelsDevCost: Decodable {
    let input: Double?
    let output: Double?
    let reasoning: Double?
    let cacheRead: Double?
    let cacheWrite: Double?

    enum CodingKeys: String, CodingKey {
        case input
        case output
        case reasoning
        case cacheRead = "cache_read"
        case cacheWrite = "cache_write"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        input = try? container.decode(Double.self, forKey: .input)
        output = try? container.decode(Double.self, forKey: .output)
        reasoning = try? container.decode(Double.self, forKey: .reasoning)
        cacheRead = try? container.decode(Double.self, forKey: .cacheRead)
        cacheWrite = try? container.decode(Double.self, forKey: .cacheWrite)
    }
}

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        return nil
    }
}
