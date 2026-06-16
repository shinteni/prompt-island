import Foundation
import VibelslandFreeCore

enum AppText {
    static func pick(
        _ language: AppLanguage,
        english: String,
        japanese: String,
        chinese: String
    ) -> String {
        switch language {
        case .english: english
        case .japanese: japanese
        case .chinese: chinese
        }
    }

    static func locale(for language: AppLanguage) -> Locale {
        Locale(identifier: language.localeIdentifier)
    }

    static func approvalWaitText(seconds: Int, language: AppLanguage) -> String {
        if seconds < 3600 {
            return count(max(1, seconds / 60), singular: minuteSingular(language), plural: minutePlural(language))
        }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let hourText = count(hours, singular: hourSingular(language), plural: hourPlural(language))
        guard minutes > 0 else { return hourText }
        let minuteText = count(minutes, singular: minuteSingular(language), plural: minutePlural(language))
        switch language {
        case .english:
            return "\(hourText) \(minuteText)"
        case .japanese, .chinese:
            return "\(hourText) \(minuteText)"
        }
    }

    static func sessions(_ count: Int, language: AppLanguage) -> String {
        switch language {
        case .english:
            return count == 1 ? "1 session" : "\(count) sessions"
        case .japanese:
            return "\(count) セッション"
        case .chinese:
            return "\(count) 个会话"
        }
    }

    static func recentSessions(_ count: Int, language: AppLanguage) -> String {
        switch language {
        case .english:
            return count == 1 ? "1 recent session" : "\(count) recent sessions"
        case .japanese:
            return "\(count) 件の最近のセッション"
        case .chinese:
            return "\(count) 个最近会话"
        }
    }

    static func activeTasks(_ count: Int, language: AppLanguage) -> String {
        switch language {
        case .english:
            return count == 1 ? "1 task running" : "\(count) tasks running"
        case .japanese:
            return "\(count) 件のタスクが実行中"
        case .chinese:
            return "\(count) 个任务进行中"
        }
    }

    static func pendingApprovals(_ count: Int, language: AppLanguage) -> String {
        switch language {
        case .english:
            return count == 1 ? "1 approval pending" : "\(count) approvals pending"
        case .japanese:
            return "\(count) 件の承認待ち"
        case .chinese:
            return "\(count) 个审批等待处理"
        }
    }

    static func subagents(_ active: Int, total: Int, language: AppLanguage) -> String {
        let value = active == total ? "\(active)" : "\(active)/\(total)"
        switch language {
        case .english:
            return active == 1 && total == 1 ? "1 subagent" : "\(value) subagents"
        case .japanese:
            return "\(value) サブエージェント"
        case .chinese:
            return "\(value) 子智能体"
        }
    }

    static func runningSubagents(_ count: Int, language: AppLanguage) -> String {
        switch language {
        case .english:
            return count == 1 ? "1 subagent running" : "\(count) subagents running"
        case .japanese:
            return "\(count) 件のサブエージェントが実行中"
        case .chinese:
            return "运行 \(count) 个子智能体"
        }
    }

    static func completed(_ count: Int, language: AppLanguage) -> String {
        switch language {
        case .english:
            return "Done \(count)"
        case .japanese:
            return "完了 \(count)"
        case .chinese:
            return "完成 \(count)"
        }
    }

    private static func count(_ value: Int, singular: String, plural: String) -> String {
        value == 1 ? "\(value) \(singular)" : "\(value) \(plural)"
    }

    private static func minuteSingular(_ language: AppLanguage) -> String {
        switch language {
        case .english: "minute"
        case .japanese: "分"
        case .chinese: "分钟"
        }
    }

    private static func minutePlural(_ language: AppLanguage) -> String {
        switch language {
        case .english: "minutes"
        case .japanese: "分"
        case .chinese: "分钟"
        }
    }

    private static func hourSingular(_ language: AppLanguage) -> String {
        switch language {
        case .english: "hour"
        case .japanese: "時間"
        case .chinese: "小时"
        }
    }

    private static func hourPlural(_ language: AppLanguage) -> String {
        switch language {
        case .english: "hours"
        case .japanese: "時間"
        case .chinese: "小时"
        }
    }
}
