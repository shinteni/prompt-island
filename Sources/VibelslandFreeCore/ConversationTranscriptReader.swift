import Foundation

package final class ConversationTranscriptReader: @unchecked Sendable {
    private let fileManager: FileManager
    private let homeURL: URL
    private let tailReadBytes = SessionMemoryPolicy.transcriptTailReadBytes
    private let tailLineLimit = SessionMemoryPolicy.transcriptTailLineLimit
    private let dateParser = ISO8601Parser()

    /// Claude 用量按文件增量累加：记录已解析到的字节位置，事件到来时只读
    /// 追加部分。首次遇到超大文件时只回溯尾部一段，保证读取始终有界。
    private struct ClaudeUsageCacheEntry {
        var parsedBytes: UInt64
        var aggregate: ClaudeUsageAggregate
    }

    private static let claudeUsageInitialScanBytes: UInt64 = 10 * 1024 * 1024
    private static let claudeUsageMarker = Data("\"usage\"".utf8)
    private let usageCacheLock = NSLock()
    private var claudeUsageCache: [String: ClaudeUsageCacheEntry] = [:]

    package init(fileManager: FileManager = .default, homeURL: URL = AppPaths.home) {
        self.fileManager = fileManager
        self.homeURL = homeURL
    }

    package func loadSnapshot(for event: AgentEvent, limit: Int = 8) -> AgentTranscriptSnapshot? {
        for url in transcriptURLs(for: event) {
            guard fileManager.fileExists(atPath: url.path),
                  let snapshot = loadSnapshot(from: url, source: event.source, limit: limit) else {
                continue
            }
            return snapshot
        }
        return nil
    }

    package func loadSnapshot(from url: URL, source: AgentSource, limit: Int = 8) -> AgentTranscriptSnapshot? {
        guard let tail = try? JSONLTailReader.readTailData(from: url, maxBytes: tailReadBytes) else {
            return nil
        }

        var transcriptActivities: [ActivityItem] = []
        var usage: UsageSnapshot?
        var lastAssistantMessage: String?
        var lastUserMessage: String?
        var isComplete = false
        var completedAt: Date?
        var latestActiveAt: Date?

        for data in JSONLTailReader.tailLines(from: tail.data, startsAtBeginning: tail.startsAtBeginning).suffix(tailLineLimit) {
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            let eventDate = parseDate(object["timestamp"])

            if let snapshot = usageSnapshot(from: object) {
                usage = snapshot
            }
            if let message = userMessage(from: object, source: source) {
                lastUserMessage = message
            }
            if let message = assistantMessage(from: object, source: source) {
                lastAssistantMessage = message
            }
            if isCompletionEvent(object, source: source) {
                isComplete = true
                completedAt = eventDate
            } else if isActiveEvent(object, source: source) {
                isComplete = false
                latestActiveAt = eventDate
            }
            for item in activities(from: object, source: source) {
                appendActivity(item, to: &transcriptActivities)
            }
        }

        if source == .claudeCode,
           let aggregate = claudeUsageAggregate(for: url),
           let snapshot = ClaudeUsagePolicy.usageSnapshot(from: aggregate) {
            usage = snapshot
        }

        return AgentTranscriptSnapshot(
            activities: Array(transcriptActivities.suffix(limit)),
            usage: usage,
            lastAssistantMessage: lastAssistantMessage,
            lastUserMessage: lastUserMessage,
            isComplete: isComplete,
            completedAt: completedAt,
            latestActiveAt: latestActiveAt
        )
    }

    package func claudeUsageAggregate(for url: URL) -> ClaudeUsageAggregate? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = (attributes[.size] as? NSNumber)?.uint64Value else {
            return nil
        }

        usageCacheLock.lock()
        var entry = claudeUsageCache[url.path]
        usageCacheLock.unlock()

        // 文件被截断或轮转时重来。
        if let cached = entry, cached.parsedBytes > size {
            entry = nil
        }
        if let cached = entry, cached.parsedBytes == size {
            return cached.aggregate
        }

        var aggregate = entry?.aggregate ?? ClaudeUsageAggregate()
        var offset = entry?.parsedBytes ?? 0
        var skipsPartialFirstLine = false
        // 无缓存且文件太大时，只回溯尾部一段；增量意外过大时同样重置回溯，
        // 保证单次读取有界。
        if size - offset > Self.claudeUsageInitialScanBytes {
            aggregate = ClaudeUsageAggregate()
            offset = size - Self.claudeUsageInitialScanBytes
            skipsPartialFirstLine = true
        }

        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: offset)) != nil,
              let data = try? handle.readToEnd(), !data.isEmpty else {
            return aggregate.turns > 0 ? aggregate : nil
        }

        var body = data
        if skipsPartialFirstLine {
            if let firstNewline = body.firstIndex(of: 0x0A) {
                let dropped = body.distance(from: body.startIndex, to: firstNewline) + 1
                offset += UInt64(dropped)
                body = body[body.index(after: firstNewline)...]
            } else {
                return aggregate.turns > 0 ? aggregate : nil
            }
        }

        // 只消费到最后一个完整行，写到一半的行留给下次。
        guard let lastNewline = body.lastIndex(of: 0x0A) else {
            storeClaudeUsage(ClaudeUsageCacheEntry(parsedBytes: offset, aggregate: aggregate), for: url.path)
            return aggregate.turns > 0 ? aggregate : nil
        }
        let complete = body[body.startIndex...lastNewline]
        let consumedBytes = UInt64(complete.count)

        for line in complete.split(separator: 0x0A) {
            guard line.range(of: Self.claudeUsageMarker) != nil,
                  let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let turn = ClaudeUsagePolicy.parseTurn(from: object) else {
                continue
            }
            aggregate.add(turn)
        }

        storeClaudeUsage(
            ClaudeUsageCacheEntry(parsedBytes: offset + consumedBytes, aggregate: aggregate),
            for: url.path
        )
        return aggregate.turns > 0 ? aggregate : nil
    }

    private func storeClaudeUsage(_ entry: ClaudeUsageCacheEntry, for path: String) {
        usageCacheLock.lock()
        claudeUsageCache[path] = entry
        usageCacheLock.unlock()
    }

    private func transcriptURLs(for event: AgentEvent) -> [URL] {
        let object = event.payload.objectValue ?? [:]
        var urls: [URL] = [
            string(object["transcript_path"]),
            string(object["codex_transcript_path"]),
            string(object["transcriptPath"]),
            string(object["rollout_path"])
        ]
            .compactMap { $0 }
            .map(expandedURL)

        if let sessionID = event.sessionId, !sessionID.isEmpty {
            urls.append(contentsOf: discoveredTranscriptURLs(sessionID: sessionID, source: event.source))
        }

        var seen = Set<String>()
        return urls.filter { seen.insert($0.path).inserted }
    }

    private func discoveredTranscriptURLs(sessionID: String, source: AgentSource) -> [URL] {
        switch source {
        case .claudeCode:
            let root = homeURL.appendingPathComponent(".claude/projects", isDirectory: true)
            return findJSONLFiles(under: root) { $0.lastPathComponent == "\(sessionID).jsonl" }
        case .codexCli:
            let root = homeURL.appendingPathComponent(".codex/sessions", isDirectory: true)
            return findJSONLFiles(under: root) { $0.lastPathComponent.contains(sessionID) }
        case .codexDesktop, .unknown:
            return []
        }
    }

    private func findJSONLFiles(under root: URL, matches: (URL) -> Bool) -> [URL] {
        guard fileManager.fileExists(atPath: root.path),
              let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
              ) else {
            return []
        }

        var results: [URL] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl", matches(url) else { continue }
            results.append(url)
            if results.count >= 3 {
                break
            }
        }
        return results
    }

    private func activities(from object: [String: Any], source: AgentSource) -> [ActivityItem] {
        switch source {
        case .claudeCode:
            return claudeActivities(from: object)
        case .codexCli, .codexDesktop, .unknown:
            return codexActivities(from: object)
        }
    }

    private func claudeActivities(from object: [String: Any]) -> [ActivityItem] {
        let timestamp = parseDate(object["timestamp"]) ?? Date()
        let type = object["type"] as? String
        var items: [ActivityItem] = []

        if type == "user",
           let message = object["message"] as? [String: Any],
           let content = message["content"] as? [[String: Any]] {
            for item in content where item["type"] as? String == "tool_result" {
                let detail = toolResultDetail(from: item)
                if !detail.isEmpty {
                    items.append(ActivityItem(symbol: "checkmark.circle", title: "工具完成", detail: detail, date: timestamp))
                }
            }
        }

        if type == "assistant",
           let message = object["message"] as? [String: Any],
           let content = message["content"] as? [[String: Any]] {
            for item in content where item["type"] as? String == "tool_use" {
                let name = string(item["name"]) ?? "工具"
                items.append(ActivityItem(symbol: "wrench.and.screwdriver", title: "工具调用", detail: DisplayTextSanitizer.sanitize(name), date: timestamp))
            }
        }

        if type == "system",
           object["subtype"] as? String == "stop_hook_summary" {
            items.append(ActivityItem(symbol: "checkmark.circle", title: "完成", detail: "任务完成", date: timestamp))
        }

        return items
    }

    private func codexActivities(from object: [String: Any]) -> [ActivityItem] {
        let timestamp = parseDate(object["timestamp"]) ?? Date()
        let payload = object["payload"] as? [String: Any] ?? [:]
        let type = payload["type"] as? String ?? object["type"] as? String ?? ""

        if object["type"] as? String == "event_msg",
           let nested = payload["payload"] as? [String: Any] {
            return codexActivities(from: ["timestamp": object["timestamp"] as Any, "payload": nested])
        }

        switch type {
        case "function_call", "custom_tool_call", "mcp_tool_call":
            return [ActivityItem(symbol: "wrench.and.screwdriver", title: "工具调用", detail: safeToolName(from: payload), date: timestamp)]
        case "function_call_output", "custom_tool_call_output", "mcp_tool_call_end":
            return [ActivityItem(symbol: "checkmark.circle", title: "工具完成", detail: safeToolName(from: payload), date: timestamp)]
        case "patch_apply_begin", "patch_apply_end":
            return [ActivityItem(symbol: "square.and.pencil", title: "修改文件", detail: type == "patch_apply_end" ? "修改已完成" : "正在修改", date: timestamp)]
        case "task_complete":
            return [ActivityItem(symbol: "checkmark.circle", title: "完成", detail: completionDetail(from: payload), date: timestamp)]
        case "agent_message":
            if let message = string(payload["message"]) {
                return [ActivityItem(symbol: "text.bubble", title: "消息", detail: DisplayTextSanitizer.sanitize(String(message.prefix(180))), date: timestamp)]
            }
        case "user_message":
            if let message = string(payload["message"]) {
                return [ActivityItem(symbol: "person.crop.circle", title: "用户输入", detail: DisplayTextSanitizer.sanitize(String(message.prefix(180))), date: timestamp)]
            }
        default:
            break
        }
        return []
    }

    private func assistantMessage(from object: [String: Any], source: AgentSource) -> String? {
        switch source {
        case .claudeCode:
            guard object["type"] as? String == "assistant",
                  let message = object["message"] as? [String: Any] else {
                return nil
            }
            return sanitizedMessageText(from: message["content"])
        case .codexCli, .codexDesktop, .unknown:
            return codexAssistantMessage(from: object)
        }
    }

    private func userMessage(from object: [String: Any], source: AgentSource) -> String? {
        switch source {
        case .claudeCode:
            guard object["type"] as? String == "user",
                  let message = object["message"] as? [String: Any] else {
                return nil
            }
            return sanitizedMessageText(from: message["content"], skipToolResults: true)
        case .codexCli, .codexDesktop, .unknown:
            return codexUserMessage(from: object)
        }
    }

    private func codexAssistantMessage(from object: [String: Any]) -> String? {
        guard let payload = object["payload"] as? [String: Any] else {
            return nil
        }

        if let message = string(payload["last_agent_message"]) ?? string(payload["last_assistant_message"]) {
            return sanitized(message, limit: 700)
        }
        if payload["type"] as? String == "agent_message",
           let message = string(payload["message"]) {
            return sanitized(message, limit: 700)
        }
        if payload["type"] as? String == "message",
           payload["role"] as? String == "assistant" {
            return sanitizedMessageText(from: payload["content"])
        }
        if object["type"] as? String == "event_msg",
           let nested = payload["payload"] as? [String: Any] {
            return codexAssistantMessage(from: ["payload": nested])
        }
        return nil
    }

    private func codexUserMessage(from object: [String: Any]) -> String? {
        guard let payload = object["payload"] as? [String: Any] else {
            return nil
        }

        if payload["type"] as? String == "user_message",
           let message = string(payload["message"]) {
            return sanitized(message, limit: 700)
        }
        if payload["type"] as? String == "message",
           payload["role"] as? String == "user" {
            return sanitizedMessageText(from: payload["content"], skipToolResults: true)
        }
        if object["type"] as? String == "response_item",
           payload["type"] as? String == "message",
           payload["role"] as? String == "user" {
            return sanitizedMessageText(from: payload["content"], skipToolResults: true)
        }
        if object["type"] as? String == "event_msg",
           let nested = payload["payload"] as? [String: Any] {
            return codexUserMessage(from: ["payload": nested])
        }
        return nil
    }

    private func isCompletionEvent(_ object: [String: Any], source: AgentSource) -> Bool {
        if source == .claudeCode {
            return object["type"] as? String == "system" && object["subtype"] as? String == "stop_hook_summary"
        }

        let payload = object["payload"] as? [String: Any] ?? [:]
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

    private func isActiveEvent(_ object: [String: Any], source: AgentSource) -> Bool {
        if source == .claudeCode {
            return ["user", "assistant"].contains(object["type"] as? String ?? "")
        }

        let payload = object["payload"] as? [String: Any] ?? [:]
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
            lastTokens: int(lastUsage?["total_tokens"]),
            totalTokens: int(totalUsage?["total_tokens"]),
            contextWindow: int(info["model_context_window"]),
            primaryUsedPercent: double(primary?["used_percent"]),
            secondaryUsedPercent: double(secondary?["used_percent"]),
            primaryWindowMinutes: optionalInt(primary?["window_minutes"]),
            secondaryWindowMinutes: optionalInt(secondary?["window_minutes"]),
            primaryResetsAt: resetDate(primary?["resets_at"]),
            secondaryResetsAt: resetDate(secondary?["resets_at"]),
            planType: rateLimits?["plan_type"] as? String,
            limitName: rateLimits?["limit_name"] as? String
        )
    }

    private func sanitizedMessageText(from value: Any?, skipToolResults: Bool = false) -> String? {
        let raw: String
        switch value {
        case let string as String:
            raw = string
        case let array as [[String: Any]]:
            raw = array.compactMap { item -> String? in
                if skipToolResults && item["type"] as? String == "tool_result" {
                    return nil
                }
                return string(item["text"])
                    ?? string(item["content"])
                    ?? string(item["input_text"])
                    ?? string(item["output_text"])
            }.joined(separator: " ")
        default:
            return nil
        }
        return sanitized(raw, limit: 700)
    }

    private func toolResultDetail(from item: [String: Any]) -> String {
        if let content = string(item["content"]), !content.isEmpty {
            return sanitized(content, limit: 90) ?? ""
        }
        return "工具已返回"
    }

    private func safeToolName(from payload: [String: Any]) -> String {
        let raw = string(payload["name"])
            ?? string(payload["tool_name"])
            ?? string(payload["call_id"])
            ?? "工具"
        return DisplayTextSanitizer.sanitize(raw)
    }

    private func completionDetail(from payload: [String: Any]) -> String {
        if let message = string(payload["last_agent_message"]) ?? string(payload["last_assistant_message"]) {
            return sanitized(message, limit: 180) ?? "任务完成"
        }
        if let duration = intOptional(payload["duration_ms"]) {
            return "耗时 \(max(1, duration / 1000)) 秒"
        }
        return "任务完成"
    }

    private func appendActivity(_ item: ActivityItem, to items: inout [ActivityItem]) {
        let detail = item.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !detail.isEmpty || ["完成", "修改文件"].contains(item.title) else {
            return
        }
        if items.suffix(6).contains(where: { existing in
            existing.title == item.title &&
            existing.detail.trimmingCharacters(in: .whitespacesAndNewlines) == detail
        }) {
            return
        }
        items.append(item)
    }

    private func expandedURL(_ path: String) -> URL {
        let expanded = NSString(string: path).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return URL(fileURLWithPath: expanded)
        }
        return homeURL.appendingPathComponent(expanded)
    }

    private func sanitized(_ value: String, limit: Int) -> String? {
        let sanitized = DisplayTextSanitizer.sanitize(value)
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitized.isEmpty else { return nil }
        return String(sanitized.prefix(limit))
    }

    private func string(_ value: Any?) -> String? {
        switch value {
        case let value as String:
            value.isEmpty ? nil : value
        case let value as NSNumber:
            value.stringValue
        case let value as JSONValue:
            value.stringValue
        default:
            nil
        }
    }

    private func int(_ value: Any?) -> Int {
        intOptional(value) ?? 0
    }

    private func intOptional(_ value: Any?) -> Int? {
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
            return Int(value)
        default:
            return nil
        }
    }

    private func optionalInt(_ value: Any?) -> Int? {
        let parsed = int(value)
        return parsed == 0 ? nil : parsed
    }

    private func double(_ value: Any?) -> Double? {
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

    private func resetDate(_ value: Any?) -> Date? {
        let seconds = int(value)
        guard seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    private func parseDate(_ value: Any?) -> Date? {
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

    private final class ISO8601Parser {
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
}
