import Foundation

package struct ClaudeTurnUsage: Equatable {
    package var inputTokens: Int
    package var outputTokens: Int
    package var cacheWriteTokens: Int
    package var cacheReadTokens: Int
    package var model: String?

    package init(
        inputTokens: Int,
        outputTokens: Int,
        cacheWriteTokens: Int,
        cacheReadTokens: Int,
        model: String?
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheWriteTokens = cacheWriteTokens
        self.cacheReadTokens = cacheReadTokens
        self.model = model
    }

    package var totalTokens: Int {
        inputTokens + outputTokens + cacheWriteTokens + cacheReadTokens
    }
}

package struct ClaudeUsageAggregate: Equatable {
    package var inputTokens = 0
    package var outputTokens = 0
    package var cacheWriteTokens = 0
    package var cacheReadTokens = 0
    package var turns = 0
    package var lastTurnTokens = 0
    package var model: String?

    package init() {}

    package mutating func add(_ turn: ClaudeTurnUsage) {
        inputTokens += turn.inputTokens
        outputTokens += turn.outputTokens
        cacheWriteTokens += turn.cacheWriteTokens
        cacheReadTokens += turn.cacheReadTokens
        turns += 1
        lastTurnTokens = turn.totalTokens
        if let model = turn.model, !model.isEmpty {
            self.model = model
        }
    }

    package var totalTokens: Int {
        inputTokens + outputTokens + cacheWriteTokens + cacheReadTokens
    }

    package var estimatedCostUSD: Double? {
        ClaudeUsagePolicy.costUSD(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheWriteTokens: cacheWriteTokens,
            cacheReadTokens: cacheReadTokens,
            model: model
        )
    }
}

/// Claude Code transcript 的 token 用量解析与成本估算。
/// Codex 的 rollout 自带累计 token_count 事件，Claude transcript 只有每条
/// assistant 消息的 message.usage，所以这里按回合累加。
package enum ClaudeUsagePolicy {
    /// 按模型家族的 API 牌价估算（美元 / 百万 token）。订阅计划下没有边际
    /// 成本，这个数字只用于展示「等价 API 成本」的量级，所以精确到家族即可；
    /// 未识别的模型不给估算。缓存写按输入价 1.25 倍、缓存读按 0.1 倍计。
    package static func rates(forModel model: String?) -> (input: Double, output: Double)? {
        guard let model = model?.lowercased() else { return nil }
        if model.contains("opus") {
            return (15, 75)
        }
        if model.contains("sonnet") {
            return (3, 15)
        }
        if model.contains("haiku") {
            return (1, 5)
        }
        return nil
    }

    package static func costUSD(
        inputTokens: Int,
        outputTokens: Int,
        cacheWriteTokens: Int,
        cacheReadTokens: Int,
        model: String?
    ) -> Double? {
        guard let rates = rates(forModel: model) else { return nil }
        let perToken = 1.0 / 1_000_000
        let input = Double(inputTokens) * rates.input * perToken
        let output = Double(outputTokens) * rates.output * perToken
        let cacheWrite = Double(cacheWriteTokens) * rates.input * 1.25 * perToken
        let cacheRead = Double(cacheReadTokens) * rates.input * 0.1 * perToken
        return input + output + cacheWrite + cacheRead
    }

    /// 从 transcript 的一行 JSON 对象里解析一次 assistant 回合的用量。
    package static func parseTurn(from object: [String: Any]) -> ClaudeTurnUsage? {
        guard object["type"] as? String == "assistant",
              let message = object["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any] else {
            return nil
        }
        let turn = ClaudeTurnUsage(
            inputTokens: intValue(usage["input_tokens"]),
            outputTokens: intValue(usage["output_tokens"]),
            cacheWriteTokens: intValue(usage["cache_creation_input_tokens"]),
            cacheReadTokens: intValue(usage["cache_read_input_tokens"]),
            model: message["model"] as? String
        )
        return turn.totalTokens > 0 ? turn : nil
    }

    package static func usageSnapshot(from aggregate: ClaudeUsageAggregate) -> UsageSnapshot? {
        guard aggregate.turns > 0 else { return nil }
        return UsageSnapshot(
            lastTokens: aggregate.lastTurnTokens,
            totalTokens: aggregate.totalTokens,
            contextWindow: 0,
            estimatedCostUSD: aggregate.estimatedCostUSD
        )
    }

    private static func intValue(_ value: Any?) -> Int {
        switch value {
        case let value as Int:
            return value
        case let value as NSNumber:
            return value.intValue
        default:
            return 0
        }
    }
}
