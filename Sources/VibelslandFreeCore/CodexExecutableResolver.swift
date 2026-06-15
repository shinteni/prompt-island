import Foundation

package enum CodexExecutableResolver {
    package static func executablePath(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> String? {
        if let override = environment["VIBELSLAND_CODEX_EXECUTABLE"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty,
           fileManager.isExecutableFile(atPath: override) {
            return override
        }

        return candidatePaths(environment: environment).first {
            fileManager.isExecutableFile(atPath: $0)
        }
    }

    package static func processEnvironment(
        forExecutablePath executablePath: String,
        baseEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> [String: String] {
        var environment = baseEnvironment
        var pathEntries: [String] = []
        var seen = Set<String>()

        func appendPath(_ path: String?) {
            guard let path = path?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !path.isEmpty,
                  seen.insert(path).inserted else {
                return
            }
            pathEntries.append(path)
        }

        let executableURL = URL(fileURLWithPath: executablePath)
        let executableDirectory = executableURL.deletingLastPathComponent().path
        appendPath(executableDirectory)

        if let destination = try? fileManager.destinationOfSymbolicLink(atPath: executablePath) {
            let resolvedPath = destination.hasPrefix("/")
                ? destination
                : URL(fileURLWithPath: executableDirectory).appendingPathComponent(destination).standardizedFileURL.path
            appendPath(URL(fileURLWithPath: resolvedPath).deletingLastPathComponent().path)
        }

        let homePath = homePath(environment: baseEnvironment)
        appendPath(homePath.map { URL(fileURLWithPath: $0).appendingPathComponent(".local/bin").path })
        appendPath(homePath.map { URL(fileURLWithPath: $0).appendingPathComponent(".codex/packages/standalone/current/bin").path })
        appendPath("/Applications/Codex.app/Contents/Resources")
        appendPath("/usr/local/bin")
        appendPath("/opt/homebrew/bin")
        appendPath("/usr/bin")
        appendPath("/bin")
        appendPath("/usr/sbin")
        appendPath("/sbin")

        if let existingPath = baseEnvironment["PATH"] {
            for entry in existingPath.split(separator: ":") {
                appendPath(String(entry))
            }
        }

        environment["PATH"] = pathEntries.joined(separator: ":")
        return environment
    }

    package static func candidatePaths(environment: [String: String] = ProcessInfo.processInfo.environment) -> [String] {
        let homePath = homePath(environment: environment)
        var paths: [String] = []

        if let homePath {
            let homeURL = URL(fileURLWithPath: homePath, isDirectory: true)
            paths.append(homeURL.appendingPathComponent(".local/bin/codex").path)
            paths.append(homeURL.appendingPathComponent(".codex/packages/standalone/current/bin/codex").path)
        }

        paths.append(contentsOf: [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/Applications/Codex.app/Contents/Resources/codex"
        ])

        return paths
    }

    private static func homePath(environment: [String: String]) -> String? {
        if let home = environment["HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !home.isEmpty {
            return home
        }
        return FileManager.default.homeDirectoryForCurrentUser.path
    }
}
