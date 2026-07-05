import Foundation

package enum GlobalHotKeyAction: String, Codable, CaseIterable, Identifiable {
    case toggleIsland
    case jumpToApproval
    case approveApproval
    case declineApproval

    package var id: String { rawValue }

    /// Carbon RegisterEventHotKey 使用的稳定 ID，注册与回调之间靠它对应。
    package var carbonHotKeyID: UInt32 {
        switch self {
        case .toggleIsland: 1
        case .jumpToApproval: 2
        case .approveApproval: 3
        case .declineApproval: 4
        }
    }

    /// 审批快捷键默认是无修饰键的裸键（空格/退格），只能在存在待审批时
    /// 临时注册，否则会吞掉全系统的日常输入。
    package var isApprovalScoped: Bool {
        switch self {
        case .approveApproval, .declineApproval: true
        case .toggleIsland, .jumpToApproval: false
        }
    }
}

/// 一条可自定义的快捷键绑定：Carbon 虚拟键码 + 修饰键掩码。
package struct HotKeyBinding: Codable, Equatable {
    package var keyCode: UInt32
    package var carbonModifiers: UInt32

    package init(keyCode: UInt32, carbonModifiers: UInt32 = 0) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }
}

package enum GlobalHotKeyPolicy {
    package static let controlKeyMask: UInt32 = 0x1000
    package static let optionKeyMask: UInt32 = 0x0800
    package static let shiftKeyMask: UInt32 = 0x0200
    package static let commandKeyMask: UInt32 = 0x0100

    /// 默认绑定：⌃⌥I 展开/收起、⌃⌥A 跳转审批、空格允许、退格拒绝。
    package static func defaultBinding(for action: GlobalHotKeyAction) -> HotKeyBinding {
        switch action {
        case .toggleIsland:
            HotKeyBinding(keyCode: 34, carbonModifiers: controlKeyMask | optionKeyMask) // I
        case .jumpToApproval:
            HotKeyBinding(keyCode: 0, carbonModifiers: controlKeyMask | optionKeyMask) // A
        case .approveApproval:
            HotKeyBinding(keyCode: 49) // Space
        case .declineApproval:
            HotKeyBinding(keyCode: 51) // Delete（退格）
        }
    }

    package static func binding(
        for action: GlobalHotKeyAction,
        overrides: [String: HotKeyBinding]
    ) -> HotKeyBinding {
        overrides[action.rawValue] ?? defaultBinding(for: action)
    }

    /// 需要注册的动作：展开/跳转常驻；审批允许/拒绝只在存在待审批时注册，
    /// 处理完立即释放按键（裸键不能常驻占用）。
    package static func actions(enabled: Bool, hasPendingApproval: Bool) -> [GlobalHotKeyAction] {
        guard enabled else { return [] }
        return GlobalHotKeyAction.allCases.filter { action in
            action.isApprovalScoped ? hasPendingApproval : true
        }
    }

    package static func action(forHotKeyID id: UInt32) -> GlobalHotKeyAction? {
        GlobalHotKeyAction.allCases.first { $0.carbonHotKeyID == id }
    }

    /// 与其它动作的绑定冲突检测：录制新键时用。
    package static func conflictingAction(
        binding: HotKeyBinding,
        excluding action: GlobalHotKeyAction,
        overrides: [String: HotKeyBinding]
    ) -> GlobalHotKeyAction? {
        GlobalHotKeyAction.allCases.first { other in
            other != action && Self.binding(for: other, overrides: overrides) == binding
        }
    }

    /// 跳转目标：审批队列里等待最久的会话（与浮岛主审批一致）。
    package static func approvalTargetSessionID(in sessions: [AgentSession]) -> AgentSession.ID? {
        ApprovalQueuePolicy.primarySession(in: sessions)?.id
    }

    /// 绑定的展示文本，如 "⌃⌥I"、"Space"、"⌫"。
    package static func displayText(for binding: HotKeyBinding) -> String {
        var parts = ""
        if binding.carbonModifiers & controlKeyMask != 0 { parts += "⌃" }
        if binding.carbonModifiers & optionKeyMask != 0 { parts += "⌥" }
        if binding.carbonModifiers & shiftKeyMask != 0 { parts += "⇧" }
        if binding.carbonModifiers & commandKeyMask != 0 { parts += "⌘" }
        return parts + keyName(for: binding.keyCode)
    }

    /// Carbon ANSI 虚拟键码 → 展示名。键码与物理键位绑定，跨布局稳定。
    package static func keyName(for keyCode: UInt32) -> String {
        if let special = specialKeyNames[keyCode] {
            return special
        }
        if let ansi = ansiKeyNames[keyCode] {
            return ansi
        }
        return "键码 \(keyCode)"
    }

    private static let specialKeyNames: [UInt32: String] = [
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 76: "⌤", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
    ]

    private static let ansiKeyNames: [UInt32: String] = [
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H",
        34: "I", 38: "J", 40: "K", 37: "L", 46: "M", 45: "N", 31: "O",
        35: "P", 12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V",
        13: "W", 7: "X", 16: "Y", 6: "Z",
        29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6",
        26: "7", 28: "8", 25: "9",
        27: "-", 24: "=", 33: "[", 30: "]", 41: ";", 39: "'", 43: ",",
        47: ".", 44: "/", 42: "\\", 50: "`",
    ]
}
