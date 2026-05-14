import Foundation
import Security

package struct InstallReport: Equatable {
    package var bridgeInstalled: Bool = false
    package var claudeHooksInstalled: Bool = false
    package var codexHooksInstalled: Bool = false
    package var codexFeatureFlagEnabled: Bool = false
    package var codexFeatureFlagChanged: Bool = false
    package var message: String = ""
}

package enum HookConfigMerger {
    package static let bridgeMarker = ".vibelsland-free/bin/vibelsland-bridge"
    package static let claudePermissionHookTimeoutSeconds = 86_400
    package static let codexPermissionHookTimeoutSeconds = 7_200
    package static let bridgeClientTimeoutSeconds = 7_200

    package static func mergedClaudeSettings(existing: [String: Any], command: String) throws -> [String: Any] {
        var root = existing
        var hooks = try hooksDictionary(from: root)
        let permissionTimeout = claudePermissionHookTimeoutSeconds
        let events = [
            "Notification", "PermissionRequest", "PreToolUse", "PostToolUse", "PreCompact",
            "SessionStart", "SessionEnd", "Stop", "SubagentStart", "SubagentStop", "UserPromptSubmit"
        ]

        for event in events {
            var entries = try hookEntries(for: event, in: hooks)
            var bridgeFound = false
            entries = entries.map {
                normalizeExistingBridgeHook($0, event: event, permissionTimeout: permissionTimeout, bridgeFound: &bridgeFound)
            }
            if bridgeFound {
                hooks[event] = entries
                continue
            }

            var hook: [String: Any] = [
                "type": "command",
                "command": command
            ]
            if event == "PermissionRequest" {
                hook["timeout"] = permissionTimeout
            }

            var entry: [String: Any] = ["hooks": [hook]]
            if ["Notification", "PermissionRequest", "PreToolUse", "PostToolUse"].contains(event) {
                entry["matcher"] = "*"
            }
            entries.append(entry)
            hooks[event] = entries
        }

        root["hooks"] = hooks
        return root
    }

    package static func mergedCodexHooks(existing: [String: Any], command: String) throws -> [String: Any] {
        var root = existing
        var hooks = try hooksDictionary(from: root)
        let permissionTimeout = codexPermissionHookTimeoutSeconds
        let events = [
            "PermissionRequest", "PreToolUse", "PostToolUse",
            "SessionStart", "Stop", "UserPromptSubmit"
        ]

        for event in events {
            var entries = try hookEntries(for: event, in: hooks)
            var bridgeFound = false
            entries = entries.map {
                normalizeExistingBridgeHook($0, event: event, permissionTimeout: permissionTimeout, bridgeFound: &bridgeFound)
            }
            if bridgeFound {
                hooks[event] = entries
                continue
            }

            var hook: [String: Any] = [
                "type": "command",
                "command": command
            ]
            if event == "PermissionRequest" {
                hook["timeout"] = permissionTimeout
            }

            var entry: [String: Any] = ["hooks": [hook]]
            if ["Notification", "PermissionRequest", "PreToolUse", "PostToolUse"].contains(event) {
                entry["matcher"] = "*"
            }
            entries.append(entry)
            hooks[event] = entries
        }

        root["hooks"] = hooks
        return root
    }

    private static func normalizeExistingBridgeHook(
        _ object: Any,
        event: String,
        permissionTimeout: Int,
        bridgeFound: inout Bool
    ) -> [String: Any] {
        normalizedBridgeObject(
            object,
            event: event,
            permissionTimeout: permissionTimeout,
            bridgeFound: &bridgeFound
        ) as? [String: Any] ?? object as? [String: Any] ?? [:]
    }

    private static func normalizedBridgeObject(
        _ object: Any,
        event: String,
        permissionTimeout: Int,
        bridgeFound: inout Bool
    ) -> Any {
        switch object {
        case let dictionary as [String: Any]:
            var normalized = dictionary.mapValues {
                normalizedBridgeObject($0, event: event, permissionTimeout: permissionTimeout, bridgeFound: &bridgeFound)
            }
            let command = dictionary["command"] as? String ?? dictionary["bash"] as? String
            if command?.contains(bridgeMarker) == true {
                bridgeFound = true
                if event == "PermissionRequest" {
                    normalized["timeout"] = permissionTimeout
                }
            }
            return normalized
        case let array as [Any]:
            return array.map {
                normalizedBridgeObject($0, event: event, permissionTimeout: permissionTimeout, bridgeFound: &bridgeFound)
            }
        case let string as String:
            if string.contains(bridgeMarker) {
                bridgeFound = true
            }
            return string
        default:
            return object
        }
    }

    private static func hooksDictionary(from root: [String: Any]) throws -> [String: Any] {
        guard let hooks = root["hooks"] else {
            return [:]
        }
        guard let dictionary = hooks as? [String: Any] else {
            throw HookInstallError.unsupportedStructure("hooks must be an object")
        }
        return dictionary
    }

    private static func hookEntries(for event: String, in hooks: [String: Any]) throws -> [[String: Any]] {
        guard let rawEntries = hooks[event] else {
            return []
        }
        guard let entries = rawEntries as? [[String: Any]] else {
            throw HookInstallError.unsupportedStructure("\(event) hooks must be an array of objects")
        }
        return entries
    }

    package static func containsBridge(_ object: Any) -> Bool {
        switch object {
        case let string as String:
            return string.contains(bridgeMarker)
        case let dictionary as [String: Any]:
            return dictionary.values.contains(where: containsBridge)
        case let array as [Any]:
            return array.contains(where: containsBridge)
        default:
            return false
        }
    }

    package static func removingBridgeHooks(existing: [String: Any]) throws -> [String: Any] {
        var root = existing
        guard root["hooks"] != nil else { return root }
        var hooks = try hooksDictionary(from: root)
        for key in Array(hooks.keys) {
            guard let entries = hooks[key] as? [[String: Any]] else { continue }
            let filteredEntries = entries.compactMap { entry -> [String: Any]? in
                var normalized = entry
                if let hookList = normalized["hooks"] as? [Any] {
                    let filteredHooks = hookList.filter { !containsBridge($0) }
                    guard !filteredHooks.isEmpty else { return nil }
                    normalized["hooks"] = filteredHooks
                    return normalized
                }
                return containsBridge(normalized) ? nil : normalized
            }
            if filteredEntries.isEmpty {
                hooks.removeValue(forKey: key)
            } else {
                hooks[key] = filteredEntries
            }
        }
        root["hooks"] = hooks
        return root
    }
}

package enum CodexConfigMerger {
    package struct Result: Equatable {
        package var text: String
        package var enabled: Bool
        package var changed: Bool

        package init(text: String, enabled: Bool, changed: Bool) {
            self.text = text
            self.enabled = enabled
            self.changed = changed
        }
    }

    package static func mergedFeatureFlagConfig(existing: String) -> Result {
        let normalized = existing.replacingOccurrences(of: "\r\n", with: "\n")
        var lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let hadTrailingNewline = normalized.hasSuffix("\n")

        if let sectionRange = featuresSectionRange(in: lines) {
            if let keyIndex = lines[sectionRange].firstIndex(where: isCodexHooksLine) {
                if codexHooksValue(in: lines[keyIndex]) == true {
                    return Result(text: normalized, enabled: true, changed: false)
                }
                lines[keyIndex] = "codex_hooks = true"
            } else {
                lines.insert("codex_hooks = true", at: sectionRange.lowerBound + 1)
            }
        } else {
            if !lines.isEmpty, lines.last?.isEmpty == false {
                lines.append("")
            }
            lines.append("[features]")
            lines.append("codex_hooks = true")
        }

        var merged = lines.joined(separator: "\n")
        if hadTrailingNewline || !merged.hasSuffix("\n") {
            merged += "\n"
        }
        return Result(text: merged, enabled: true, changed: merged != normalized)
    }

    private static func featuresSectionRange(in lines: [String]) -> Range<Int>? {
        guard let start = lines.firstIndex(where: { sectionName(from: $0) == "features" }) else {
            return nil
        }
        let end = lines[(start + 1)...].firstIndex { line in
            sectionName(from: line) != nil
        } ?? lines.endIndex
        return start..<end
    }

    private static func sectionName(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("["),
              !trimmed.hasPrefix("[["),
              let close = trimmed.firstIndex(of: "]") else {
            return nil
        }
        let name = String(trimmed[trimmed.index(after: trimmed.startIndex)..<close])
        let suffix = trimmed[trimmed.index(after: close)...].trimmingCharacters(in: .whitespaces)
        guard suffix.isEmpty || suffix.hasPrefix("#") else {
            return nil
        }
        return name
    }

    private static func isCodexHooksLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("codex_hooks") && trimmed.contains("=")
    }

    private static func codexHooksValue(in line: String) -> Bool? {
        let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        let value = parts[1]
            .split(separator: "#", maxSplits: 1)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        switch value {
        case "true": return true
        case "false": return false
        default: return nil
        }
    }
}

package enum HookInstallError: LocalizedError {
    case unsupportedStructure(String)

    package var errorDescription: String? {
        switch self {
        case .unsupportedStructure(let detail):
            "Unsupported hook configuration structure: \(detail)"
        }
    }
}

package final class HookInstaller {
    package static let bridgePayloadAllowedKeys: Set<String> = [
        "approval_id",
        "codex_event_type",
        "codex_last_assistant_message",
        "codex_permission_mode",
        "codex_session_start_source",
        "codex_transcript_path",
        "command",
        "cwd",
        "event",
        "hook_event_name",
        "permission_suggestions",
        "reason",
        "session_id",
        "sessionId",
        "timestamp",
        "thread_id",
        "threadId",
        "tool_input",
        "tool_name",
        "transcript_path",
        "turn_id",
        "type",
        "workspace"
    ]

    private let logger: AppLogger
    private let fileManager: FileManager

    package init(logger: AppLogger = .shared, fileManager: FileManager = .default) {
        self.logger = logger
        self.fileManager = fileManager
    }

    package func installBridgeScript() throws {
        try AppPaths.ensureRuntimeDirectories()
        let token = try ensureBridgeToken()
        let script = bridgeScript()
        try script.write(to: AppPaths.bridgeURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: AppPaths.bridgeURL.path)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: AppPaths.bridgeTokenURL.path)
        logger.info("bridge.token.ready", detail: "\(token.count) bytes")
        logger.info("bridge.script.installed", detail: AppPaths.bridgeURL.path)
    }

    package func installHooks(configuration: AppConfiguration) throws -> InstallReport {
        try installBridgeScript()
        var report = InstallReport(bridgeInstalled: true)

        if configuration.enableClaude {
            try mergeJSONFile(
                at: AppPaths.claudeSettingsURL,
                transform: { existing in
                    try HookConfigMerger.mergedClaudeSettings(
                        existing: existing,
                        command: claudeCommand()
                    )
                }
            )
            report.claudeHooksInstalled = true
        }

        if configuration.enableCodexCLI {
            try mergeJSONFile(
                at: AppPaths.codexHooksURL,
                transform: { existing in
                    try HookConfigMerger.mergedCodexHooks(
                        existing: existing,
                        command: codexCommand()
                    )
                }
            )
            report.codexHooksInstalled = true
            let featureFlag = try ensureCodexHooksFeatureFlag()
            report.codexFeatureFlagEnabled = featureFlag.enabled
            report.codexFeatureFlagChanged = featureFlag.changed
        }

        report.message = "Bridge and selected hooks installed."
        return report
    }

    package func uninstallHooks() throws -> InstallReport {
        var report = InstallReport(bridgeInstalled: fileManager.isExecutableFile(atPath: AppPaths.bridgeURL.path))
        if fileManager.fileExists(atPath: AppPaths.claudeSettingsURL.path) {
            try mergeJSONFile(
                at: AppPaths.claudeSettingsURL,
                transform: HookConfigMerger.removingBridgeHooks(existing:)
            )
            report.claudeHooksInstalled = false
        }
        if fileManager.fileExists(atPath: AppPaths.codexHooksURL.path) {
            try mergeJSONFile(
                at: AppPaths.codexHooksURL,
                transform: HookConfigMerger.removingBridgeHooks(existing:)
            )
            report.codexHooksInstalled = false
        }
        report.message = "Vibelsland hooks removed from Claude and Codex hook files."
        logger.info("hooks.uninstalled")
        return report
    }

    private func ensureCodexHooksFeatureFlag() throws -> CodexConfigMerger.Result {
        let url = AppPaths.codexConfigURL
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let result = CodexConfigMerger.mergedFeatureFlagConfig(existing: existing)
        guard result.changed else {
            logger.info("codex.feature.flag.unchanged", detail: url.path)
            return result
        }

        if fileManager.fileExists(atPath: url.path) {
            let backupURL = backupURL(for: url)
            try fileManager.copyItem(at: url, to: backupURL)
            logger.info("codex.feature.flag.backup", detail: backupURL.path)
        }
        try result.text.write(to: url, atomically: true, encoding: .utf8)
        logger.info("codex.feature.flag.enabled", detail: url.path)
        return result
    }

    private func mergeJSONFile(at url: URL, transform: ([String: Any]) throws -> [String: Any]) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let existing = try readJSONObject(at: url)
        let merged = try transform(existing)
        let data = try JSONSerialization.data(withJSONObject: merged, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        if let existingData = try? Data(contentsOf: url),
           jsonObjectsEqual(existingData, data) {
            logger.info("hooks.unchanged", detail: url.path)
            return
        }
        if fileManager.fileExists(atPath: url.path) {
            let backupURL = backupURL(for: url)
            try fileManager.copyItem(at: url, to: backupURL)
            logger.info("hooks.backup", detail: backupURL.path)
        }
        try data.write(to: url, options: [.atomic])
        logger.info("hooks.installed", detail: url.path)
    }

    private func readJSONObject(at url: URL) throws -> [String: Any] {
        guard fileManager.fileExists(atPath: url.path) else {
            return [:]
        }
        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            throw HookInstallError.unsupportedStructure("root JSON value must be an object")
        }
        return dictionary
    }

    private func backupURL(for url: URL) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let suffix = "\(formatter.string(from: Date()))-\(UUID().uuidString.prefix(8))"
        return url.deletingLastPathComponent()
            .appendingPathComponent("\(url.lastPathComponent).vibelsland-free.\(suffix).bak")
    }

    private func ensureBridgeToken() throws -> String {
        if let token = try? String(contentsOf: AppPaths.bridgeTokenURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
           token.count >= 32 {
            return token
        }

        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Unable to create bridge token"])
        }
        let token = bytes.map { String(format: "%02x", $0) }.joined()
        try token.write(to: AppPaths.bridgeTokenURL, atomically: true, encoding: .utf8)
        return token
    }

    private func jsonObjectsEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard let left = try? JSONSerialization.jsonObject(with: lhs),
              let right = try? JSONSerialization.jsonObject(with: rhs) else {
            return lhs == rhs
        }
        return canonicalJSONData(left) == canonicalJSONData(right)
    }

    private func canonicalJSONData(_ object: Any) -> Data? {
        guard JSONSerialization.isValidJSONObject(object) else {
            return nil
        }
        return try? JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
    }

    private func claudeCommand() -> String {
        "/bin/sh -c '[ -x \"$HOME/.vibelsland-free/bin/vibelsland-bridge\" ] && exec \"$HOME/.vibelsland-free/bin/vibelsland-bridge\" --source claude; exit 0'"
    }

    private func codexCommand() -> String {
        "/bin/sh -c '[ -x \"$HOME/.vibelsland-free/bin/vibelsland-bridge\" ] && exec \"$HOME/.vibelsland-free/bin/vibelsland-bridge\" --source codex; exit 0'"
    }

    private func bridgeScript() -> String {
        """
        #!/bin/zsh
        set -u

        SOCKET="$HOME/.vibelsland-free/run/vibelsland.sock"
        TOKEN_FILE="$HOME/.vibelsland-free/run/bridge-token"
        SOURCE="unknown"

        while [[ $# -gt 0 ]]; do
          case "$1" in
            --source)
              SOURCE="${2:-unknown}"
              shift 2
              ;;
            *)
              shift
              ;;
          esac
        done

        if command -v python3 >/dev/null 2>&1; then
          python3 -c '
        import json
        import os
        import socket
        import sys
        import time

        sock_path, token_file, source, cwd = sys.argv[1:5]
        raw_input = sys.stdin.read()

        try:
            payload = json.loads(raw_input) if raw_input.strip() else {}
        except Exception:
            payload = {"text": raw_input}

        event_name = (
            os.environ.get("CLAUDE_HOOK_EVENT_NAME")
            or os.environ.get("CODEX_HOOK_EVENT_NAME")
            or payload.get("hook_event_name")
            or payload.get("event")
            or payload.get("type")
            or "hook"
        )

        allowed_keys = { \(Self.bridgePayloadAllowedKeysLiteral) }
        sanitized_payload = {key: value for key, value in payload.items() if key in allowed_keys}
        try:
            event_timestamp = float(payload.get("timestamp", time.time()))
        except Exception:
            event_timestamp = time.time()

        if isinstance(sanitized_payload.get("tool_input"), dict):
            safe_tool_input_keys = {
                "command", "file_path", "path", "pattern", "url",
                "description", "tool_name"
            }
            sanitized_payload["tool_input"] = {
                key: value
                for key, value in sanitized_payload["tool_input"].items()
                if key in safe_tool_input_keys
            }

        try:
            with open(token_file, "r", encoding="utf-8") as token_handle:
                token = token_handle.read().strip()
        except Exception:
            token = ""

        envelope = {
            "token": token,
            "source": source,
            "event": event_name,
            "workspace": payload.get("cwd") or cwd,
            "timestamp": event_timestamp,
            "payload": sanitized_payload,
        }

        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
                client.settimeout(float(os.environ.get("VIBELSLAND_BRIDGE_TIMEOUT", "\(HookConfigMerger.bridgeClientTimeoutSeconds)")))
                client.connect(sock_path)
                client.sendall((json.dumps(envelope, separators=(",", ":")) + "\\n").encode("utf-8"))
                client.shutdown(socket.SHUT_WR)
                chunks = []
                while True:
                    chunk = client.recv(8192)
                    if not chunk:
                        break
                    chunks.append(chunk)
                response = b"".join(chunks).decode("utf-8", "replace").strip()
                if response:
                    print(response)
        except Exception:
            pass
        ' "$SOCKET" "$TOKEN_FILE" "$SOURCE" "$PWD"
          exit 0
        fi

        exit 0
        """
    }

    private static var bridgePayloadAllowedKeysLiteral: String {
        bridgePayloadAllowedKeys
            .sorted()
            .map { #""\#($0)""# }
            .joined(separator: ", ")
    }
}
