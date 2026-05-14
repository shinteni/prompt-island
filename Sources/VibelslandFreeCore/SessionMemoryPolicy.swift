import Foundation

package enum SessionMemoryPolicy {
    package static let maxSessionActivityItems = 8
    package static let maxSessionMessageCharacters = 700
    package static let codexDesktopTailReadBytes = 256_000
    package static let codexDesktopTailLineLimit = 72
    package static let transcriptTailReadBytes = 640_000
    package static let transcriptTailLineLimit = 120
    package static let codexDesktopSnapshotCacheLimit = 32
    package static let soundCooldownMaxAge: TimeInterval = 15 * 60

    package static func compact(_ session: AgentSession) -> AgentSession {
        var compacted = session
        compacted.title = trimmed(compacted.title, limit: maxSessionMessageCharacters)
        compacted.prompt = trimmed(compacted.prompt, limit: maxSessionMessageCharacters)
        compacted.lastAssistantMessage = compacted.lastAssistantMessage.map {
            trimmed($0, limit: maxSessionMessageCharacters)
        }
        compacted.lastUserMessage = compacted.lastUserMessage.map {
            trimmed($0, limit: maxSessionMessageCharacters)
        }
        compacted.activity = compactActivities(compacted.activity)
        return compacted
    }

    package static func compactActivities(_ activities: [ActivityItem]) -> [ActivityItem] {
        var seen = Set<String>()
        let filtered = activities.filter { item in
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = item.detail.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !detail.isEmpty else { return false }
            guard !["task_complete", "token_count", "reasoning"].contains(title) else { return false }
            let key = "\(title)|\(detail)"
            return seen.insert(key).inserted
        }
        return Array(filtered.suffix(maxSessionActivityItems))
    }

    package static func compactCooldowns(
        _ cooldowns: [String: Date],
        now: Date = Date()
    ) -> [String: Date] {
        cooldowns.filter { now.timeIntervalSince($0.value) <= soundCooldownMaxAge }
    }

    private static func trimmed(_ value: String, limit: Int) -> String {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count > limit else {
            return cleaned
        }
        return String(cleaned.prefix(limit))
    }
}
