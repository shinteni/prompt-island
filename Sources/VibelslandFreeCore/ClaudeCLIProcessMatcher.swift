import Foundation

package enum ClaudeCLIProcessMatcher {
    private static let wrapperExecutables: Set<String> = [
        "node",
        "npm",
        "npx",
        "pnpm",
        "pnpx",
        "bun",
        "bunx",
        "yarn"
    ]

    package static func isClaudeCLIProcess(_ arguments: String) -> Bool {
        let tokens = shellLikeTokens(arguments)
        guard let executable = tokens.first else {
            return false
        }
        let executableName = basename(executable)
        let lowercasedArguments = arguments.lowercased()

        if executableName == "claude" ||
            lowercasedArguments.contains("/claude.app/contents/macos/claude") {
            return true
        }

        guard wrapperExecutables.contains(executableName) else {
            return false
        }

        return tokens.dropFirst().contains { token in
            let lowercased = token.lowercased()
            return basename(lowercased) == "claude" ||
                lowercased == "@anthropic-ai/claude-code" ||
                lowercased.contains("/@anthropic-ai/claude-code/") ||
                lowercased.contains("/claude-code/") ||
                lowercased.hasSuffix("/claude")
        }
    }

    private static func shellLikeTokens(_ arguments: String) -> [String] {
        arguments
            .split(whereSeparator: \.isWhitespace)
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
            .filter { !$0.isEmpty }
    }

    private static func basename(_ path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent.lowercased()
    }
}
