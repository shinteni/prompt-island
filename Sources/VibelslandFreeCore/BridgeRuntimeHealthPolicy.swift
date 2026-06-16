import Foundation

package struct BridgeSocketInspection: Equatable {
    package var exists: Bool
    package var isSocket: Bool
    package var ownerMatchesCurrentUser: Bool
    package var permissions: Int?

    package init(
        exists: Bool,
        isSocket: Bool,
        ownerMatchesCurrentUser: Bool,
        permissions: Int?
    ) {
        self.exists = exists
        self.isSocket = isSocket
        self.ownerMatchesCurrentUser = ownerMatchesCurrentUser
        self.permissions = permissions
    }

    package static let missing = BridgeSocketInspection(
        exists: false,
        isSocket: false,
        ownerMatchesCurrentUser: false,
        permissions: nil
    )
}

package enum BridgeRuntimeHealthPolicy {
    package static func item(
        bridgeEnabled: Bool,
        bridgeExecutable: Bool,
        socket: BridgeSocketInspection,
        language: AppLanguage = .chinese
    ) -> HealthCheckItem {
        HealthCheckItem(
            id: "bridge",
            name: "Bridge",
            status: status(
                bridgeEnabled: bridgeEnabled,
                bridgeExecutable: bridgeExecutable,
                socket: socket
            ),
            detail: detail(
                bridgeEnabled: bridgeEnabled,
                bridgeExecutable: bridgeExecutable,
                socket: socket,
                language: language
            ),
            suggestedAction: bridgeEnabled
                ? repairHooksText(language)
                : enableSourceText(language)
        )
    }

    package static func status(
        bridgeEnabled: Bool,
        bridgeExecutable: Bool,
        socket: BridgeSocketInspection
    ) -> HealthCheckStatus {
        guard bridgeEnabled else { return .disabled }
        return bridgeExecutable && socketIsReady(socket) ? .normal : .needsAction
    }

    package static func detail(
        bridgeEnabled: Bool,
        bridgeExecutable: Bool,
        socket: BridgeSocketInspection,
        language: AppLanguage = .chinese
    ) -> String {
        guard bridgeEnabled else {
            return disabledDetail(language)
        }
        guard bridgeExecutable else {
            return socket.exists ? bridgeNotExecutableText(language) : bridgeIncompleteText(language)
        }
        guard socket.exists else {
            return socketMissingText(language)
        }
        guard socket.isSocket else {
            return socketNotUnixText(language)
        }
        guard socket.ownerMatchesCurrentUser else {
            return socketWrongOwnerText(language)
        }
        guard socket.permissions == 0o600 else {
            let value = socket.permissions.map { String($0, radix: 8) } ?? unknownText(language)
            return socketWrongPermissionText(value, language: language)
        }
        return readyText(language)
    }

    private static func socketIsReady(_ socket: BridgeSocketInspection) -> Bool {
        socket.exists &&
            socket.isSocket &&
            socket.ownerMatchesCurrentUser &&
            socket.permissions == 0o600
    }

    private static func disabledDetail(_ language: AppLanguage) -> String {
        switch language {
        case .english: "Hook sources are off. Bridge is not needed right now."
        case .japanese: "Hook 受信元がオフです。現在 Bridge は不要です。"
        case .chinese: "Hook 来源已关闭，Bridge 暂不需要"
        }
    }

    private static func bridgeNotExecutableText(_ language: AppLanguage) -> String {
        switch language {
        case .english: "Bridge script is not executable"
        case .japanese: "Bridge スクリプトが実行可能ではありません"
        case .chinese: "桥接脚本不可执行"
        }
    }

    private static func bridgeIncompleteText(_ language: AppLanguage) -> String {
        switch language {
        case .english: "Bridge script and socket are incomplete"
        case .japanese: "Bridge スクリプトと socket が不完全です"
        case .chinese: "桥接脚本和 socket 不完整"
        }
    }

    private static func socketMissingText(_ language: AppLanguage) -> String {
        switch language {
        case .english: "Bridge socket has not been created"
        case .japanese: "Bridge socket が作成されていません"
        case .chinese: "Bridge socket 未创建"
        }
    }

    private static func socketNotUnixText(_ language: AppLanguage) -> String {
        switch language {
        case .english: "Bridge socket path is not a Unix socket"
        case .japanese: "Bridge socket のパスが Unix socket ではありません"
        case .chinese: "Bridge socket 路径不是 Unix socket"
        }
    }

    private static func socketWrongOwnerText(_ language: AppLanguage) -> String {
        switch language {
        case .english: "Bridge socket is not owned by the current user"
        case .japanese: "Bridge socket の所有者が現在のユーザーではありません"
        case .chinese: "Bridge socket 属主不是当前用户"
        }
    }

    private static func socketWrongPermissionText(_ value: String, language: AppLanguage) -> String {
        switch language {
        case .english: "Bridge socket permissions should be 600, current \(value)"
        case .japanese: "Bridge socket の権限は 600 の必要があります。現在は \(value)"
        case .chinese: "Bridge socket 权限应为 600，当前 \(value)"
        }
    }

    private static func readyText(_ language: AppLanguage) -> String {
        switch language {
        case .english: "Local bridge script and socket are healthy"
        case .japanese: "ローカル Bridge スクリプトと socket は正常です"
        case .chinese: "本机桥接脚本和 socket 正常"
        }
    }

    private static func repairHooksText(_ language: AppLanguage) -> String {
        switch language {
        case .english: "Install or repair hooks"
        case .japanese: "Hooks をインストールまたは修復"
        case .chinese: "安装/修复 Hooks"
        }
    }

    private static func enableSourceText(_ language: AppLanguage) -> String {
        switch language {
        case .english: "Enable Claude or Codex CLI sources"
        case .japanese: "Claude または Codex CLI 受信元を有効化"
        case .chinese: "启用 Claude 或 Codex CLI 来源"
        }
    }

    private static func unknownText(_ language: AppLanguage) -> String {
        switch language {
        case .english: "unknown"
        case .japanese: "不明"
        case .chinese: "未知"
        }
    }
}
