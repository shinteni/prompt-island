import Foundation

package enum AppPaths {
    package static var home: URL {
        home(environment: ProcessInfo.processInfo.environment)
    }

    package static func home(environment: [String: String]) -> URL {
        if let override = environment["VIBELSLAND_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true).standardizedFileURL
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    package static var appHome: URL {
        home.appendingPathComponent(".vibelsland-free", isDirectory: true)
    }

    package static var binDirectory: URL {
        appHome.appendingPathComponent("bin", isDirectory: true)
    }

    package static var runDirectory: URL {
        appHome.appendingPathComponent("run", isDirectory: true)
    }

    package static var socketURL: URL {
        runDirectory.appendingPathComponent("vibelsland.sock")
    }

    package static var bridgeTokenURL: URL {
        runDirectory.appendingPathComponent("bridge-token")
    }

    package static var bridgeURL: URL {
        binDirectory.appendingPathComponent("vibelsland-bridge")
    }

    package static var applicationSupportDirectory: URL {
        home.appendingPathComponent("Library/Application Support/VibelslandFree", isDirectory: true)
    }

    package static var configURL: URL {
        applicationSupportDirectory.appendingPathComponent("config.json")
    }

    package static var logsDirectory: URL {
        home.appendingPathComponent("Library/Logs/VibelslandFree", isDirectory: true)
    }

    package static var logURL: URL {
        logsDirectory.appendingPathComponent("app.log")
    }

    package static var claudeSettingsURL: URL {
        home.appendingPathComponent(".claude/settings.json")
    }

    package static var codexHooksURL: URL {
        home.appendingPathComponent(".codex/hooks.json")
    }

    package static var codexConfigURL: URL {
        home.appendingPathComponent(".codex/config.toml")
    }

    package static var codexStateURL: URL {
        codexStateURL(environment: ProcessInfo.processInfo.environment)
    }

    package static func codexStateURL(
        environment: [String: String],
        fileManager: FileManager = .default
    ) -> URL {
        let homeURL = home(environment: environment)
        let currentURL = homeURL.appendingPathComponent(".codex/sqlite/state_5.sqlite")
        if fileManager.fileExists(atPath: currentURL.path) {
            return currentURL
        }
        return homeURL.appendingPathComponent(".codex/state_5.sqlite")
    }

    package static func ensureRuntimeDirectories() throws {
        for directory in [appHome, binDirectory, runDirectory, applicationSupportDirectory, logsDirectory] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        for directory in [appHome, binDirectory, runDirectory] {
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        }
    }
}
