import Foundation

package final class CodexDesktopStateReader: @unchecked Sendable {
    private let stateURL: URL
    private let logger: AppLogger
    private let activityTailReadBytes = SessionMemoryPolicy.codexDesktopTailReadBytes
    private let activityTailLineLimit = SessionMemoryPolicy.codexDesktopTailLineLimit
    private let snapshotCacheLock = NSLock()
    private var snapshotCache: [SnapshotCacheKey: SnapshotCacheEntry] = [:]
    private static let dateParser = ISO8601Parser()
    package static let childRecordHideAfter = DashboardSessionPolicy.activeHideAfter

    package init(stateURL: URL = AppPaths.codexStateURL, logger: AppLogger = .shared) {
        self.stateURL = stateURL
        self.logger = logger
    }

    package func loadRecentThreads(limit: Int = 8, now: Date = Date()) -> [CodexThreadRecord] {
        guard FileManager.default.fileExists(atPath: stateURL.path) else {
            return []
        }

        do {
            let childCutoffMilliseconds = Int64(now.addingTimeInterval(-Self.childRecordHideAfter).timeIntervalSince1970 * 1000)
            let recentChildSQL = """
            \(Self.threadSelectSQL)
              from threads
             where ifnull(archived, 0) = 0
               and json_valid(ifnull(source, '')) = 1
               and json_extract(source, '$.subagent.thread_spawn.parent_thread_id') is not null
               and ifnull(updated_at_ms, ifnull(updated_at, 0) * 1000) >= \(childCutoffMilliseconds)
             order by updated_at_ms desc, updated_at desc
             limit \(max(1, limit * 4));
            """
            let recentChildRecords = try queryThreadRows(sql: recentChildSQL).compactMap(Self.record)
            let recentChildParentIDs = Array(Set(recentChildRecords.compactMap(\.parentThreadID))).sorted()

            let parentSQL = """
            \(Self.threadSelectSQL)
             from threads
             where ifnull(archived, 0) = 0
               and case
                    when json_valid(ifnull(source, '')) = 1
                    then json_extract(source, '$.subagent.thread_spawn.parent_thread_id')
                    else null
               end is null
             order by updated_at_ms desc, updated_at desc
             limit \(max(1, limit));
            """
            let parentRows = try queryThreadRows(sql: parentSQL)
            var parentRecords = parentRows.compactMap(Self.record)
            if !recentChildParentIDs.isEmpty {
                let childParentSQL = """
                \(Self.threadSelectSQL)
                 from threads
                 where ifnull(archived, 0) = 0
                   and id in (\(Self.sqlStringList(recentChildParentIDs)));
                """
                parentRecords.append(contentsOf: try queryThreadRows(sql: childParentSQL).compactMap(Self.record))
                parentRecords = Self.dedupedRecords(parentRecords)
            }
            let parentIDs = parentRecords.map(\.id)
            guard !parentIDs.isEmpty else {
                return []
            }

            let childSQL = """
            \(Self.threadSelectSQL)
              from threads
             where ifnull(archived, 0) = 0
               and json_valid(ifnull(source, '')) = 1
               and json_extract(source, '$.subagent.thread_spawn.parent_thread_id') in (\(Self.sqlStringList(parentIDs)))
               and ifnull(updated_at_ms, ifnull(updated_at, 0) * 1000) >= \(childCutoffMilliseconds)
             order by updated_at_ms desc, updated_at desc;
            """
            let childRows = try queryThreadRows(sql: childSQL)
            let records = parentRecords + childRows.compactMap(Self.record)
            pruneSnapshotCache(keeping: Set(records.map(\.id)))
            return records
        } catch {
            logger.error("codex.sqlite.read.failed", detail: error.localizedDescription)
            return []
        }
    }

    package static func shouldIncludeChildRecord(updatedAt: Date, now: Date = Date()) -> Bool {
        now.timeIntervalSince(updatedAt) < childRecordHideAfter
    }

    private static func dedupedRecords(_ records: [CodexThreadRecord]) -> [CodexThreadRecord] {
        var seen = Set<String>()
        var result: [CodexThreadRecord] = []
        for record in records where !seen.contains(record.id) {
            seen.insert(record.id)
            result.append(record)
        }
        return result
    }

    package func loadActivities(for record: CodexThreadRecord, limit: Int = 6) -> [ActivityItem] {
        loadThreadSnapshot(for: record, limit: limit).activities
    }

    package func loadThreadSnapshot(for record: CodexThreadRecord, limit: Int = 8) -> CodexThreadSnapshot {
        guard let signature = rolloutSignature(for: record) else {
            return Self.emptySnapshot
        }

        let cacheKey = SnapshotCacheKey(threadID: record.id, limit: limit)
        if let cached = cachedSnapshot(for: cacheKey, signature: signature) {
            return cached
        }

        let url = URL(fileURLWithPath: signature.rolloutPath)
        guard let tail = try? JSONLTailReader.readTailData(from: url, maxBytes: activityTailReadBytes) else {
            return Self.emptySnapshot
        }

        let lineData = JSONLTailReader.tailLines(from: tail.data, startsAtBeginning: tail.startsAtBeginning)
            .suffix(activityTailLineLimit)
        var items: [ActivityItem] = []
        var usage: UsageSnapshot?
        var lastAssistantMessage: String?
        var lastUserMessage: String?
        var isComplete = false
        var completedAt: Date?
        var latestActiveAt: Date?

        for data in lineData {
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            let eventDate = Self.parseDate(object["timestamp"]) ?? Date()
            if let snapshot = usageSnapshot(from: object),
               usage == nil || isAggregateUsageEvent(object) {
                usage = snapshot
            }
            if let message = assistantMessage(from: object) {
                lastAssistantMessage = message
            }
            if let message = userMessage(from: object) {
                lastUserMessage = message
            }
            if isCompletionEvent(object) {
                isComplete = true
                completedAt = eventDate
            } else if isActiveEvent(object) {
                isComplete = false
                latestActiveAt = eventDate
            }
            if var item = activity(from: object) {
                item.id = stableActivityID(from: object, fallbackData: data)
                appendActivity(item, to: &items)
            }
        }

        let snapshot = CodexThreadSnapshot(
            activities: Array(items.suffix(limit)),
            usage: usage,
            lastAssistantMessage: lastAssistantMessage,
            lastUserMessage: lastUserMessage,
            isComplete: isComplete,
            completedAt: completedAt,
            latestActiveAt: latestActiveAt
        )
        storeSnapshot(snapshot, for: cacheKey, signature: signature)
        return snapshot
    }

    private static var emptySnapshot: CodexThreadSnapshot {
        CodexThreadSnapshot(activities: [], usage: nil, lastAssistantMessage: nil, lastUserMessage: nil, isComplete: false)
    }

    private func rolloutSignature(for record: CodexThreadRecord) -> SnapshotCacheSignature? {
        guard !record.rolloutPath.isEmpty else { return nil }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: record.rolloutPath) else {
            return nil
        }
        let fileSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        let modifiedAt = (attributes[.modificationDate] as? Date)?.timeIntervalSinceReferenceDate
        return SnapshotCacheSignature(
            rolloutPath: record.rolloutPath,
            updatedAtMilliseconds: record.updatedAtMilliseconds,
            fileSize: fileSize,
            modifiedAt: modifiedAt
        )
    }

    private func cachedSnapshot(for key: SnapshotCacheKey, signature: SnapshotCacheSignature) -> CodexThreadSnapshot? {
        snapshotCacheLock.lock()
        defer { snapshotCacheLock.unlock() }
        guard let entry = snapshotCache[key],
              entry.signature == signature else {
            return nil
        }
        return entry.snapshot
    }

    private func storeSnapshot(_ snapshot: CodexThreadSnapshot, for key: SnapshotCacheKey, signature: SnapshotCacheSignature) {
        snapshotCacheLock.lock()
        snapshotCache[key] = SnapshotCacheEntry(signature: signature, snapshot: snapshot)
        if snapshotCache.count > SessionMemoryPolicy.codexDesktopSnapshotCacheLimit {
            snapshotCache.removeAll(keepingCapacity: true)
            snapshotCache[key] = SnapshotCacheEntry(signature: signature, snapshot: snapshot)
        }
        snapshotCacheLock.unlock()
    }

    private func pruneSnapshotCache(keeping threadIDs: Set<String>) {
        snapshotCacheLock.lock()
        snapshotCache = snapshotCache.filter { threadIDs.contains($0.key.threadID) }
        snapshotCacheLock.unlock()
    }

    private struct SnapshotCacheKey: Hashable {
        let threadID: String
        let limit: Int
    }

    private struct SnapshotCacheSignature: Equatable {
        let rolloutPath: String
        let updatedAtMilliseconds: Int64
        let fileSize: UInt64
        let modifiedAt: TimeInterval?
    }

    private struct SnapshotCacheEntry {
        let signature: SnapshotCacheSignature
        let snapshot: CodexThreadSnapshot
    }

    private static var threadSelectSQL: String {
        """
        select id,
               ifnull(cwd, '') as cwd,
               ifnull(title, '') as title,
               ifnull(source, '') as source,
               ifnull(approval_mode, '') as approvalMode,
               ifnull(sandbox_policy, '') as sandboxPolicy,
               ifnull(rollout_path, '') as rolloutPath,
               ifnull(updated_at, 0) as updatedAt,
               ifnull(updated_at_ms, ifnull(updated_at, 0) * 1000) as updatedAtMilliseconds,
               ifnull(model, '') as model,
               ifnull(agent_nickname, '') as agentNickname,
               ifnull(agent_role, '') as agentRole
        """
    }

    private func queryThreadRows(sql: String) throws -> [[String: Any]] {
        let data = try run("/usr/bin/sqlite3", arguments: ["-readonly", "-json", stateURL.path, sql])
        return try Self.decodeThreadRows(from: data)
    }

    package static func decodeThreadRows(from data: Data) throws -> [[String: Any]] {
        if data.allSatisfy({ byte in
            byte == 9 || byte == 10 || byte == 13 || byte == 32
        }) {
            return []
        }
        return try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
    }

    private func run(_ executable: String, arguments: [String]) throws -> Data {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = error
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = error.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let message = String(data: errorData, encoding: .utf8) ?? ""
            throw NSError(domain: "VibelslandFree.sqlite", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: message])
        }
        return data
    }

    private static func record(from row: [String: Any]) -> CodexThreadRecord? {
        guard let id = row["id"] as? String else { return nil }
        return CodexThreadRecord(
            id: id,
            cwd: row["cwd"] as? String ?? "",
            title: row["title"] as? String ?? "",
            source: row["source"] as? String ?? "",
            approvalMode: row["approvalMode"] as? String ?? "",
            sandboxPolicy: row["sandboxPolicy"] as? String ?? "",
            rolloutPath: row["rolloutPath"] as? String ?? "",
            updatedAt: parseDate(row["updatedAt"]) ?? Date(),
            updatedAtMilliseconds: int64(row["updatedAtMilliseconds"]),
            model: row["model"] as? String ?? "",
            agentNickname: row["agentNickname"] as? String ?? "",
            agentRole: row["agentRole"] as? String ?? "",
            parentThreadID: parentThreadID(from: row["source"] as? String ?? "")
        )
    }

    private static func sqlStringList(_ values: [String]) -> String {
        values
            .map { "'\($0.replacingOccurrences(of: "'", with: "''"))'" }
            .joined(separator: ", ")
    }

    private static func int64(_ value: Any?) -> Int64 {
        switch value {
        case let value as Int64:
            return value
        case let value as Int:
            return Int64(value)
        case let value as Double:
            return Int64(value)
        case let value as String:
            return Int64(value) ?? 0
        default:
            return 0
        }
    }

    private static func int(_ value: Any?) -> Int {
        switch value {
        case let value as Int:
            return value
        case let value as Int64:
            return Int(value)
        case let value as Double:
            return Int(value)
        case let value as NSNumber:
            return value.intValue
        case let value as String:
            return Int(value) ?? 0
        default:
            return 0
        }
    }

    private static func double(_ value: Any?) -> Double? {
        switch value {
        case let value as Double:
            return value
        case let value as Int:
            return Double(value)
        case let value as NSNumber:
            return value.doubleValue
        case let value as String:
            return Double(value)
        default:
            return nil
        }
    }

    private static func optionalInt(_ value: Any?) -> Int? {
        let parsed = int(value)
        return parsed == 0 ? nil : parsed
    }

    private static func resetDate(_ value: Any?) -> Date? {
        let seconds = int(value)
        guard seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    private static func parseDate(_ value: Any?) -> Date? {
        switch value {
        case let value as Int:
            return Date(timeIntervalSince1970: TimeInterval(value))
        case let value as Double:
            return Date(timeIntervalSince1970: value)
        case let value as String:
            if let number = TimeInterval(value) {
                return Date(timeIntervalSince1970: number)
            }
            return dateParser.date(from: value)
        default:
            return nil
        }
    }

    private final class ISO8601Parser: @unchecked Sendable {
        private let lock = NSLock()
        private let standard = ISO8601DateFormatter()
        private let fractional: ISO8601DateFormatter = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter
        }()

        func date(from value: String) -> Date? {
            lock.lock()
            defer { lock.unlock() }
            if value.contains("."),
               let date = fractional.date(from: value) {
                return date
            }
            return standard.date(from: value)
        }
    }

    private func activity(from object: [String: Any]) -> ActivityItem? {
        let timestamp = Self.parseDate(object["timestamp"]) ?? Date()
        guard let payload = object["payload"] as? [String: Any] else {
            return nil
        }

        if let type = payload["type"] as? String {
            switch type {
            case "agent_message":
                return ActivityItem(symbol: "text.bubble", title: "消息", detail: (payload["message"] as? String) ?? "", date: timestamp)
            case "message":
                return messageActivity(from: payload, timestamp: timestamp)
            case "event_msg":
                return eventMessageActivity(from: payload, timestamp: timestamp)
            case "collab_agent_spawn_begin", "collab_agent_spawn_end":
                return ActivityItem(symbol: "person.2", title: "子智能体", detail: summarize(payload), date: timestamp)
            case "reasoning", "token_count", "exec_command_end":
                return nil
            case "task_complete":
                return ActivityItem(symbol: "checkmark.circle", title: "完成", detail: completionDetail(from: payload), date: timestamp)
            case "function_call", "custom_tool_call", "mcp_tool_call":
                return ActivityItem(symbol: "wrench.and.screwdriver", title: "工具调用", detail: safeToolName(from: payload) ?? "工具", date: timestamp)
            case "function_call_output", "custom_tool_call_output", "mcp_tool_call_end":
                guard let detail = safeToolName(from: payload, includeCallID: false) else { return nil }
                return ActivityItem(symbol: "checkmark.circle", title: "工具完成", detail: detail, date: timestamp)
            case "patch_apply_begin", "patch_apply_end":
                return ActivityItem(symbol: "square.and.pencil", title: "修改文件", detail: type == "patch_apply_end" ? "修改已完成" : "正在修改", date: timestamp)
            case "user_message":
                return ActivityItem(symbol: "person.crop.circle", title: "用户输入", detail: (payload["message"] as? String) ?? "", date: timestamp)
            default:
                let detail = summarize(payload)
                guard !detail.isEmpty else { return nil }
                return ActivityItem(symbol: "waveform.path", title: readableType(type), detail: detail, date: timestamp)
            }
        }

        if let item = payload["type"] as? String {
            return ActivityItem(symbol: "circle", title: item, detail: summarize(payload), date: timestamp)
        }
        return nil
    }

    private func stableActivityID(from object: [String: Any], fallbackData: Data) -> String {
        if let id = object["id"] as? String, !id.isEmpty {
            return id
        }

        let payload = object["payload"] as? [String: Any] ?? [:]
        let nestedItem = payload["item"] as? [String: Any]
        let candidates = [
            nestedItem?["id"] as? String,
            payload["id"] as? String,
            payload["call_id"] as? String
        ].compactMap { $0 }.filter { !$0.isEmpty }

        if !candidates.isEmpty {
            return candidates.joined(separator: ":")
        }

        let timestamp = (object["timestamp"] as? String) ?? String(describing: object["timestamp"] ?? "")
        let type = (payload["type"] as? String) ?? ""
        return "rollout-\(Self.stableHash(Data("\(timestamp):\(type):".utf8) + fallbackData))"
    }

    private static func stableHash(_ data: Data) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    private static func parentThreadID(from source: String) -> String? {
        let data = Data(source.utf8)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let subagent = object["subagent"] as? [String: Any],
              let spawn = subagent["thread_spawn"] as? [String: Any] else {
            return nil
        }
        return spawn["parent_thread_id"] as? String
    }

    private func messageActivity(from payload: [String: Any], timestamp: Date) -> ActivityItem? {
        if let role = payload["role"] as? String,
           let content = payload["content"] as? [[String: Any]] {
            let text = content.compactMap { item -> String? in
                item["text"] as? String
            }.joined(separator: " ")
            guard !text.isEmpty else { return nil }
            return ActivityItem(
                symbol: role == "user" ? "person.crop.circle" : "text.bubble",
                title: role == "user" ? "用户输入" : "消息",
                detail: String(text.prefix(160)),
                date: timestamp
            )
        }
        return nil
    }

    private func eventMessageActivity(from payload: [String: Any], timestamp: Date) -> ActivityItem? {
        guard let eventPayload = payload["payload"] as? [String: Any],
              let eventType = eventPayload["type"] as? String else {
            return nil
        }
        switch eventType {
        case "agent_message":
            return ActivityItem(symbol: "text.bubble", title: "消息", detail: (eventPayload["message"] as? String) ?? "", date: timestamp)
        case "token_count":
            return nil
        case "exec_command_end":
            return nil
        case "task_complete":
            return ActivityItem(symbol: "checkmark.circle", title: "完成", detail: completionDetail(from: eventPayload), date: timestamp)
        case "patch_apply_begin", "patch_apply_end":
            return ActivityItem(symbol: "square.and.pencil", title: "修改文件", detail: eventType == "patch_apply_end" ? "修改已完成" : "正在修改", date: timestamp)
        case "user_message":
            return ActivityItem(symbol: "person.crop.circle", title: "用户输入", detail: (eventPayload["message"] as? String) ?? "", date: timestamp)
        default:
            let detail = summarize(eventPayload)
            guard !detail.isEmpty else { return nil }
            return ActivityItem(symbol: "waveform.path", title: readableType(eventType), detail: detail, date: timestamp)
        }
    }

    private func assistantMessage(from object: [String: Any]) -> String? {
        guard let payload = object["payload"] as? [String: Any] else {
            return nil
        }

        if let last = payload["last_agent_message"] as? String, !last.isEmpty {
            return DisplayTextSanitizer.sanitize(String(last.prefix(700)))
        }
        if let last = payload["last_assistant_message"] as? String, !last.isEmpty {
            return DisplayTextSanitizer.sanitize(String(last.prefix(700)))
        }
        if payload["type"] as? String == "agent_message",
           let message = payload["message"] as? String,
           !message.isEmpty {
            return DisplayTextSanitizer.sanitize(String(message.prefix(700)))
        }
        if payload["type"] as? String == "message",
           payload["role"] as? String == "assistant",
           let message = messageText(from: payload),
           !message.isEmpty {
            return DisplayTextSanitizer.sanitize(String(message.prefix(700)))
        }
        if object["type"] as? String == "event_msg",
           let nested = payload["payload"] as? [String: Any] {
            return assistantMessage(from: ["payload": nested])
        }
        return nil
    }

    private func userMessage(from object: [String: Any]) -> String? {
        guard let payload = object["payload"] as? [String: Any] else {
            return nil
        }
        if payload["type"] as? String == "user_message",
           let message = payload["message"] as? String,
           !message.isEmpty {
            return DisplayTextSanitizer.sanitize(String(message.prefix(700)))
        }
        if payload["type"] as? String == "message",
           payload["role"] as? String == "user",
           let message = messageText(from: payload),
           !message.isEmpty {
            return DisplayTextSanitizer.sanitize(String(message.prefix(700)))
        }
        if object["type"] as? String == "event_msg",
           let nested = payload["payload"] as? [String: Any] {
            return userMessage(from: ["payload": nested])
        }
        return nil
    }

    private func usageSnapshot(from object: [String: Any]) -> UsageSnapshot? {
        guard let payload = object["payload"] as? [String: Any],
              payload["type"] as? String == "token_count",
              let info = payload["info"] as? [String: Any] else {
            return nil
        }
        let totalUsage = info["total_token_usage"] as? [String: Any]
        let lastUsage = info["last_token_usage"] as? [String: Any]
        let rateLimits = object["rate_limits"] as? [String: Any]
        let primary = rateLimits?["primary"] as? [String: Any]
        let secondary = rateLimits?["secondary"] as? [String: Any]
        return UsageSnapshot(
            lastTokens: Self.int(lastUsage?["total_tokens"]),
            totalTokens: Self.int(totalUsage?["total_tokens"]),
            contextWindow: Self.int(info["model_context_window"]),
            primaryUsedPercent: Self.double(primary?["used_percent"]),
            secondaryUsedPercent: Self.double(secondary?["used_percent"]),
            primaryWindowMinutes: Self.optionalInt(primary?["window_minutes"]),
            secondaryWindowMinutes: Self.optionalInt(secondary?["window_minutes"]),
            primaryResetsAt: Self.resetDate(primary?["resets_at"]),
            secondaryResetsAt: Self.resetDate(secondary?["resets_at"]),
            planType: rateLimits?["plan_type"] as? String,
            limitName: rateLimits?["limit_name"] as? String
        )
    }

    private func isAggregateUsageEvent(_ object: [String: Any]) -> Bool {
        guard let rateLimits = object["rate_limits"] as? [String: Any],
              let limitID = rateLimits["limit_id"] as? String else {
            return true
        }
        return limitID == "codex" || limitID == "claude"
    }

    private func isCompletionEvent(_ object: [String: Any]) -> Bool {
        guard let payload = object["payload"] as? [String: Any] else {
            return false
        }
        if payload["type"] as? String == "task_complete" {
            return true
        }
        if object["type"] as? String == "event_msg",
           let nested = payload["payload"] as? [String: Any],
           nested["type"] as? String == "task_complete" {
            return true
        }
        return false
    }

    private func isActiveEvent(_ object: [String: Any]) -> Bool {
        guard let payload = object["payload"] as? [String: Any] else {
            return false
        }
        let ignored = Set([
            "reasoning",
            "token_count",
            "exec_command_end",
            "function_call_output",
            "custom_tool_call_output",
            "mcp_tool_call_end"
        ])
        if let type = payload["type"] as? String {
            return !ignored.contains(type)
        }
        if object["type"] as? String == "event_msg",
           let nested = payload["payload"] as? [String: Any],
           let type = nested["type"] as? String {
            return !ignored.contains(type)
        }
        return false
    }

    private func messageText(from payload: [String: Any]) -> String? {
        guard let content = payload["content"] as? [[String: Any]] else {
            return nil
        }
        let text = content.compactMap { item -> String? in
            item["text"] as? String
        }.joined(separator: " ")
        return text.isEmpty ? nil : text
    }

    private func appendActivity(_ item: ActivityItem, to items: inout [ActivityItem]) {
        let detail = item.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let titlesAllowingEmptyDetail = Set(["完成", "工具调用", "修改文件"])
        guard !detail.isEmpty || titlesAllowingEmptyDetail.contains(item.title) else {
            return
        }
        if items.suffix(4).contains(where: { existing in
            existing.title == item.title &&
            existing.detail.trimmingCharacters(in: .whitespacesAndNewlines) == detail
        }) {
            return
        }
        items.append(item)
    }

    private func completionDetail(from payload: [String: Any]) -> String {
        if let message = payload["last_agent_message"] as? String, !message.isEmpty {
            return String(DisplayTextSanitizer.sanitize(message).prefix(180))
        }
        if let duration = payload["duration_ms"] as? NSNumber {
            return "耗时 \(max(1, duration.intValue / 1000)) 秒"
        }
        return "任务完成"
    }

    private func summarize(_ dictionary: [String: Any]) -> String {
        if let nickname = dictionary["agent_nickname"] as? String {
            return nickname
        }
        if let target = dictionary["target"] as? String {
            return target
        }
        if dictionary.keys.contains("encrypted_content") {
            return ""
        }
        if let message = dictionary["message"] as? String {
            return String(message.prefix(160))
        }
        if let name = dictionary["name"] as? String {
            return name
        }
        let safeKeys = dictionary.keys
            .filter { !["content", "encrypted_content", "output", "stderr", "stdout"].contains($0) }
            .sorted()
            .prefix(4)
        return safeKeys.joined(separator: ", ")
    }

    private func safeToolName(from dictionary: [String: Any], includeCallID: Bool = true) -> String? {
        if let name = dictionary["name"] as? String {
            return name
        }
        if let invocation = dictionary["invocation"] as? [String: Any],
           let name = invocation["name"] as? String {
            return name
        }
        if includeCallID, let callID = dictionary["call_id"] as? String {
            return callID
        }
        return nil
    }

    private func readableType(_ type: String) -> String {
        switch type {
        case "event_msg": return "事件"
        case "response_item": return "响应"
        default: return type
        }
    }
}
