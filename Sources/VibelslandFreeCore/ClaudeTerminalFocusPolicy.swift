import Foundation

package struct ProcessSnapshot: Equatable {
    package var pid: Int
    package var ppid: Int
    package var arguments: String

    package init(pid: Int, ppid: Int, arguments: String) {
        self.pid = pid
        self.ppid = ppid
        self.arguments = arguments
    }
}

package enum ClaudeTerminalFocusPolicy {
    package static let terminalApplicationNamesByBundleID: [String: String] = [
        "com.apple.Terminal": "Terminal",
        "com.googlecode.iterm2": "iTerm",
        "dev.warp.Warp-Stable": "Warp",
        "dev.warp.Warp": "Warp",
        "com.mitchellh.ghostty": "Ghostty",
        "com.github.wez.wezterm": "WezTerm",
        "org.alacritty": "Alacritty"
    ]

    package static func terminalBundleIdentifier(
        forSessionID sessionID: String?,
        processSnapshots: [ProcessSnapshot],
        runningAppsByPID: [Int: String]
    ) -> String? {
        let parentByPID = Dictionary(uniqueKeysWithValues: processSnapshots.map { ($0.pid, $0.ppid) })
        let candidates = processSnapshots
            .filter { ClaudeCLIProcessMatcher.isClaudeCLIProcess($0.arguments) }
            .sorted { left, right in
                claudeProcessScore(left, sessionID: sessionID) > claudeProcessScore(right, sessionID: sessionID)
            }

        for candidate in candidates {
            if let bundleID = terminalBundleIdentifier(
                forProcessID: candidate.pid,
                parentByPID: parentByPID,
                runningAppsByPID: runningAppsByPID
            ) {
                return bundleID
            }
        }
        return nil
    }

    private static func terminalBundleIdentifier(
        forProcessID processID: Int,
        parentByPID: [Int: Int],
        runningAppsByPID: [Int: String]
    ) -> String? {
        var current = processID
        var visited = Set<Int>()
        while let parent = parentByPID[current], visited.insert(parent).inserted {
            if let bundleID = runningAppsByPID[parent] {
                return terminalApplicationNamesByBundleID[bundleID] == nil ? nil : bundleID
            }
            current = parent
        }
        return nil
    }

    private static func claudeProcessScore(_ process: ProcessSnapshot, sessionID: String?) -> Int {
        var score = 0
        if let sessionID, process.arguments.contains(sessionID) {
            score += 100
        }
        if process.arguments == "claude" || process.arguments.hasPrefix("claude ") {
            score += 10
        }
        return score
    }
}
