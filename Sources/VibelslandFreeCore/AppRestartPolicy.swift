import Foundation

package struct AppRestartCommand: Equatable {
    package var executablePath: String
    package var arguments: [String]

    package init(executablePath: String, arguments: [String]) {
        self.executablePath = executablePath
        self.arguments = arguments
    }
}

package enum AppRestartPolicy {
    package static let executablePath = "/bin/sh"
    private static let reopenScript = "source_pid=\"$1\"; shift; if [ -n \"$source_pid\" ]; then i=0; while kill -0 \"$source_pid\" 2>/dev/null && [ \"$i\" -lt 40 ]; do sleep 0.1; i=$((i + 1)); done; else sleep 0.35; fi; exec /usr/bin/open \"$@\""
    private static let preservedEnvironmentKeys = [
        "VIBELSLAND_HOME",
        "VIBELSLAND_ENABLE_VERIFICATION_ACTIONS",
        "VIBELSLAND_APPROVAL_TIMEOUT_SECONDS",
        "VIBELSLAND_CODEX_EXECUTABLE",
        "VIBELSLAND_CODEX_IPC_SOCKET"
    ]

    package static func command(
        bundlePath: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        currentProcessID: Int32 = ProcessInfo.processInfo.processIdentifier
    ) -> AppRestartCommand? {
        let trimmedPath = bundlePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            return nil
        }
        let environmentArguments = preservedEnvironmentKeys.flatMap { key -> [String] in
            guard let value = environment[key],
                  !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return []
            }
            return ["--env", "\(key)=\(value)"]
        }
        return AppRestartCommand(
            executablePath: executablePath,
            arguments: [
                "-c",
                reopenScript,
                "vibelsland-restart",
                "\(currentProcessID)"
            ] + environmentArguments + [
                "-n",
                trimmedPath
            ]
        )
    }
}
