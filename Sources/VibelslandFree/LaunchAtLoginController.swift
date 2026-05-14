import Foundation
import VibelslandFreeCore
import ServiceManagement

enum LaunchAtLoginController {
    static var isEnabled: Bool {
        guard #available(macOS 13.0, *) else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Result<Bool, Error> {
        guard #available(macOS 13.0, *) else { return .success(false) }
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
            return .success(SMAppService.mainApp.status == .enabled)
        } catch {
            AppLogger.shared.error("launch-at-login.failed", detail: error.localizedDescription)
            return .failure(error)
        }
    }
}
