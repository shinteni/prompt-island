import Foundation

/// 一天的本地统计：只有计数与合计，不含任何提示词、命令或会话内容。
package struct DailyStats: Codable, Equatable {
    package var sessionsStarted: [String: Int] = [:]
    package var sessionsCompleted = 0
    package var sessionsFailed = 0
    package var approvalsReceived = 0
    package var approvalsAccepted = 0
    package var approvalsDeclined = 0
    package var approvalsCancelled = 0
    package var tokens = 0
    package var estimatedCostUSD = 0.0

    package init() {}

    package var sessionsStartedTotal: Int {
        sessionsStarted.values.reduce(0, +)
    }

    package mutating func recordSessionStarted(source: AgentSource) {
        sessionsStarted[source.rawValue, default: 0] += 1
    }

    package mutating func recordApprovalResolution(_ state: ApprovalResolutionState) {
        switch state {
        case .accepted:
            approvalsAccepted += 1
        case .declined:
            approvalsDeclined += 1
        case .cancelled:
            approvalsCancelled += 1
        case .pending, .resolving, .timedOut, .sendFailed, .disconnected:
            break
        }
    }

    package mutating func merge(_ other: DailyStats) {
        for (key, value) in other.sessionsStarted {
            sessionsStarted[key, default: 0] += value
        }
        sessionsCompleted += other.sessionsCompleted
        sessionsFailed += other.sessionsFailed
        approvalsReceived += other.approvalsReceived
        approvalsAccepted += other.approvalsAccepted
        approvalsDeclined += other.approvalsDeclined
        approvalsCancelled += other.approvalsCancelled
        tokens += other.tokens
        estimatedCostUSD += other.estimatedCostUSD
    }
}

package enum UsageStatsPolicy {
    package static let retentionDays = 30

    package static func dayKey(
        for date: Date,
        calendar: Calendar = .current
    ) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    /// 最近 count 天的 key（含当天），从旧到新。
    package static func recentDayKeys(
        endingAt date: Date = Date(),
        count: Int = 7,
        calendar: Calendar = .current
    ) -> [String] {
        (0..<max(0, count)).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: date).map { dayKey(for: $0, calendar: calendar) }
        }
    }

    package static func prune(
        _ days: [String: DailyStats],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [String: DailyStats] {
        let keep = Set(recentDayKeys(endingAt: now, count: retentionDays, calendar: calendar))
        return days.filter { keep.contains($0.key) }
    }

    package static func total(of days: [DailyStats]) -> DailyStats {
        var result = DailyStats()
        for day in days {
            result.merge(day)
        }
        return result
    }

    /// 会话累计值的日增量：token/成本都是会话内单调递增的累计数，
    /// 记录相邻快照的正向差值；数值回退（会话重置）时按新值重新起算。
    package static func usageDelta(
        previous: UsageSnapshot?,
        current: UsageSnapshot?
    ) -> (tokens: Int, costUSD: Double) {
        guard let current else { return (0, 0) }
        let previousTokens = previous?.totalTokens ?? 0
        let previousCost = previous?.estimatedCostUSD ?? 0
        let currentCost = current.estimatedCostUSD ?? 0
        let tokens = current.totalTokens >= previousTokens
            ? current.totalTokens - previousTokens
            : current.totalTokens
        let cost = currentCost >= previousCost
            ? currentCost - previousCost
            : currentCost
        return (max(0, tokens), max(0, cost))
    }
}

/// 本地统计的持久化：Application Support/VibelslandFree/stats.json。
/// 只写聚合计数；保留最近 30 天；写入去抖合并。
@MainActor
package final class UsageStatsStore: ObservableObject {
    @Published package private(set) var days: [String: DailyStats]

    private let url: URL
    private let logger: AppLogger
    private var saveTimer: Timer?

    package init(url: URL = AppPaths.statsURL, logger: AppLogger = .shared) {
        self.url = url
        self.logger = logger
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([String: DailyStats].self, from: data) {
            days = UsageStatsPolicy.prune(decoded)
        } else {
            days = [:]
        }
    }

    package func record(on date: Date = Date(), _ mutation: (inout DailyStats) -> Void) {
        let key = UsageStatsPolicy.dayKey(for: date)
        var day = days[key] ?? DailyStats()
        mutation(&day)
        days[key] = day
        days = UsageStatsPolicy.prune(days, now: date)
        scheduleSave()
    }

    package func stats(forDayKey key: String) -> DailyStats {
        days[key] ?? DailyStats()
    }

    package func todayStats(now: Date = Date()) -> DailyStats {
        stats(forDayKey: UsageStatsPolicy.dayKey(for: now))
    }

    package func weekStats(now: Date = Date()) -> DailyStats {
        UsageStatsPolicy.total(of: UsageStatsPolicy.recentDayKeys(endingAt: now).map { stats(forDayKey: $0) })
    }

    package func recentDays(now: Date = Date(), count: Int = 7) -> [(key: String, stats: DailyStats)] {
        UsageStatsPolicy.recentDayKeys(endingAt: now, count: count).map { ($0, stats(forDayKey: $0)) }
    }

    package func clearAll() {
        days = [:]
        saveTimer?.invalidate()
        saveTimer = nil
        try? FileManager.default.removeItem(at: url)
        logger.info("stats.cleared")
    }

    package func flush() {
        saveTimer?.invalidate()
        saveTimer = nil
        save()
    }

    private func scheduleSave() {
        guard saveTimer == nil else { return }
        let timer = Timer(timeInterval: 2.0, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.saveTimer = nil
                self?.save()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        saveTimer = timer
    }

    private func save() {
        do {
            try AppPaths.ensureRuntimeDirectories()
            let data = try JSONEncoder.pretty.encode(days)
            try data.write(to: url, options: [.atomic])
        } catch {
            logger.error("stats.save.failed", detail: error.localizedDescription)
        }
    }
}
