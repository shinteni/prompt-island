import Foundation
import SwiftUI

package enum IslandPosition: String, Codable, CaseIterable, Identifiable {
    case topCenter
    case topLeft
    case topRight

    package var id: String { rawValue }

    package var title: String {
        switch self {
        case .topCenter: "顶部居中"
        case .topLeft: "顶部靠左"
        case .topRight: "顶部靠右"
        }
    }
}

package enum SoundTheme: String, Codable, CaseIterable, Identifiable {
    case soft
    case glass
    case system
    case eightBit

    package var id: String { rawValue }

    package var title: String {
        switch self {
        case .soft: "柔和"
        case .glass: "玻璃"
        case .system: "系统"
        case .eightBit: "8bit"
        }
    }
}

package struct AppConfiguration: Codable, Equatable {
    package var enableClaude: Bool
    package var enableCodexCLI: Bool
    package var enableCodexDesktop: Bool
    package var enableSounds: Bool
    package var soundTheme: SoundTheme
    package var doNotDisturb: Bool
    package var launchAtLogin: Bool
    package var islandPosition: IslandPosition
    package var language: AppLanguage
    package var approvalTimeoutSeconds: TimeInterval
    package var maxVisibleSessions: Int
    package var enableGlobalHotKeys: Bool
    package var enableApprovalNotifications: Bool
    package var autoCheckUpdates: Bool
    /// 全局快捷键的自定义绑定，键为 GlobalHotKeyAction.rawValue；缺省用策略默认值。
    package var hotKeyBindings: [String: HotKeyBinding]

    package static let `default` = AppConfiguration(
        enableClaude: true,
        enableCodexCLI: true,
        enableCodexDesktop: true,
        enableSounds: true,
        soundTheme: .soft,
        doNotDisturb: false,
        launchAtLogin: false,
        islandPosition: .topCenter,
        language: .english,
        approvalTimeoutSeconds: 7_200,
        maxVisibleSessions: 5,
        enableGlobalHotKeys: false,
        enableApprovalNotifications: false,
        autoCheckUpdates: false,
        hotKeyBindings: [:]
    )

    package enum CodingKeys: String, CodingKey {
        case enableClaude
        case enableCodexCLI
        case enableCodexDesktop
        case enableSounds
        case soundTheme
        case doNotDisturb
        case launchAtLogin
        case islandPosition
        case language
        case approvalTimeoutSeconds
        case maxVisibleSessions
        case enableGlobalHotKeys
        case enableApprovalNotifications
        case autoCheckUpdates
        case hotKeyBindings
    }

    package init(
        enableClaude: Bool,
        enableCodexCLI: Bool,
        enableCodexDesktop: Bool,
        enableSounds: Bool,
        soundTheme: SoundTheme,
        doNotDisturb: Bool,
        launchAtLogin: Bool,
        islandPosition: IslandPosition,
        language: AppLanguage,
        approvalTimeoutSeconds: TimeInterval,
        maxVisibleSessions: Int,
        enableGlobalHotKeys: Bool = false,
        enableApprovalNotifications: Bool = false,
        autoCheckUpdates: Bool = false,
        hotKeyBindings: [String: HotKeyBinding] = [:]
    ) {
        self.enableClaude = enableClaude
        self.enableCodexCLI = enableCodexCLI
        self.enableCodexDesktop = enableCodexDesktop
        self.enableSounds = enableSounds
        self.soundTheme = soundTheme
        self.doNotDisturb = doNotDisturb
        self.launchAtLogin = launchAtLogin
        self.islandPosition = islandPosition
        self.language = language
        self.approvalTimeoutSeconds = approvalTimeoutSeconds
        self.maxVisibleSessions = maxVisibleSessions
        self.enableGlobalHotKeys = enableGlobalHotKeys
        self.enableApprovalNotifications = enableApprovalNotifications
        self.autoCheckUpdates = autoCheckUpdates
        self.hotKeyBindings = hotKeyBindings
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enableClaude = try container.decodeIfPresent(Bool.self, forKey: .enableClaude) ?? Self.default.enableClaude
        enableCodexCLI = try container.decodeIfPresent(Bool.self, forKey: .enableCodexCLI) ?? Self.default.enableCodexCLI
        enableCodexDesktop = try container.decodeIfPresent(Bool.self, forKey: .enableCodexDesktop) ?? Self.default.enableCodexDesktop
        enableSounds = try container.decodeIfPresent(Bool.self, forKey: .enableSounds) ?? Self.default.enableSounds
        soundTheme = try container.decodeIfPresent(SoundTheme.self, forKey: .soundTheme) ?? Self.default.soundTheme
        doNotDisturb = try container.decodeIfPresent(Bool.self, forKey: .doNotDisturb) ?? Self.default.doNotDisturb
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? Self.default.launchAtLogin
        islandPosition = try container.decodeIfPresent(IslandPosition.self, forKey: .islandPosition) ?? Self.default.islandPosition
        language = try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? Self.default.language
        approvalTimeoutSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .approvalTimeoutSeconds) ?? Self.default.approvalTimeoutSeconds
        maxVisibleSessions = try container.decodeIfPresent(Int.self, forKey: .maxVisibleSessions) ?? Self.default.maxVisibleSessions
        enableGlobalHotKeys = try container.decodeIfPresent(Bool.self, forKey: .enableGlobalHotKeys) ?? Self.default.enableGlobalHotKeys
        enableApprovalNotifications = try container.decodeIfPresent(Bool.self, forKey: .enableApprovalNotifications) ?? Self.default.enableApprovalNotifications
        autoCheckUpdates = try container.decodeIfPresent(Bool.self, forKey: .autoCheckUpdates) ?? Self.default.autoCheckUpdates
        hotKeyBindings = try container.decodeIfPresent([String: HotKeyBinding].self, forKey: .hotKeyBindings) ?? Self.default.hotKeyBindings
    }
}

@MainActor
package final class AppConfigurationStore: ObservableObject {
    @Published package var config: AppConfiguration {
        didSet {
            guard config != oldValue else { return }
            save()
        }
    }

    private let url: URL
    private let logger: AppLogger

    package init(url: URL = AppPaths.configURL, logger: AppLogger = .shared) {
        self.url = url
        self.logger = logger
        if let data = try? Data(contentsOf: url),
           let value = try? JSONDecoder().decode(AppConfiguration.self, from: data) {
            config = Self.normalized(value)
        } else {
            config = .default
        }
    }

    package func save() {
        do {
            try AppPaths.ensureRuntimeDirectories()
            let data = try JSONEncoder.pretty.encode(config)
            try data.write(to: url, options: [.atomic])
        } catch {
            logger.error("config.save.failed", detail: error.localizedDescription)
        }
    }

    private static func normalized(_ value: AppConfiguration) -> AppConfiguration {
        var config = value
        if config.approvalTimeoutSeconds <= 30 {
            config.approvalTimeoutSeconds = AppConfiguration.default.approvalTimeoutSeconds
        } else {
            config.approvalTimeoutSeconds = min(max(config.approvalTimeoutSeconds, 60), 7_200)
        }
        config.maxVisibleSessions = DashboardSessionPolicy.configuredVisibleSessionLimit(config.maxVisibleSessions)
        return config
    }
}

package extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
