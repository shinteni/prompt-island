import Foundation

package enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case english
    case japanese
    case chinese

    package var id: String { rawValue }

    package var displayName: String {
        switch self {
        case .english: "English"
        case .japanese: "日本語"
        case .chinese: "中文"
        }
    }

    package var localeIdentifier: String {
        switch self {
        case .english: "en"
        case .japanese: "ja"
        case .chinese: "zh-Hans"
        }
    }
}

package extension IslandPosition {
    func title(language: AppLanguage) -> String {
        switch language {
        case .english:
            switch self {
            case .topCenter: "Top center"
            case .topLeft: "Top left"
            case .topRight: "Top right"
            }
        case .japanese:
            switch self {
            case .topCenter: "上部中央"
            case .topLeft: "上部左"
            case .topRight: "上部右"
            }
        case .chinese:
            title
        }
    }
}

package extension SoundTheme {
    func title(language: AppLanguage) -> String {
        switch language {
        case .english:
            switch self {
            case .soft: "Soft"
            case .glass: "Glass"
            case .system: "System"
            case .eightBit: "8-bit"
            }
        case .japanese:
            switch self {
            case .soft: "ソフト"
            case .glass: "グラス"
            case .system: "システム"
            case .eightBit: "8-bit"
            }
        case .chinese:
            title
        }
    }
}

package extension SessionStatus {
    func displayName(language: AppLanguage) -> String {
        switch language {
        case .english:
            switch self {
            case .idle: "Idle"
            case .thinking: "Thinking"
            case .runningTool: "Running tool"
            case .waitingApproval: "Waiting approval"
            case .waitingQuestion: "Waiting input"
            case .done: "Done"
            case .failed: "Error"
            }
        case .japanese:
            switch self {
            case .idle: "待機中"
            case .thinking: "思考中"
            case .runningTool: "ツール実行中"
            case .waitingApproval: "承認待ち"
            case .waitingQuestion: "入力待ち"
            case .done: "完了"
            case .failed: "エラー"
            }
        case .chinese:
            displayName
        }
    }
}

package extension ApprovalDecision {
    func title(language: AppLanguage) -> String {
        switch language {
        case .english:
            switch self {
            case .accept: "Allow once"
            case .acceptForSession: "Allow this session"
            case .decline: "Deny"
            case .cancel: "Cancel task"
            }
        case .japanese:
            switch self {
            case .accept: "一度だけ許可"
            case .acceptForSession: "このセッションで許可"
            case .decline: "拒否"
            case .cancel: "タスクをキャンセル"
            }
        case .chinese:
            title
        }
    }
}

package extension ApprovalResolutionState {
    func title(language: AppLanguage) -> String {
        switch language {
        case .english:
            switch self {
            case .pending: "Waiting approval"
            case .resolving: "Returning approval"
            case .accepted: "Allowed"
            case .declined: "Denied"
            case .cancelled: "Cancelled"
            case .timedOut: "Approval timed out"
            case .sendFailed: "Send failed"
            case .disconnected: "Disconnected"
            }
        case .japanese:
            switch self {
            case .pending: "承認待ち"
            case .resolving: "承認を返送中"
            case .accepted: "許可済み"
            case .declined: "拒否済み"
            case .cancelled: "キャンセル済み"
            case .timedOut: "承認がタイムアウト"
            case .sendFailed: "返送失敗"
            case .disconnected: "接続切断"
            }
        case .chinese:
            title
        }
    }
}

package extension DisplayConfidence {
    func title(language: AppLanguage) -> String {
        switch language {
        case .english:
            switch self {
            case .realtime: "Live"
            case .event: "Hook event"
            case .transcript: "Transcript"
            case .inferred: "Inferred"
            }
        case .japanese:
            switch self {
            case .realtime: "リアルタイム"
            case .event: "Hook イベント"
            case .transcript: "転記推定"
            case .inferred: "時間推定"
            }
        case .chinese:
            title
        }
    }
}

package extension HealthCheckStatus {
    func title(language: AppLanguage) -> String {
        switch language {
        case .english:
            switch self {
            case .normal: "OK"
            case .needsAction: "Needs action"
            case .disabled: "Disabled"
            }
        case .japanese:
            switch self {
            case .normal: "正常"
            case .needsAction: "対応が必要"
            case .disabled: "無効"
            }
        case .chinese:
            title
        }
    }
}
