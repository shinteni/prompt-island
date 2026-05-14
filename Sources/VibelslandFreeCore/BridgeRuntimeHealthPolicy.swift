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
        socket: BridgeSocketInspection
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
                socket: socket
            ),
            suggestedAction: bridgeEnabled ? "安装/修复 Hooks" : "启用 Claude 或 Codex CLI 来源"
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
        socket: BridgeSocketInspection
    ) -> String {
        guard bridgeEnabled else {
            return "Hook 来源已关闭，Bridge 暂不需要"
        }
        guard bridgeExecutable else {
            return socket.exists ? "桥接脚本不可执行" : "桥接脚本和 socket 不完整"
        }
        guard socket.exists else {
            return "Bridge socket 未创建"
        }
        guard socket.isSocket else {
            return "Bridge socket 路径不是 Unix socket"
        }
        guard socket.ownerMatchesCurrentUser else {
            return "Bridge socket 属主不是当前用户"
        }
        guard socket.permissions == 0o600 else {
            let value = socket.permissions.map { String($0, radix: 8) } ?? "未知"
            return "Bridge socket 权限应为 600，当前 \(value)"
        }
        return "本机桥接脚本和 socket 正常"
    }

    private static func socketIsReady(_ socket: BridgeSocketInspection) -> Bool {
        socket.exists &&
            socket.isSocket &&
            socket.ownerMatchesCurrentUser &&
            socket.permissions == 0o600
    }
}
