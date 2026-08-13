import Foundation

public struct OpenCodeProvider: UsageProvider {
    public static let allowedSQLIdentifiers: Set<String> = [
        "asc",
        "as",
        "by",
        "cost",
        "date",
        "day",
        "from",
        "group",
        "json_extract",
        "model",
        "model_id",
        "order",
        "provider_id",
        "select",
        "session",
        "sum",
        "time_updated",
        "tokens_cache_read",
        "tokens_cache_write",
        "tokens_input",
        "tokens_output",
        "tokens_reasoning",
    ]

    public static let fixedAggregateSQL = """
        SELECT
          date(time_updated / 1000, 'unixepoch', 'localtime') AS day,
          json_extract(model, '$.providerID') AS provider_id,
          json_extract(model, '$.id') AS model_id,
          SUM(cost) AS cost,
          SUM(tokens_input) AS tokens_input,
          SUM(tokens_output) AS tokens_output,
          SUM(tokens_reasoning) AS tokens_reasoning,
          SUM(tokens_cache_read) AS tokens_cache_read,
          SUM(tokens_cache_write) AS tokens_cache_write
        FROM session
        GROUP BY day, provider_id, model_id
        ORDER BY day ASC, provider_id ASC, model_id ASC;
        """

    public let id = ProviderID.opencode

    private let databaseURL: URL
    private let process: any ProcessExecuting
    private let sqliteURL: URL

    public init(
        databaseURL: URL,
        process: any ProcessExecuting,
        sqliteURL: URL
    ) {
        self.databaseURL = databaseURL
        self.process = process
        self.sqliteURL = sqliteURL
    }

    public func refresh(at now: Date) async -> ProviderSnapshot {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            return .unavailable(
                provider: id,
                health: .setupRequired,
                observedAt: now
            )
        }

        let result = await process.run(
            ProcessRequest(
                executable: sqliteURL,
                arguments: [
                    "-readonly",
                    "-json",
                    databaseURL.path,
                    Self.fixedAggregateSQL,
                ],
                timeout: .seconds(3)
            )
        )

        switch result.termination {
        case .launchFailed:
            return .unavailable(provider: id, health: .toolMissing, observedAt: now)
        case .timedOut:
            return .unavailable(provider: id, health: .timedOut, observedAt: now)
        case .exited(let code) where code != 0:
            return .unavailable(
                provider: id,
                health: Self.failureHealth(stderr: result.stderr),
                observedAt: now
            )
        case .exited:
            break
        }

        do {
            let bytes = result.stdout.isEmpty ? Data("[]".utf8) : result.stdout
            let rows = try JSONDecoder().decode([OpenCodeAggregateRow].self, from: bytes)
            return try Self.snapshot(rows: rows, observedAt: now)
        } catch {
            return .unavailable(
                provider: id,
                health: .malformedData,
                observedAt: now
            )
        }
    }

    private static func snapshot(
        rows: [OpenCodeAggregateRow],
        observedAt: Date
    ) throws -> ProviderSnapshot {
        var total = OpenCodeAccumulator()
        var days: [Date: OpenCodeAccumulator] = [:]
        var models: [OpenCodeModelKey: OpenCodeAccumulator] = [:]

        for row in rows {
            guard let day = localDay(from: row.day) else {
                throw OpenCodeNormalizationError.invalidDay(row.day)
            }
            total.add(row)
            days[day, default: OpenCodeAccumulator()].add(row)

            if let modelID = row.modelID, !modelID.isEmpty {
                let key = OpenCodeModelKey(
                    providerID: row.providerID,
                    modelID: modelID
                )
                models[key, default: OpenCodeAccumulator()].add(row)
            }
        }

        let dailyBuckets =
            days
            .map { day, aggregate in
                UsageBucket(
                    day: day,
                    tokens: aggregate.tokens.total,
                    costUSD: aggregate.costUSD
                )
            }
            .sorted { $0.day < $1.day }
        let modelBreakdowns =
            models
            .map { key, aggregate in
                ModelUsage(
                    providerID: key.providerID,
                    modelID: key.modelID,
                    tokens: aggregate.tokens,
                    costUSD: aggregate.costUSD
                )
            }
            .sorted { $0.id < $1.id }

        return ProviderSnapshot(
            provider: .opencode,
            observedAt: observedAt,
            health: .ready,
            tokens: total.tokens,
            costDisplay: .exactUSD(total.costUSD),
            dailyBuckets: dailyBuckets,
            quotaWindows: [],
            modelBreakdowns: modelBreakdowns
        )
    }

    private static func localDay(from value: String) -> Date? {
        let components = value.split(separator: "-")
        guard components.count == 3,
            let year = Int(components[0]),
            let month = Int(components[1]),
            let day = Int(components[2])
        else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(
            from: DateComponents(year: year, month: month, day: day)
        )
    }

    private static func failureHealth(stderr: Data) -> ProviderHealth {
        let message = String(decoding: stderr, as: UTF8.self).lowercased()
        if message.contains("no such column") || message.contains("no such table") {
            return .malformedData
        }
        return .temporarilyUnavailable
    }
}

private enum OpenCodeNormalizationError: Error {
    case invalidDay(String)
}
