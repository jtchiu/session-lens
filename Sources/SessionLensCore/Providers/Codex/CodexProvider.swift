import Foundation

public struct CodexProvider: UsageProvider {
    public let id = ProviderID.codex

    private let client: any CodexAccountReading

    public init(client: any CodexAccountReading) {
        self.client = client
    }

    public func refresh(at now: Date) async -> ProviderSnapshot {
        do {
            let rateLimits = try await client.readRateLimits()
            let usage = try await client.readUsage()
            do {
                return try Self.snapshot(
                    rateLimits: rateLimits,
                    usage: usage,
                    observedAt: now
                )
            } catch {
                return .unavailable(
                    provider: id,
                    health: .malformedData,
                    observedAt: now
                )
            }
        } catch {
            return .unavailable(
                provider: id,
                health: Self.health(for: error),
                observedAt: now
            )
        }
    }

    public static func label(for minutes: Int?) -> String {
        switch minutes {
        case 300:
            "5-hour"
        case 10_080:
            "Weekly"
        case let .some(value):
            "\(value) min"
        case nil:
            "Quota"
        }
    }

    private static func snapshot(
        rateLimits: CodexRateLimitsResponse,
        usage: CodexAccountUsageResponse,
        observedAt: Date
    ) throws -> ProviderSnapshot {
        let snapshots = [rateLimits.rateLimits]
            + (rateLimits.rateLimitsByLimitId?.values.map { $0 } ?? [])
        let quotaWindows = normalizedWindows(from: snapshots)
        let dailyBuckets = try (usage.dailyUsageBuckets ?? [])
            .map { bucket -> UsageBucket in
                guard let date = localDay(from: bucket.startDate) else {
                    throw CodexNormalizationError.invalidDay(bucket.startDate)
                }
                return UsageBucket(
                    day: date,
                    tokens: max(0, bucket.tokens),
                    costUSD: nil
                )
            }
            .sorted { $0.day < $1.day }
        let tokens = usage.summary.lifetimeTokens.map {
            TokenBreakdown(
                input: 0,
                output: 0,
                reasoning: 0,
                cacheRead: 0,
                cacheWrite: 0,
                uncategorized: max(0, $0)
            )
        }
        let hasPlan = snapshots.contains { snapshot in
            guard let planType = snapshot.planType else { return false }
            return !planType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        return ProviderSnapshot(
            provider: .codex,
            observedAt: observedAt,
            health: .ready,
            tokens: tokens,
            costDisplay: hasPlan ? .includedWithPlan : .unavailable,
            dailyBuckets: dailyBuckets,
            quotaWindows: quotaWindows,
            modelBreakdowns: []
        )
    }

    private static func normalizedWindows(
        from snapshots: [CodexRateLimitSnapshot]
    ) -> [QuotaWindow] {
        var candidates: [CodexWindowKey: CodexWindowCandidate] = [:]

        for snapshot in snapshots {
            for window in [snapshot.primary, snapshot.secondary].compactMap({ $0 }) {
                let key = CodexWindowKey(
                    durationMinutes: window.windowDurationMins,
                    resetsAt: window.resetsAt
                )
                let candidate = CodexWindowCandidate(
                    limitID: snapshot.limitId,
                    window: window
                )
                if let existing = candidates[key] {
                    if candidate.window.usedPercent > existing.window.usedPercent {
                        candidates[key] = candidate
                    }
                } else {
                    candidates[key] = candidate
                }
            }
        }

        return candidates
            .map { key, candidate in
                QuotaWindow(
                    id: key.id(limitID: candidate.limitID),
                    label: label(for: key.durationMinutes),
                    durationMinutes: key.durationMinutes,
                    usedPercent: Double(candidate.window.usedPercent),
                    resetsAt: key.resetsAt.map {
                        Date(timeIntervalSince1970: Double($0))
                    },
                    provenance: .exactProvider
                )
            }
            .sorted { left, right in
                let leftDuration = left.durationMinutes ?? Int.max
                let rightDuration = right.durationMinutes ?? Int.max
                if leftDuration != rightDuration {
                    return leftDuration < rightDuration
                }
                return (left.resetsAt ?? .distantFuture)
                    < (right.resetsAt ?? .distantFuture)
            }
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

    private static func health(for error: Error) -> ProviderHealth {
        switch error {
        case JSONLTransportError.timedOut:
            .timedOut
        case JSONLTransportError.launchFailed, JSONLTransportError.notStarted:
            .toolMissing
        case JSONLTransportError.malformedJSON,
            CodexAppServerClientError.malformedResponse,
            is DecodingError:
            .malformedData
        default:
            .temporarilyUnavailable
        }
    }
}

private struct CodexWindowKey: Hashable {
    let durationMinutes: Int?
    let resetsAt: Int64?

    func id(limitID: String?) -> String {
        let duration = durationMinutes.map(String.init) ?? "unknown"
        let reset = resetsAt.map(String.init) ?? "unknown"
        return "\(limitID ?? "quota"):\(duration):\(reset)"
    }
}

private struct CodexWindowCandidate {
    let limitID: String?
    let window: CodexRateLimitWindow
}

private enum CodexNormalizationError: Error {
    case invalidDay(String)
}
