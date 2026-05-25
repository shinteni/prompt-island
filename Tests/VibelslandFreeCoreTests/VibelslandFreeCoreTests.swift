import Foundation
import Testing
@testable import VibelslandFreeCore

func XCTAssertTrue(_ condition: @autoclosure () -> Bool, _ message: String = "") {
    #expect(condition(), Comment(rawValue: message))
}

func XCTAssertFalse(_ condition: @autoclosure () -> Bool, _ message: String = "") {
    #expect(!condition(), Comment(rawValue: message))
}

func XCTAssertEqual<T: Equatable>(_ first: @autoclosure () -> T, _ second: @autoclosure () -> T, _ message: String = "") {
    #expect(first() == second(), Comment(rawValue: message))
}

func XCTAssertNotEqual<T: Equatable>(_ first: @autoclosure () -> T, _ second: @autoclosure () -> T, _ message: String = "") {
    #expect(first() != second(), Comment(rawValue: message))
}

@Suite
struct VibelslandFreeCoreTests {
    @Test func testSmokeCoverage() throws {
        func jsonDictionary(_ text: String) throws -> [String: Any] {
            let data = text.data(using: .utf8)!
            return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        }
        
        XCTAssertTrue(ApprovalResponseMapper.codexAppServerResponse(for: .accept) == #"{"decision":"accept"}"#, "Codex app-server accept mapping")
        XCTAssertTrue(ApprovalResponseMapper.codexAppServerResponse(for: .acceptForSession) == #"{"decision":"acceptForSession"}"#, "Codex app-server session mapping")
        XCTAssertTrue(ApprovalResponseMapper.codexAppServerResponse(for: .decline) == #"{"decision":"decline"}"#, "Codex app-server decline mapping")
        XCTAssertTrue(ApprovalDecision.accept.title == "允许一次", "Approval accept title")
        XCTAssertTrue(ApprovalDecision.acceptForSession.title == "本轮始终允许", "Approval session title")
        XCTAssertTrue(ApprovalDecision.cancel.title == "取消任务", "Approval cancel title")
        XCTAssertTrue(DisplayConfidence.realtime.title == "实时连接", "Display confidence title")
        XCTAssertTrue(HealthCheckStatus.needsAction.title == "需要处理", "Health status title")
        XCTAssertTrue(ClaudeCLIProcessMatcher.isClaudeCLIProcess("claude --print"), "Direct Claude CLI process recognized")
        XCTAssertTrue(ClaudeCLIProcessMatcher.isClaudeCLIProcess("/opt/homebrew/bin/npx @anthropic-ai/claude-code"), "npx Claude wrapper process recognized")
        XCTAssertTrue(ClaudeCLIProcessMatcher.isClaudeCLIProcess("node /opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/cli.js"), "node Claude wrapper process recognized")
        XCTAssertTrue(!ClaudeCLIProcessMatcher.isClaudeCLIProcess("node /tmp/not-claude.js"), "Unrelated node process ignored")
        
        let codexPermission = AgentEvent(
            source: .codexCli,
            kind: .approval,
            payload: .object(["hook_event_name": .string("PermissionRequest")])
        )
        let codexAllowResponse = try jsonDictionary(ApprovalResponseMapper.hookResponse(for: codexPermission, decision: .accept) ?? "{}")
        let codexAllowOutput = codexAllowResponse["hookSpecificOutput"] as? [String: Any]
        let codexAllowDecision = codexAllowOutput?["decision"] as? [String: Any]
        XCTAssertTrue(codexAllowOutput?["hookEventName"] as? String == "PermissionRequest", "Codex hook event name")
        XCTAssertTrue(codexAllowDecision?["behavior"] as? String == "allow", "Codex hook allow schema")
        
        let codexDeclineResponse = try jsonDictionary(ApprovalResponseMapper.hookResponse(for: codexPermission, decision: .decline) ?? "{}")
        let codexDeclineOutput = codexDeclineResponse["hookSpecificOutput"] as? [String: Any]
        let codexDeclineDecision = codexDeclineOutput?["decision"] as? [String: Any]
        XCTAssertTrue(codexDeclineDecision?["behavior"] as? String == "deny", "Codex hook deny schema")
        XCTAssertTrue(ApprovalResponseMapper.hookResponse(for: codexPermission, decision: .acceptForSession) == nil, "Codex hook session decision falls back")
        
        let claudePermission = AgentEvent(
            source: .claudeCode,
            kind: .approval,
            payload: .object([
                "hook_event_name": .string("PermissionRequest"),
                "permission_suggestions": .array([
                    .object([
                        "type": .string("setMode"),
                        "mode": .string("acceptEdits"),
                        "destination": .string("session")
                    ])
                ])
            ])
        )
        let claudePermissionResponse = ApprovalResponseMapper.hookResponse(for: claudePermission, decision: .acceptForSession) ?? ""
        XCTAssertTrue(claudePermissionResponse.contains(#""hookEventName":"PermissionRequest""#), "Claude PermissionRequest envelope")
        XCTAssertTrue(claudePermissionResponse.contains(#""updatedPermissions""#), "Claude session permission mapping")
        XCTAssertTrue(!claudePermissionResponse.contains("localSettings"), "Claude session permission filters persistent suggestions")
        
        let persistentSuggestion: JSONValue = .array([
            .object([
                "type": .string("setMode"),
                "mode": .string("acceptEdits"),
                "destination": .string("localSettings")
            ])
        ])
        let bypassSuggestion: JSONValue = .array([
            .object([
                "type": .string("setMode"),
                "mode": .string("bypassPermissions"),
                "destination": .string("session")
            ])
        ])
        let unknownFieldSuggestion: JSONValue = .array([
            .object([
                "type": .string("setMode"),
                "mode": .string("acceptEdits"),
                "destination": .string("session"),
                "unknown": .bool(true)
            ])
        ])
        XCTAssertTrue(!PermissionSuggestionSanitizer.hasSafeClaudeSessionSuggestion(persistentSuggestion), "Persistent Claude suggestion rejected")
        XCTAssertTrue(!PermissionSuggestionSanitizer.hasSafeClaudeSessionSuggestion(bypassSuggestion), "Claude bypassPermissions suggestion rejected")
        XCTAssertTrue(!PermissionSuggestionSanitizer.hasSafeClaudeSessionSuggestion(unknownFieldSuggestion), "Claude unknown fields rejected")
        
        let unsupportedClaude = AgentEvent(source: .claudeCode, kind: .approval, payload: .object(["hook_event_name": .string("Unknown")]))
        XCTAssertTrue(ApprovalResponseMapper.hookResponse(for: unsupportedClaude, decision: .accept) == nil, "Unsupported Claude approval falls back")
        
        let bridgeData = #"{"source":"codex","event":"PermissionRequest","workspace":"/tmp/work","payload":{"tool_name":"Bash","command":"npm test"}}"#.data(using: .utf8)!
        let event = try EventParser.parseBridgeData(bridgeData)
        XCTAssertTrue(event.source == .codexCli, "Codex source parsing")
        XCTAssertTrue(event.kind == .approval, "PermissionRequest kind")
        XCTAssertTrue(event.workspace == "/tmp/work", "Workspace parsing")
        XCTAssertTrue(EventParser.approvalRequest(for: event)?.tool == "Bash", "Approval tool parsing")
        XCTAssertTrue(EventParser.approvalRequest(for: event)?.availableDecisions == [.accept, .decline], "Codex hook decisions are limited")
        XCTAssertTrue(HookInstaller.bridgePayloadAllowedKeys.contains("thread_id"), "Bridge script keeps Codex CLI thread_id for deep links")
        XCTAssertTrue(HookInstaller.bridgePayloadAllowedKeys.contains("threadId"), "Bridge script keeps Codex CLI threadId for deep links")
        XCTAssertTrue(HookInstaller.bridgePayloadAllowedKeys.contains("timestamp"), "Bridge script accepts timestamp for non-visible smoke events")

        let bridgeThreadData = #"{"source":"codex","event":"Status","timestamp":1,"payload":{"thread_id":"123E4567-E89B-12D3-A456-426614174000","session_id":"fallback"}}"#.data(using: .utf8)!
        let bridgeThreadEvent = try EventParser.parseBridgeData(bridgeThreadData)
        XCTAssertEqual(bridgeThreadEvent.threadId, "123E4567-E89B-12D3-A456-426614174000", "Codex thread id is parsed before session id")
        XCTAssertEqual(bridgeThreadEvent.timestamp, Date(timeIntervalSince1970: 1), "Bridge timestamp can be controlled by smoke tests")

        let bridgeDesktopDerivedData = #"{"source":"codex","event":"SessionStart","payload":{"thread_id":"thread-non-uuid","codex_session_start_source":"codex_desktop_subagent"}}"#.data(using: .utf8)!
        let bridgeDesktopDerivedEvent = try EventParser.parseBridgeData(bridgeDesktopDerivedData)
        XCTAssertEqual(bridgeDesktopDerivedEvent.threadId, "thread-non-uuid", "Codex non-UUID thread id is preserved for deep links")
        XCTAssertEqual(bridgeDesktopDerivedEvent.codexSessionStartSource, "codex_desktop_subagent", "Codex session start source is parsed for dedupe")
        
        let codexStopData = #"{"source":"codex","event":"Stop","workspace":"/tmp/work","payload":{"hook_event_name":"Stop"}}"#.data(using: .utf8)!
        let codexStopEvent = try EventParser.parseBridgeData(codexStopData)
        XCTAssertTrue(codexStopEvent.kind == .session, "Codex Stop is a session event")
        XCTAssertTrue(SessionStatusResolver.status(for: codexStopEvent) == .done, "Codex Stop resolves to done")
        
        let claudeSessionEndData = #"{"source":"claude","event":"SessionEnd","workspace":"/tmp/work","payload":{"hook_event_name":"SessionEnd"}}"#.data(using: .utf8)!
        let claudeSessionEndEvent = try EventParser.parseBridgeData(claudeSessionEndData)
        XCTAssertTrue(SessionStatusResolver.status(for: claudeSessionEndEvent) == .done, "Claude SessionEnd resolves to done")

        let claudeSubagentStopData = #"{"source":"claude","event":"SubagentStop","workspace":"/tmp/work","payload":{"hook_event_name":"SubagentStop"}}"#.data(using: .utf8)!
        let claudeSubagentStopEvent = try EventParser.parseBridgeData(claudeSubagentStopData)
        XCTAssertTrue(SessionStatusResolver.status(for: claudeSubagentStopEvent) == .thinking, "SubagentStop does not complete the parent session")
        XCTAssertTrue(SessionStatusResolver.isSubagentCompletion(claudeSubagentStopEvent), "SubagentStop can still mark the child as complete")
        
        let codexTaskComplete = AgentEvent(
            source: .codexCli,
            kind: .status,
            payload: .object(["codex_event_type": .string("task_complete")])
        )
        XCTAssertTrue(SessionStatusResolver.status(for: codexTaskComplete) == .done, "Codex task_complete resolves to done")
        let codexTurnAborted = AgentEvent(
            source: .codexCli,
            kind: .status,
            payload: .object(["codex_event_type": .string("turn_aborted")])
        )
        XCTAssertTrue(SessionStatusResolver.status(for: codexTurnAborted) == .failed, "Codex turn_aborted does not resolve to done")
        let continuingAfterSuccessfulCommand = AgentEvent(
            source: .codexDesktop,
            kind: .notification,
            payload: .object(["message": .string("命令成功，继续下一步")])
        )
        XCTAssertTrue(
            SessionStatusResolver.status(for: continuingAfterSuccessfulCommand) == .thinking,
            "Natural-language success inside ongoing work does not resolve the task"
        )
        
        let incompleteMessage = AgentEvent(
            source: .claudeCode,
            kind: .notification,
            payload: .object(["message": .string("任务尚未完成")])
        )
        XCTAssertTrue(SessionStatusResolver.status(for: incompleteMessage) == .thinking, "Incomplete wording is not treated as done")
        
        let codexPostTool = AgentEvent(
            source: .codexCli,
            kind: .tool,
            payload: .object(["hook_event_name": .string("PostToolUse")])
        )
        XCTAssertTrue(SessionStatusResolver.status(for: codexPostTool) == .thinking, "PostToolUse returns to thinking")
        
        let desktopStatusNow = Date()
        let desktopToolFinishedSnapshot = CodexThreadSnapshot(
            activities: [
                ActivityItem(symbol: "checkmark.circle", title: "工具完成", detail: "exec_command", date: desktopStatusNow)
            ],
            usage: nil,
            lastAssistantMessage: nil,
            lastUserMessage: "run tests",
            isComplete: false
        )
        XCTAssertTrue(
            SessionStatusResolver.codexDesktopStatus(
                recordUpdatedAt: desktopStatusNow,
                snapshot: desktopToolFinishedSnapshot,
                hasPendingApproval: false,
                now: desktopStatusNow
            ) == .thinking,
            "Desktop tool completion is not task completion"
        )
        
        let desktopAssistantMessageSnapshot = CodexThreadSnapshot(
            activities: [
                ActivityItem(symbol: "text.bubble", title: "消息", detail: "继续处理", date: desktopStatusNow)
            ],
            usage: nil,
            lastAssistantMessage: "继续处理",
            lastUserMessage: "run tests",
            isComplete: false
        )
        XCTAssertTrue(
            SessionStatusResolver.codexDesktopStatus(
                recordUpdatedAt: desktopStatusNow,
                snapshot: desktopAssistantMessageSnapshot,
                hasPendingApproval: false,
                now: desktopStatusNow
            ) == .thinking,
            "Desktop assistant message alone is not task completion"
        )
        
        let desktopCompleteSnapshot = CodexThreadSnapshot(
            activities: [
                ActivityItem(symbol: "checkmark.circle", title: "完成", detail: "任务完成", date: desktopStatusNow)
            ],
            usage: nil,
            lastAssistantMessage: "done",
            lastUserMessage: "run tests",
            isComplete: true
        )
        XCTAssertTrue(
            SessionStatusResolver.codexDesktopStatus(
                recordUpdatedAt: desktopStatusNow,
                snapshot: desktopCompleteSnapshot,
                hasPendingApproval: false,
                now: desktopStatusNow
            ) == .done,
            "Desktop task_complete marks done"
        )
        
        let desktopResumedAfterCompleteSnapshot = CodexThreadSnapshot(
            activities: [
                ActivityItem(symbol: "checkmark.circle", title: "完成", detail: "任务完成", date: desktopStatusNow.addingTimeInterval(-60)),
                ActivityItem(symbol: "text.bubble", title: "消息", detail: "继续处理", date: desktopStatusNow)
            ],
            usage: nil,
            lastAssistantMessage: "继续处理",
            lastUserMessage: "调整 UI",
            isComplete: true,
            completedAt: desktopStatusNow.addingTimeInterval(-60),
            latestActiveAt: desktopStatusNow
        )
        XCTAssertTrue(
            SessionStatusResolver.codexDesktopStatus(
                recordUpdatedAt: desktopStatusNow,
                snapshot: desktopResumedAfterCompleteSnapshot,
                hasPendingApproval: false,
                now: desktopStatusNow
            ) == .thinking,
            "Desktop activity after task_complete reopens the turn"
        )
        
        let resumedRolloutURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vibelsland-resumed-\(UUID().uuidString).jsonl")
        let resumedRolloutLines = [
            #"{"timestamp":"2026-05-07T03:41:54Z","type":"event_msg","payload":{"type":"task_complete","last_agent_message":"已完成。"}}"#,
            #"{"timestamp":"2026-05-07T03:49:32Z","type":"event_msg","payload":{"type":"user_message","message":"继续改 UI"}}"#,
            #"{"timestamp":"2026-05-07T03:49:46Z","type":"event_msg","payload":{"type":"agent_message","message":"继续处理中"}}"#
        ].joined(separator: "\n")
        try resumedRolloutLines.write(to: resumedRolloutURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: resumedRolloutURL) }
        
        let resumedRecord = CodexThreadRecord(
            id: "resumed-thread",
            cwd: "/tmp/vibelsland",
            title: "resumed",
            source: "",
            approvalMode: "",
            sandboxPolicy: "",
            rolloutPath: resumedRolloutURL.path,
            updatedAt: desktopStatusNow,
            updatedAtMilliseconds: Int64(desktopStatusNow.timeIntervalSince1970 * 1000),
            model: "gpt-5.5",
            agentNickname: "",
            agentRole: "",
            parentThreadID: nil
        )
        let resumedSnapshot = CodexDesktopStateReader().loadThreadSnapshot(for: resumedRecord)
        XCTAssertTrue(!resumedSnapshot.isComplete, "Desktop reader clears completion after later activity")
        XCTAssertTrue(resumedSnapshot.completedAt != nil, "Desktop reader records completion time")
        XCTAssertTrue(resumedSnapshot.latestActiveAt != nil, "Desktop reader records later activity time")

        let trailingRolloutURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vibelsland-trailing-\(UUID().uuidString).jsonl")
        let trailingRolloutLines = [
            #"{"timestamp":"2026-05-07T03:41:54Z","type":"event_msg","payload":{"type":"task_complete","last_agent_message":"已完成。"}}"#,
            #"{"timestamp":"2026-05-07T03:41:55Z","type":"event_msg","payload":{"type":"exec_command_end","call_id":"call_1"}}"#,
            #"{"timestamp":"2026-05-07T03:41:56Z","type":"response_item","payload":{"type":"function_call_output","call_id":"call_1","output":"ok"}}"#
        ].joined(separator: "\n")
        try trailingRolloutLines.write(to: trailingRolloutURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: trailingRolloutURL) }

        let trailingRecord = CodexThreadRecord(
            id: "trailing-thread",
            cwd: "/tmp/vibelsland",
            title: "trailing",
            source: "",
            approvalMode: "",
            sandboxPolicy: "",
            rolloutPath: trailingRolloutURL.path,
            updatedAt: desktopStatusNow,
            updatedAtMilliseconds: Int64(desktopStatusNow.timeIntervalSince1970 * 1000),
            model: "gpt-5.5",
            agentNickname: "",
            agentRole: "",
            parentThreadID: nil
        )
        let trailingSnapshot = CodexDesktopStateReader().loadThreadSnapshot(for: trailingRecord)
        XCTAssertTrue(trailingSnapshot.isComplete, "Trailing tool-end noise after task_complete does not reopen the Desktop turn")

        XCTAssertTrue(
            CodexDesktopStateReader.shouldIncludeChildRecord(
                updatedAt: desktopStatusNow.addingTimeInterval(-30 * 60),
                now: desktopStatusNow
            ),
            "Recent Codex Desktop child records stay eligible for subagent status"
        )
        XCTAssertFalse(
            CodexDesktopStateReader.shouldIncludeChildRecord(
                updatedAt: desktopStatusNow.addingTimeInterval(-3 * 60 * 60),
                now: desktopStatusNow
            ),
            "Stale Codex Desktop child records are skipped instead of repeatedly reading old transcripts"
        )
        let emptyThreadRows = try CodexDesktopStateReader.decodeThreadRows(from: Data())
        let whitespaceThreadRows = try CodexDesktopStateReader.decodeThreadRows(from: Data(" \n\t".utf8))
        XCTAssertEqual(emptyThreadRows.count, 0, "sqlite3 -json returns empty stdout for zero rows; this is a valid empty result")
        XCTAssertEqual(whitespaceThreadRows.count, 0, "Whitespace-only sqlite output is also treated as an empty result")
        
        let lateNotification = AgentEvent(
            source: .codexCli,
            kind: .notification,
            payload: .object(["message": .string("background update")])
        )
        XCTAssertTrue(SessionStatusResolver.shouldPreserveDoneStatus(current: .done, next: .thinking, event: lateNotification), "Late generic notifications preserve done")
        
        let newPromptEvent = AgentEvent(
            source: .codexCli,
            kind: .prompt,
            payload: .object(["hook_event_name": .string("UserPromptSubmit"), "prompt": .string("new task")])
        )
        XCTAssertTrue(!SessionStatusResolver.shouldPreserveDoneStatus(current: .done, next: .thinking, event: newPromptEvent), "New prompts can leave done state")
        
        let bridgeToolInputData = #"{"source":"codex","event":"PermissionRequest","workspace":"/tmp/work","payload":{"tool_name":"Bash","tool_input":{"command":"npm test"}}}"#.data(using: .utf8)!
        let toolInputEvent = try EventParser.parseBridgeData(bridgeToolInputData)
        XCTAssertTrue(EventParser.approvalRequest(for: toolInputEvent)?.detail == "npm test", "Approval command detail parsing")
        let parsedCodexHookResponse = try jsonDictionary(ApprovalResponseMapper.hookResponse(for: toolInputEvent, decision: .accept) ?? "{}")
        let parsedCodexHookOutput = parsedCodexHookResponse["hookSpecificOutput"] as? [String: Any]
        let parsedCodexHookDecision = parsedCodexHookOutput?["decision"] as? [String: Any]
        XCTAssertTrue(parsedCodexHookDecision?["behavior"] as? String == "allow", "Parsed Codex bridge approval can return allow")
        
        let command = "/Users/test/.vibelsland-free/bin/vibelsland-bridge --source codex"
        let once = try HookConfigMerger.mergedCodexHooks(existing: [:], command: command)
        let twice = try HookConfigMerger.mergedCodexHooks(existing: once, command: command)
        let hooks = twice["hooks"] as? [String: Any]
        let permission = hooks?["PermissionRequest"] as? [[String: Any]]
        XCTAssertTrue(permission?.count == 1, "Codex hook merge idempotence")
        let permissionHook = ((permission?.first?["hooks"] as? [[String: Any]])?.first)
        XCTAssertTrue(permissionHook?["timeout"] as? Int == HookConfigMerger.codexPermissionHookTimeoutSeconds, "Codex permission timeout")
        let codexHookEvents = Set(hooks?.keys.compactMap { $0 } ?? [])
        XCTAssertTrue(codexHookEvents == Set(["PermissionRequest", "PreToolUse", "PostToolUse", "SessionStart", "Stop", "UserPromptSubmit"]), "Codex hook events match supported set")
        
        let oldShortTimeout: [String: Any] = [
            "hooks": [
                "PermissionRequest": [
                    [
                        "hooks": [
                            [
                                "type": "command",
                                "command": command,
                                "timeout": 35
                            ]
                        ],
                        "matcher": "*"
                    ]
                ]
            ]
        ]
        let repaired = try HookConfigMerger.mergedCodexHooks(existing: oldShortTimeout, command: command)
        let repairedPermission = ((repaired["hooks"] as? [String: Any])?["PermissionRequest"] as? [[String: Any]])?.first
        let repairedHook = (repairedPermission?["hooks"] as? [[String: Any]])?.first
        XCTAssertTrue(repairedHook?["timeout"] as? Int == HookConfigMerger.codexPermissionHookTimeoutSeconds, "Existing Codex timeout repaired")
        let removedBridge = try HookConfigMerger.removingBridgeHooks(existing: repaired)
        XCTAssertTrue(!HookConfigMerger.containsBridge(removedBridge), "Bridge hooks can be removed")
        
        let missingFeatureFlag = CodexConfigMerger.mergedFeatureFlagConfig(existing: "model = \"gpt-5.2\"\n")
        XCTAssertTrue(missingFeatureFlag.changed, "Codex feature flag inserted")
        XCTAssertTrue(missingFeatureFlag.text.contains("[features]\ncodex_hooks = true"), "Codex feature flag text")
        let existingFeatureFlag = CodexConfigMerger.mergedFeatureFlagConfig(existing: "[features]\ncodex_hooks = true\n")
        XCTAssertTrue(existingFeatureFlag.enabled && !existingFeatureFlag.changed, "Codex feature flag idempotence")
        let disabledFeatureFlag = CodexConfigMerger.mergedFeatureFlagConfig(existing: "[features]\ncodex_hooks = false\n")
        XCTAssertTrue(disabledFeatureFlag.changed && disabledFeatureFlag.text.contains("codex_hooks = true"), "Codex feature flag flips false")
        XCTAssertTrue(DisplayTextSanitizer.sanitize("复刻 " + "Vibe " + "Island UI") == "复刻 浮岛 UI", "Display title sanitizer")

        let resolverHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("vibelsland-codex-resolver-\(UUID().uuidString)", isDirectory: true)
        let standaloneBinURL = resolverHome
            .appendingPathComponent(".codex/packages/standalone/current/bin", isDirectory: true)
        let localBinURL = resolverHome
            .appendingPathComponent(".local/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: standaloneBinURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: localBinURL, withIntermediateDirectories: true)
        let standaloneCodexURL = standaloneBinURL.appendingPathComponent("codex")
        let localCodexURL = localBinURL.appendingPathComponent("codex")
        try "#!/bin/sh\n".write(to: standaloneCodexURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: standaloneCodexURL.path)
        try FileManager.default.createSymbolicLink(at: localCodexURL, withDestinationURL: standaloneCodexURL)
        defer { try? FileManager.default.removeItem(at: resolverHome) }

        XCTAssertEqual(
            CodexExecutableResolver.executablePath(environment: ["HOME": resolverHome.path]),
            localCodexURL.path,
            "Codex executable resolver prefers the user-installed CLI before bundled app resources"
        )
        let codexEnvironment = CodexExecutableResolver.processEnvironment(
            forExecutablePath: localCodexURL.path,
            baseEnvironment: ["HOME": resolverHome.path, "PATH": "/custom/bin"]
        )
        let pathEntries = codexEnvironment["PATH"]?.split(separator: ":").map(String.init) ?? []
        XCTAssertEqual(pathEntries.first, localBinURL.path, "Codex child PATH starts with the selected executable directory")
        XCTAssertTrue(pathEntries.contains(standaloneBinURL.path), "Codex child PATH includes symlink target directory")
        XCTAssertTrue(pathEntries.contains("/Applications/Codex.app/Contents/Resources"), "Codex child PATH includes bundled Codex resources")
        XCTAssertTrue(
            (pathEntries.firstIndex(of: standaloneBinURL.path) ?? .max) < (pathEntries.firstIndex(of: "/custom/bin") ?? .min),
            "Codex child PATH puts known runtime locations before inherited PATH entries"
        )

        let desktopCommandRequest: [String: Any] = [
            "id": "request-1",
            "method": "item/commandExecution/requestApproval",
            "params": [
                "threadId": "thread-1",
                "turnId": "turn-1",
                "itemId": "item-1",
                "cwd": "/tmp/work",
                "command": "npm test",
                "availableDecisions": ["accept", "acceptForSession", "decline", "cancel"]
            ]
        ]
        let desktopCommandApproval = CodexAppServerLiveClient.approval(from: desktopCommandRequest)
        XCTAssertTrue(desktopCommandApproval?.id == "codex-desktop-approval-request-1", "Desktop approval request id mapping")
        XCTAssertTrue(desktopCommandApproval?.threadID == "thread-1", "Desktop approval thread id mapping")
        XCTAssertTrue(desktopCommandApproval?.detail == "npm test", "Desktop command detail mapping")
        XCTAssertTrue(desktopCommandApproval?.approvalRequest.availableDecisions == [.accept, .acceptForSession, .decline, .cancel], "Desktop approval request decisions")
        XCTAssertEqual(
            CodexAppServerLiveClient.loadedThreadIDs(
                from: ["id": 101, "result": ["data": ["thread-1", "thread-2"]]]
            ),
            ["thread-1", "thread-2"],
            "Desktop loaded thread response is parsed for deep link verification"
        )
        XCTAssertEqual(CodexAppServerLiveClient.integerID(from: "101"), 101)
        XCTAssertEqual(CodexAppServerLiveClient.integerID(from: 101.0), 101)
        XCTAssertTrue(
            CodexAppServerLiveClient.responseResult(for: desktopCommandApproval!, decision: .acceptForSession)?["decision"] as? String == "acceptForSession",
            "Desktop command session response"
        )
        XCTAssertTrue(
            CodexAppServerLiveClient.responseResult(for: desktopCommandApproval!, decision: .decline)?["decision"] as? String == "decline",
            "Desktop command decline response"
        )
        let desktopAccept = CodexAppServerLiveClient.responseResult(for: desktopCommandApproval!, decision: .accept)
        XCTAssertTrue(desktopAccept?["decision"] as? String == "accept", "Desktop command accept response")
        let desktopCancel = CodexAppServerLiveClient.responseResult(for: desktopCommandApproval!, decision: .cancel)
        XCTAssertTrue(desktopCancel?["decision"] as? String == "cancel", "Desktop command cancel response")
        
        let restrictedDesktopCommandRequest: [String: Any] = [
            "id": "request-2",
            "method": "item/commandExecution/requestApproval",
            "params": [
                "threadId": "thread-1",
                "cwd": "/tmp/work",
                "command": "npm test",
                "availableDecisions": ["accept", "decline"]
            ]
        ]
        let restrictedDesktopApproval = CodexAppServerLiveClient.approval(from: restrictedDesktopCommandRequest)
        XCTAssertTrue(restrictedDesktopApproval?.approvalRequest.availableDecisions == [.accept, .decline], "Restricted Desktop decisions preserved")
        XCTAssertTrue(CodexAppServerLiveClient.responseResult(for: restrictedDesktopApproval!, decision: .acceptForSession) == nil, "Unsupported Desktop decision rejected")
        
        let snakeDesktopCommandRequest: [String: Any] = [
            "id": "request-3",
            "method": "item/fileChange/requestApproval",
            "params": [
                "threadId": "thread-1",
                "cwd": "/tmp/work",
                "reason": "edit files",
                "available_decisions": ["accept", "decline"]
            ]
        ]
        let snakeDesktopApproval = CodexAppServerLiveClient.approval(from: snakeDesktopCommandRequest)
        XCTAssertTrue(snakeDesktopApproval?.approvalRequest.availableDecisions == [.accept, .decline], "Snake case Desktop decisions parsed")
        
        let unknownDesktopCommandRequest: [String: Any] = [
            "id": "request-4",
            "method": "item/commandExecution/requestApproval",
            "params": [
                "threadId": "thread-1",
                "cwd": "/tmp/work",
                "command": "npm test",
                "availableDecisions": ["approve_forever"]
            ]
        ]
        let unknownDesktopApproval = CodexAppServerLiveClient.approval(from: unknownDesktopCommandRequest)
        XCTAssertTrue(unknownDesktopApproval?.approvalRequest.availableDecisions == [], "Unknown Desktop decisions do not default to unsafe buttons")
        XCTAssertTrue(CodexAppServerLiveClient.responseResult(for: unknownDesktopApproval!, decision: .accept) == nil, "Unknown Desktop decisions rejected")
        
        let desktopLegacyRequest: [String: Any] = [
            "id": 42,
            "method": "execCommandApproval",
            "params": [
                "conversationId": "thread-legacy",
                "callId": "call-1",
                "cwd": "/tmp/work",
                "command": ["npm", "test"],
                "parsedCmd": []
            ]
        ]
        let desktopLegacyApproval = CodexAppServerLiveClient.approval(from: desktopLegacyRequest)
        XCTAssertTrue(desktopLegacyApproval?.id == "codex-desktop-approval-42", "Legacy desktop approval numeric id mapping")
        XCTAssertTrue(desktopLegacyApproval?.detail == "npm test", "Legacy desktop command detail")
        let legacySession = CodexAppServerLiveClient.responseResult(for: desktopLegacyApproval!, decision: .acceptForSession)
        XCTAssertTrue(legacySession?["decision"] as? String == "approved_for_session", "Legacy desktop session response")
        let legacyAbort = CodexAppServerLiveClient.responseResult(for: desktopLegacyApproval!, decision: .cancel)
        XCTAssertTrue(legacyAbort?["decision"] as? String == "abort", "Legacy desktop cancel response")
        
        let desktopPermissionRequest: [String: Any] = [
            "id": "permission-1",
            "method": "item/permissions/requestApproval",
            "params": [
                "threadId": "thread-1",
                "turnId": "turn-1",
                "itemId": "item-2",
                "cwd": "/tmp/work",
                "reason": "need write access",
                "permissions": [
                    "fileSystem": [
                        "write": ["/tmp/work"]
                    ],
                    "network": [
                        "enabled": true
                    ]
                ]
            ]
        ]
        let desktopPermissionApproval = CodexAppServerLiveClient.approval(from: desktopPermissionRequest)
        XCTAssertTrue(desktopPermissionApproval?.tool == "权限请求", "Desktop permissions approval parsed")
        let permissionResult = CodexAppServerLiveClient.responseResult(for: desktopPermissionApproval!, decision: .acceptForSession)
        XCTAssertTrue(permissionResult?["scope"] as? String == "session", "Desktop permissions session scope")
        XCTAssertTrue(permissionResult?["permissions"] as? [String: Any] != nil, "Desktop permissions grant payload")
        
        let tempDirectory = FileManager.default.temporaryDirectory
        let claudeTranscriptURL = tempDirectory.appendingPathComponent("vibelsland-claude-\(UUID().uuidString).jsonl")
        let claudeTranscript = [
            #"{"type":"user","timestamp":"2026-05-06T12:00:00Z","message":{"role":"user","content":"当前任务已经结束的情况下还是显示思考中"},"sessionId":"session-1","cwd":"/Users/rinka/.claude"}"#,
            #"{"type":"assistant","timestamp":"2026-05-06T12:00:02Z","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"swift build"}},{"type":"text","text":"已修复状态显示和跳转问题。"}]},"sessionId":"session-1","cwd":"/Users/rinka/.claude"}"#,
            #"{"type":"system","subtype":"stop_hook_summary","timestamp":"2026-05-06T12:00:03Z","sessionId":"session-1","cwd":"/Users/rinka/.claude"}"#
        ].joined(separator: "\n")
        try claudeTranscript.write(to: claudeTranscriptURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: claudeTranscriptURL) }
        
        let transcriptReader = ConversationTranscriptReader()
        let claudeSnapshot = transcriptReader.loadSnapshot(from: claudeTranscriptURL, source: .claudeCode)
        XCTAssertTrue(claudeSnapshot?.lastUserMessage == "当前任务已经结束的情况下还是显示思考中", "Claude transcript user message parsed")
        XCTAssertTrue(claudeSnapshot?.lastAssistantMessage == "已修复状态显示和跳转问题。", "Claude transcript assistant message parsed")
        XCTAssertTrue(claudeSnapshot?.activities.contains(where: { $0.title == "工具调用" && $0.detail == "Bash" }) == true, "Claude transcript tool call parsed")
        XCTAssertTrue(claudeSnapshot?.isComplete == true, "Claude transcript completion parsed")
        XCTAssertTrue(claudeSnapshot?.completedAt != nil, "Claude transcript completion timestamp parsed")
        XCTAssertTrue((claudeSnapshot?.latestActiveAt ?? .distantFuture) < (claudeSnapshot?.completedAt ?? .distantPast), "Claude transcript active timestamp precedes completion")
        
        let displaySession = AgentSession(
            id: "session-1",
            title: ".claude",
            prompt: ".claude",
            source: .claudeCode,
            workspace: "/Users/rinka/.claude",
            terminal: "Claude",
            updatedAt: Date(),
            status: .done,
            activity: claudeSnapshot?.activities ?? [],
            approval: nil,
            question: nil,
            subagents: [],
            lastAssistantMessage: claudeSnapshot?.lastAssistantMessage,
            lastUserMessage: claudeSnapshot?.lastUserMessage,
            usage: nil
        )
        let display = SessionDisplaySnapshot(session: displaySession)
        XCTAssertTrue(display.title.hasPrefix("当前任务已经结束"), "Low value Claude title falls back to user task")
        XCTAssertTrue(display.primaryLine.contains("AI：已修复状态显示"), "Display snapshot prioritizes assistant message")
        XCTAssertTrue(display.signals.contains(where: { $0.text == "Bash" }), "Display snapshot exposes tool signal")
        XCTAssertTrue(display.confidence == .transcript, "Display confidence uses transcript data")
        XCTAssertTrue(display.statusText == "已完成", "Transcript backed completion stays certain")
        
        let inferredDoneSession = AgentSession(
            id: "inferred",
            title: "Codex",
            prompt: "Codex",
            source: .codexDesktop,
            workspace: "",
            terminal: "Codex",
            updatedAt: Date(),
            status: .done,
            activity: [],
            approval: nil,
            question: nil,
            subagents: [],
            lastAssistantMessage: nil,
            lastUserMessage: nil,
            usage: nil
        )
        let inferredDisplay = SessionDisplaySnapshot(session: inferredDoneSession)
        XCTAssertTrue(inferredDisplay.confidence == .inferred, "Empty session uses inferred confidence")
        XCTAssertTrue(inferredDisplay.statusText == "可能已完成", "Inferred done status is conservative")

        var doneOnlySubagentSession = inferredDoneSession
        doneOnlySubagentSession.subagents = [
            SubagentItem(id: "child-1", name: "Gibbs", status: .done, detail: "worker"),
            SubagentItem(id: "child-2", name: "Lagrange", status: .done, detail: "worker")
        ]
        let doneOnlySubagentDisplay = SessionDisplaySnapshot(session: doneOnlySubagentSession)
        XCTAssertFalse(
            doneOnlySubagentDisplay.signals.contains(where: { $0.text.contains("子智能体") }),
            "Completed historical subagents do not show as current work"
        )

        var activeSubagentSession = inferredDoneSession
        activeSubagentSession.subagents = [
            SubagentItem(id: "child-1", name: "Gibbs", status: .done, detail: "worker"),
            SubagentItem(id: "child-2", name: "Lagrange", status: .thinking, detail: "worker")
        ]
        let activeSubagentDisplay = SessionDisplaySnapshot(session: activeSubagentSession)
        XCTAssertTrue(
            activeSubagentDisplay.signals.contains(where: { $0.text == "1/2 子智能体" }),
            "Only active subagents contribute to the badge count"
        )
        
        func dashboardPolicySession(
            id: String,
            status: SessionStatus,
            updatedAt: Date,
            source: AgentSource = .codexDesktop
        ) -> AgentSession {
            AgentSession(
                id: id,
                title: id,
                prompt: id,
                source: source,
                workspace: "/tmp/\(id)",
                terminal: "Codex",
                updatedAt: updatedAt,
                status: status,
                activity: [],
                approval: nil,
                question: nil,
                subagents: [],
                lastAssistantMessage: nil,
                lastUserMessage: nil,
                usage: nil
            )
        }
        
        let dashboardPolicyNow = Date()
        let staleDone = dashboardPolicySession(
            id: "stale-done",
            status: .done,
            updatedAt: dashboardPolicyNow.addingTimeInterval(-3 * 60)
        )
        let recentDone = dashboardPolicySession(
            id: "recent-done",
            status: .done,
            updatedAt: dashboardPolicyNow.addingTimeInterval(-60)
        )
        let recentFailed = dashboardPolicySession(
            id: "recent-failed",
            status: .failed,
            updatedAt: dashboardPolicyNow.addingTimeInterval(-5 * 60)
        )
        let staleFailed = dashboardPolicySession(
            id: "stale-failed",
            status: .failed,
            updatedAt: dashboardPolicyNow.addingTimeInterval(-11 * 60)
        )
        let staleActive = dashboardPolicySession(
            id: "stale-active",
            status: .thinking,
            updatedAt: dashboardPolicyNow.addingTimeInterval(-121 * 60)
        )
        let visiblePolicySessions = DashboardSessionPolicy.visibleSessions(
            from: [staleDone, recentDone, recentFailed, staleFailed, staleActive],
            now: dashboardPolicyNow
        )
        XCTAssertTrue(!visiblePolicySessions.contains(where: { $0.id == "stale-done" }), "Old completed sessions are hidden from dashboard")
        XCTAssertTrue(visiblePolicySessions.contains(where: { $0.id == "recent-done" }), "Just completed sessions stay briefly visible")
        XCTAssertTrue(visiblePolicySessions.contains(where: { $0.id == "recent-failed" }), "Recent failures stay visible for follow-up")
        XCTAssertTrue(!visiblePolicySessions.contains(where: { $0.id == "stale-failed" }), "Old failures are hidden from dashboard")
        XCTAssertTrue(!visiblePolicySessions.contains(where: { $0.id == "stale-active" }), "Very old active-looking sessions are hidden from dashboard")
        XCTAssertTrue(
            !DashboardSessionPolicy.hasActiveTask(in: [recentDone], now: dashboardPolicyNow),
            "Recent completed sessions do not keep the compact pill expanded"
        )
        let activeDashboardTask = dashboardPolicySession(
            id: "active-dashboard-task",
            status: .runningTool,
            updatedAt: dashboardPolicyNow
        )
        XCTAssertTrue(
            DashboardSessionPolicy.hasActiveTask(in: [recentDone, activeDashboardTask], now: dashboardPolicyNow),
            "Active sessions keep the compact pill expanded"
        )
        
        let sixRecentSessions = (0..<6).map { index in
            dashboardPolicySession(
                id: "recent-\(index)",
                status: .thinking,
                updatedAt: dashboardPolicyNow.addingTimeInterval(TimeInterval(-index))
            )
        }
        XCTAssertTrue(
            DashboardSessionPolicy.visibleSessions(from: sixRecentSessions, now: dashboardPolicyNow).count == 5,
            "Dashboard caps visible sessions at five"
        )
        XCTAssertEqual(DashboardSessionPolicy.configuredVisibleSessionLimit(1), 3, "Configured dashboard limit has a readable lower bound")
        XCTAssertEqual(DashboardSessionPolicy.configuredVisibleSessionLimit(4), 4, "Configured dashboard limit preserves valid values")
        XCTAssertEqual(DashboardSessionPolicy.configuredVisibleSessionLimit(9), 5, "Configured dashboard limit caps at five")
        XCTAssertEqual(
            DashboardSessionPolicy.visibleSessions(from: sixRecentSessions, limit: 3, now: dashboardPolicyNow).count,
            3,
            "Dashboard honors a lower configured visible-session limit"
        )
        let newestUnsorted = dashboardPolicySession(
            id: "newest-unsorted",
            status: .thinking,
            updatedAt: dashboardPolicyNow.addingTimeInterval(-1),
            source: .codexDesktop
        )
        let olderUnsortedSameSource = dashboardPolicySession(
            id: "older-unsorted-same-source",
            status: .thinking,
            updatedAt: dashboardPolicyNow.addingTimeInterval(-30),
            source: .codexDesktop
        )
        let middleUnsortedOtherSource = dashboardPolicySession(
            id: "middle-unsorted-other-source",
            status: .thinking,
            updatedAt: dashboardPolicyNow.addingTimeInterval(-10),
            source: .claudeCode
        )
        let unsortedVisible = DashboardSessionPolicy.visibleSessions(
            from: [olderUnsortedSameSource, middleUnsortedOtherSource, newestUnsorted],
            now: dashboardPolicyNow
        )
        XCTAssertEqual(
            unsortedVisible.map(\.id),
            ["newest-unsorted", "middle-unsorted-other-source", "older-unsorted-same-source"],
            "Dashboard policy owns recency ordering instead of relying on callers to pre-sort sessions"
        )
        
        let codexTranscriptURL = tempDirectory.appendingPathComponent("vibelsland-codex-\(UUID().uuidString).jsonl")
        let codexTranscript = [
            #"{"timestamp":"2026-05-06T12:01:00Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"优化浮岛显示信息"}]}}"#,
            #"{"timestamp":"2026-05-06T12:01:01Z","type":"response_item","payload":{"type":"function_call","name":"exec_command","arguments":"{}","call_id":"call_1"}}"#,
            #"{"timestamp":"2026-05-06T12:01:02Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"已改成摘要显示。"}]}}"#,
            #"{"timestamp":"2026-05-06T12:01:03Z","type":"event_msg","payload":{"type":"task_complete","last_agent_message":"已改成摘要显示。","duration_ms":1200}}"#
        ].joined(separator: "\n")
        try codexTranscript.write(to: codexTranscriptURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: codexTranscriptURL) }
        
        let codexSnapshot = transcriptReader.loadSnapshot(from: codexTranscriptURL, source: .codexCli)
        XCTAssertTrue(codexSnapshot?.lastUserMessage == "优化浮岛显示信息", "Codex transcript user message parsed")
        XCTAssertTrue(codexSnapshot?.lastAssistantMessage == "已改成摘要显示。", "Codex transcript assistant message parsed")
        XCTAssertTrue(codexSnapshot?.activities.contains(where: { $0.title == "工具调用" && $0.detail == "exec_command" }) == true, "Codex transcript tool call parsed")
        XCTAssertTrue(codexSnapshot?.isComplete == true, "Codex transcript completion parsed")

        let abortedTranscriptURL = tempDirectory.appendingPathComponent("vibelsland-aborted-\(UUID().uuidString).jsonl")
        let abortedTranscript = [
            #"{"timestamp":"2026-05-06T12:02:00.123Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"运行一个长任务"}]}}"#,
            #"{"timestamp":"2026-05-06T12:02:01.456Z","type":"event_msg","payload":{"type":"turn_aborted","reason":"user_cancelled"}}"#
        ].joined(separator: "\n")
        try abortedTranscript.write(to: abortedTranscriptURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: abortedTranscriptURL) }

        let abortedSnapshot = transcriptReader.loadSnapshot(from: abortedTranscriptURL, source: .codexCli)
        XCTAssertFalse(abortedSnapshot?.isComplete == true, "Aborted Codex turns are not displayed as completed")
        XCTAssertTrue(abortedSnapshot?.latestActiveAt != nil, "Fractional transcript timestamps are parsed for stale-completion protection")
        
        let duplicateDate = Date()
        let codexCliShadow = AgentSession(
            id: "codex-cli-shadow",
            title: "files-mentioned-by-the-user-memory",
            prompt: "files-mentioned-by-the-user-memory",
            source: .codexCli,
            workspace: "/Users/rinka/codexprojects/files-mentioned-by-the-user-memory",
            terminal: "Codex",
            updatedAt: duplicateDate,
            status: .done,
            activity: [
                ActivityItem(symbol: "wrench.and.screwdriver", title: "工具调用", detail: "exec_command", date: duplicateDate)
            ],
            approval: nil,
            question: nil,
            subagents: [],
            lastAssistantMessage: "结论：Codex 的 memory 确实有指定格式",
            lastUserMessage: "当前这个 MEMORY.md 需要检查",
            usage: UsageSnapshot(lastTokens: 109_500, totalTokens: 157_200_000, contextWindow: 258_400)
        )
        let codexDesktopPrimary = AgentSession(
            id: "codex-desktop-thread",
            title: "files-mentioned-by-the-user-memory",
            prompt: "files-mentioned-by-the-user-memory",
            source: .codexDesktop,
            workspace: "/Users/rinka/codexprojects/files-mentioned-by-the-user-memory",
            terminal: "Codex",
            updatedAt: duplicateDate.addingTimeInterval(-4),
            status: .done,
            activity: [
                ActivityItem(symbol: "wrench.and.screwdriver", title: "工具调用", detail: "exec_command", date: duplicateDate.addingTimeInterval(-4))
            ],
            approval: nil,
            question: nil,
            subagents: [],
            lastAssistantMessage: "结论：Codex 的 memory 确实有指定格式",
            lastUserMessage: "当前这个 MEMORY.md 需要检查",
            usage: nil
        )
        let deduped = SessionDeduper.compact([codexCliShadow, codexDesktopPrimary], selectedSessionID: codexCliShadow.id)
        XCTAssertTrue(deduped.sessions.count == 1, "Codex CLI shadow is merged into Desktop session")
        XCTAssertTrue(deduped.sessions.first?.source == .codexDesktop, "Codex Desktop is preferred for duplicate task")
        XCTAssertTrue(deduped.selectedSessionID == codexDesktopPrimary.id, "Duplicate selected session remaps to Desktop")
        XCTAssertTrue(deduped.sessions.first?.usage?.lastTokens == 109_500, "Merged Desktop session keeps CLI usage data")

        let nestedCliCall = AgentSession(
            id: "nested-cli-call",
            title: "vibelsland free",
            prompt: "vibelsland free",
            source: .codexCli,
            workspace: "/Users/rinka/codexprojects/files-mentioned-by-the-user-memory",
            terminal: "Codex",
            updatedAt: duplicateDate.addingTimeInterval(20),
            status: .done,
            activity: [
                ActivityItem(symbol: "wrench.and.screwdriver", title: "call_nested", detail: "内部 CLI 调用", date: duplicateDate.addingTimeInterval(20))
            ],
            approval: nil,
            question: nil,
            subagents: [],
            lastAssistantMessage: "内部子任务完成",
            lastUserMessage: "vibelsland free",
            usage: UsageSnapshot(lastTokens: 7_000, totalTokens: 7_000, contextWindow: 258_400)
        )
        let nestedDeduped = SessionDeduper.compact([codexDesktopPrimary, nestedCliCall], selectedSessionID: nestedCliCall.id)
        XCTAssertTrue(nestedDeduped.sessions.count == 1, "Nested Codex CLI calls inside Desktop tasks are hidden")
        XCTAssertTrue(nestedDeduped.sessions.first?.id == codexDesktopPrimary.id, "Desktop task remains the only visible task")
        XCTAssertTrue(nestedDeduped.sessions.first?.usage == nil, "Nested CLI usage is not merged into the Desktop task")
        XCTAssertTrue(
            SessionDeduper.sameWorkspace(
                "/Users/rinka/codexprojects/files-mentioned-by-the-user-memory/subtask",
                "/Users/rinka/codexprojects/files-mentioned-by-the-user-memory"
            ),
            "Codex internal CLI calls from child directories stay associated with the Desktop task"
        )
        var nestedCliFromChildDirectory = nestedCliCall
        nestedCliFromChildDirectory.id = "nested-cli-child-dir"
        nestedCliFromChildDirectory.workspace = "/Users/rinka/codexprojects/files-mentioned-by-the-user-memory/subtask"
        let childDirectoryDeduped = SessionDeduper.compact([codexDesktopPrimary, nestedCliFromChildDirectory], selectedSessionID: nestedCliFromChildDirectory.id)
        XCTAssertTrue(childDirectoryDeduped.sessions.count == 1, "Nested Codex CLI calls from child directories are hidden")

        var structuredNestedCli = nestedCliCall
        structuredNestedCli.id = "structured-desktop-child"
        structuredNestedCli.workspace = "/Users/rinka/codexprojects/files-mentioned-by-the-user-memory/subtask"
        structuredNestedCli.activity = [
            ActivityItem(symbol: "wrench.and.screwdriver", title: "exec_command", detail: "plain command", date: duplicateDate.addingTimeInterval(20))
        ]
        structuredNestedCli.codexSessionStartSource = "codex_desktop_subagent"
        let structuredNestedDeduped = SessionDeduper.compact([codexDesktopPrimary, structuredNestedCli], selectedSessionID: structuredNestedCli.id)
        XCTAssertTrue(structuredNestedDeduped.sessions.count == 1, "Structured Codex desktop-derived CLI sessions are hidden without relying on display text")

        var lateStructuredNestedCli = structuredNestedCli
        lateStructuredNestedCli.id = "late-structured-desktop-child"
        lateStructuredNestedCli.updatedAt = duplicateDate.addingTimeInterval(7_200)
        let lateStructuredDeduped = SessionDeduper.compact([codexDesktopPrimary, lateStructuredNestedCli], selectedSessionID: lateStructuredNestedCli.id)
        XCTAssertTrue(lateStructuredDeduped.sessions.count == 1, "Explicit Desktop-derived CLI sessions stay hidden even after a long parent task")

        var broadSourceCli = structuredNestedCli
        broadSourceCli.id = "broad-source-cli"
        broadSourceCli.codexSessionStartSource = "terminal_app"
        let broadSourceDeduped = SessionDeduper.compact([codexDesktopPrimary, broadSourceCli], selectedSessionID: broadSourceCli.id)
        XCTAssertTrue(broadSourceDeduped.sessions.count == 2, "Broad app-like source text is not enough to hide manual CLI work")

        var lateStructuredApproval = lateStructuredNestedCli
        lateStructuredApproval.id = "late-structured-approval"
        lateStructuredApproval.status = .waitingApproval
        lateStructuredApproval.approval = ApprovalRequest(
            id: "approval-late",
            source: .codexCli,
            title: "Codex CLI 请求权限",
            detail: "npm test",
            tool: "Bash",
            workspace: "/Users/rinka/codexprojects/files-mentioned-by-the-user-memory/subtask",
            availableDecisions: [.accept, .decline, .cancel],
            suggestedSessionAllow: false,
            supportsCancel: true,
            createdAt: duplicateDate.addingTimeInterval(7_200)
        )
        let lateStructuredApprovalDeduped = SessionDeduper.compact([codexDesktopPrimary, lateStructuredApproval], selectedSessionID: lateStructuredApproval.id)
        XCTAssertTrue(lateStructuredApprovalDeduped.sessions.count == 2, "Nested CLI approvals remain visible even when the CLI session is Desktop-derived")

        var independentCliFromChildDirectory = nestedCliCall
        independentCliFromChildDirectory.id = "manual-cli-child-dir"
        independentCliFromChildDirectory.title = "manual child task"
        independentCliFromChildDirectory.prompt = "manual child task"
        independentCliFromChildDirectory.workspace = "/Users/rinka/codexprojects/files-mentioned-by-the-user-memory/subtask"
        independentCliFromChildDirectory.activity = [
            ActivityItem(symbol: "wrench.and.screwdriver", title: "exec_command", detail: "manual command", date: duplicateDate.addingTimeInterval(20))
        ]
        independentCliFromChildDirectory.lastAssistantMessage = "手动 CLI 任务完成"
        independentCliFromChildDirectory.lastUserMessage = "manual child task"
        let independentDeduped = SessionDeduper.compact([codexDesktopPrimary, independentCliFromChildDirectory], selectedSessionID: independentCliFromChildDirectory.id)
        XCTAssertTrue(independentDeduped.sessions.count == 2, "Independent Codex CLI work in a child directory remains visible")

        var cliApproval = nestedCliCall
        cliApproval.id = "nested-cli-approval"
        cliApproval.status = .waitingApproval
        cliApproval.approval = ApprovalRequest(
            id: "approval",
            source: .codexCli,
            title: "Codex CLI 请求权限",
            detail: "npm test",
            tool: "Bash",
            workspace: cliApproval.workspace,
            availableDecisions: [.accept, .decline],
            suggestedSessionAllow: false,
            supportsCancel: false,
            createdAt: duplicateDate
        )
        let approvalDeduped = SessionDeduper.compact([codexDesktopPrimary, cliApproval], selectedSessionID: cliApproval.id)
        XCTAssertTrue(approvalDeduped.sessions.count == 2, "Nested CLI approvals stay visible so the user can respond")
    }

    @Test func testSessionTimelineSortsEventsAndTracksToolLifecycle() {
        let baseDate = Date(timeIntervalSince1970: 1_800_000_000)
        let toolStart = sessionEvent(
            kind: .tool,
            timestamp: baseDate.addingTimeInterval(10),
            payload: ["hook_event_name": .string("PreToolUse")]
        )
        let userPrompt = sessionEvent(
            kind: .prompt,
            timestamp: baseDate,
            payload: ["hook_event_name": .string("UserPromptSubmit")]
        )
        let toolEnd = sessionEvent(
            kind: .tool,
            timestamp: baseDate.addingTimeInterval(20),
            payload: ["hook_event_name": .string("PostToolUse")]
        )

        var timeline = SessionTimeline(events: [toolStart, userPrompt])
        XCTAssertEqual(timeline.events.map(\.id), ["prompt", "tool"], "Timeline keeps events sorted by timestamp")
        XCTAssertEqual(timeline.status, .runningTool)
        XCTAssertEqual(timeline.resolutionState, .active)
        XCTAssertEqual(SessionStateReducer.status(for: timeline), .runningTool)

        timeline.append(toolEnd)
        XCTAssertEqual(timeline.status, .thinking, "Tool end returns the session to thinking, not completed")
        XCTAssertEqual(timeline.resolutionState, .active)
        XCTAssertEqual(SessionStateReducer.status(after: .runningTool, event: toolEnd), .thinking)
    }

    @Test func testToolEndDisplayDoesNotLookCompleted() {
        let baseDate = Date(timeIntervalSince1970: 1_800_000_050)
        let toolStart = sessionEvent(
            id: "tool-start",
            kind: .tool,
            timestamp: baseDate,
            payload: ["hook_event_name": .string("PreToolUse")]
        )
        let toolEnd = sessionEvent(
            id: "tool-end",
            kind: .tool,
            timestamp: baseDate.addingTimeInterval(15),
            payload: ["hook_event_name": .string("PostToolUse")]
        )
        let timeline = SessionTimeline(events: [toolStart, toolEnd])
        let session = AgentSession(
            id: "active-after-tool-end",
            title: "vibelsland free",
            prompt: "继续修复",
            source: .codexCli,
            workspace: "/Users/rinka/codexprojects/vibelsland free",
            terminal: "Codex",
            updatedAt: baseDate.addingTimeInterval(15),
            status: timeline.status,
            activity: [
                ActivityItem(
                    symbol: "wrench.and.screwdriver",
                    title: "工具调用",
                    detail: "Bash",
                    date: baseDate.addingTimeInterval(15)
                )
            ],
            approval: nil,
            question: nil,
            subagents: [],
            lastAssistantMessage: "我继续处理这个问题。",
            lastUserMessage: "工具调用后还在处理",
            usage: nil
        )
        let display = SessionDisplaySnapshot(session: session)

        XCTAssertEqual(timeline.resolutionState, .active)
        XCTAssertFalse(["已完成", "可能已完成"].contains(display.statusText), "Tool completion must not be shown as task completion")
        XCTAssertFalse(display.primaryLine.contains("已完成"), "The visible card body must not imply the full turn is complete")
    }

    @Test func testSessionTimelineKeepsAssistantContinuationActive() {
        let baseDate = Date(timeIntervalSince1970: 1_800_000_100)
        let toolStart = sessionEvent(
            id: "tool-start",
            kind: .tool,
            timestamp: baseDate.addingTimeInterval(-1),
            payload: ["hook_event_name": .string("PreToolUse")]
        )
        let toolEnd = sessionEvent(
            id: "tool-end",
            kind: .tool,
            timestamp: baseDate,
            payload: ["hook_event_name": .string("PostToolUse")]
        )
        let assistantContinues = sessionEvent(
            id: "assistant-continues",
            kind: .status,
            timestamp: baseDate.addingTimeInterval(1),
            payload: [
                "type": .string("agent_message"),
                "message": .string("继续处理")
            ]
        )

        let timeline = SessionTimeline(events: [toolStart, toolEnd, assistantContinues])
        XCTAssertEqual(timeline.status, .thinking)
        XCTAssertEqual(timeline.resolutionState, .active)
        XCTAssertEqual(SessionStateReducer.resolutionState(for: timeline.events), .active)
    }

    @Test func testSessionTimelineResolvesCompletionAndFailure() {
        let baseDate = Date(timeIntervalSince1970: 1_800_000_200)
        let completion = sessionEvent(
            kind: .status,
            timestamp: baseDate,
            payload: ["codex_event_type": .string("task_complete")]
        )
        let failure = sessionEvent(
            kind: .status,
            timestamp: baseDate,
            payload: ["status": .string("failed")]
        )

        let completedTimeline = SessionTimeline(events: [completion])
        XCTAssertEqual(completedTimeline.status, .done)
        XCTAssertEqual(completedTimeline.resolutionState, .completed)

        let failedTimeline = SessionTimeline(events: [failure])
        XCTAssertEqual(failedTimeline.status, .failed)
        XCTAssertEqual(failedTimeline.resolutionState, .failed)
    }

    @Test func testSessionTimelineReopensAfterNewPromptButPreservesLateNotificationCompletion() {
        let baseDate = Date(timeIntervalSince1970: 1_800_000_300)
        let completion = sessionEvent(
            id: "complete",
            kind: .status,
            timestamp: baseDate,
            payload: ["codex_event_type": .string("task_complete")]
        )
        let newPrompt = sessionEvent(
            id: "new-prompt",
            kind: .prompt,
            timestamp: baseDate.addingTimeInterval(1),
            payload: ["hook_event_name": .string("UserPromptSubmit")]
        )
        let lateNotification = sessionEvent(
            id: "late-notification",
            kind: .notification,
            timestamp: baseDate.addingTimeInterval(1),
            payload: ["message": .string("后台同步")]
        )

        let reopenedTimeline = SessionTimeline(events: [completion, newPrompt])
        XCTAssertEqual(reopenedTimeline.status, .thinking)
        XCTAssertEqual(reopenedTimeline.resolutionState, .active)

        let preservedTimeline = SessionTimeline(events: [completion, lateNotification])
        XCTAssertEqual(preservedTimeline.status, .done)
        XCTAssertEqual(preservedTimeline.resolutionState, .completed)
    }

    @Test func testStaleTranscriptCompletionDoesNotOverrideNewPrompt() {
        let baseDate = Date(timeIntervalSince1970: 1_800_001_000)
        let prompt = AgentEvent(
            id: "new-claude-prompt",
            source: .claudeCode,
            kind: .prompt,
            timestamp: baseDate,
            payload: .object(["hook_event_name": .string("UserPromptSubmit")])
        )
        let staleTranscript = AgentTranscriptSnapshot(
            activities: [],
            usage: nil,
            lastAssistantMessage: "上一轮回答",
            lastUserMessage: "上一轮任务",
            isComplete: true,
            completedAt: baseDate.addingTimeInterval(-60),
            latestActiveAt: baseDate.addingTimeInterval(-70)
        )

        XCTAssertFalse(SessionStateReducer.shouldApplyTranscriptCompletion(staleTranscript, to: prompt))
        XCTAssertFalse(SessionStateReducer.shouldApplyTranscriptContent(staleTranscript, to: prompt))
        XCTAssertEqual(SessionStateReducer.status(after: .done, event: prompt), .thinking)
    }

    @Test func testCurrentTranscriptContentAppliesToNewPrompt() {
        let baseDate = Date(timeIntervalSince1970: 1_800_001_050)
        let prompt = AgentEvent(
            id: "current-claude-prompt",
            source: .claudeCode,
            kind: .prompt,
            timestamp: baseDate,
            payload: .object([
                "hook_event_name": .string("UserPromptSubmit"),
                "prompt": .string("对比和功能")
            ])
        )
        let currentTranscript = AgentTranscriptSnapshot(
            activities: [],
            usage: nil,
            lastAssistantMessage: nil,
            lastUserMessage: "对比和功能",
            isComplete: false,
            completedAt: baseDate.addingTimeInterval(-60),
            latestActiveAt: baseDate.addingTimeInterval(-1)
        )

        XCTAssertTrue(SessionStateReducer.shouldApplyTranscriptContent(currentTranscript, to: prompt))
    }

    @Test func testFreshTranscriptCompletionCanResolveSession() {
        let baseDate = Date(timeIntervalSince1970: 1_800_001_100)
        let stop = AgentEvent(
            id: "claude-stop",
            source: .claudeCode,
            kind: .session,
            timestamp: baseDate,
            payload: .object(["hook_event_name": .string("Stop")])
        )
        let freshTranscript = AgentTranscriptSnapshot(
            activities: [],
            usage: nil,
            lastAssistantMessage: "已完成",
            lastUserMessage: "当前任务",
            isComplete: true,
            completedAt: baseDate.addingTimeInterval(1),
            latestActiveAt: baseDate.addingTimeInterval(-1)
        )

        XCTAssertTrue(SessionStateReducer.shouldApplyTranscriptCompletion(freshTranscript, to: stop))
    }

    @Test func testTranscriptCompletionDoesNotOverrideFailureEvent() {
        let baseDate = Date(timeIntervalSince1970: 1_800_001_150)
        let failure = AgentEvent(
            id: "codex-aborted",
            source: .codexCli,
            kind: .status,
            timestamp: baseDate,
            payload: .object(["codex_event_type": .string("turn_aborted")])
        )
        let oldCompleteTranscript = AgentTranscriptSnapshot(
            activities: [],
            usage: nil,
            lastAssistantMessage: "上一轮已完成",
            lastUserMessage: "上一轮任务",
            isComplete: true,
            completedAt: baseDate.addingTimeInterval(-20),
            latestActiveAt: baseDate.addingTimeInterval(-21)
        )

        XCTAssertFalse(
            SessionStateReducer.shouldApplyTranscriptCompletion(oldCompleteTranscript, to: failure),
            "Failed or aborted events must not be overwritten by stale transcript completion"
        )
        XCTAssertEqual(SessionStateReducer.status(after: .thinking, event: failure), .failed)
    }

    @Test func testApprovalResolutionStateTextAndTerminalStates() {
        XCTAssertEqual(ApprovalResolutionState.pending.title, "等待审批")
        XCTAssertEqual(ApprovalResolutionState.resolving.title, "正在返回审批")
        XCTAssertEqual(ApprovalResolutionState.accepted.title, "已允许")
        XCTAssertEqual(ApprovalResolutionState.declined.title, "已拒绝")
        XCTAssertEqual(ApprovalResolutionState.cancelled.title, "已取消")
        XCTAssertEqual(ApprovalResolutionState.timedOut.title, "审批已超时")
        XCTAssertEqual(ApprovalResolutionState.sendFailed.title, "回传失败")
        XCTAssertEqual(ApprovalResolutionState.disconnected.title, "连接断开")

        XCTAssertFalse(ApprovalResolutionState.pending.isTerminal)
        XCTAssertFalse(ApprovalResolutionState.resolving.isTerminal)
        XCTAssertTrue(ApprovalResolutionState.accepted.isTerminal)
        XCTAssertTrue(ApprovalResolutionState.declined.isTerminal)
        XCTAssertTrue(ApprovalResolutionState.cancelled.isTerminal)
        XCTAssertTrue(ApprovalResolutionState.timedOut.isTerminal)
        XCTAssertTrue(ApprovalResolutionState.sendFailed.isTerminal)
        XCTAssertTrue(ApprovalResolutionState.disconnected.isTerminal)
    }

    @Test func testApprovalTerminalStatesDisplayExplicitStatus() {
        let cancelled = SessionDisplaySnapshot(session: approvalDisplaySession(state: .cancelled))
        XCTAssertEqual(cancelled.statusText, "已取消")
        XCTAssertEqual(cancelled.primaryLine, "已取消")

        let timedOut = SessionDisplaySnapshot(session: approvalDisplaySession(state: .timedOut, expired: true))
        XCTAssertEqual(timedOut.statusText, "审批已超时")
        XCTAssertEqual(timedOut.primaryLine, "审批已超时")

        let disconnected = SessionDisplaySnapshot(session: approvalDisplaySession(state: .disconnected))
        XCTAssertEqual(disconnected.statusText, "连接断开")
        XCTAssertEqual(disconnected.primaryLine, "连接断开")
    }

    @Test func testCodexThreadLinkPolicyUsesExplicitThreadID() {
        let cliNonUUID = linkPolicySession(
            id: "display-session-id",
            source: .codexCli,
            threadID: "thread-non-uuid"
        )
        XCTAssertEqual(
            CodexThreadLinkPolicy.threadID(for: cliNonUUID),
            "thread-non-uuid",
            "Codex CLI deep links use explicit thread id even when it is not a UUID"
        )

        let cliLegacyUUID = linkPolicySession(
            id: "123E4567-E89B-12D3-A456-426614174000",
            source: .codexCli
        )
        XCTAssertEqual(
            CodexThreadLinkPolicy.threadID(for: cliLegacyUUID),
            "123E4567-E89B-12D3-A456-426614174000",
            "Older UUID-backed Codex CLI sessions still deep link"
        )

        let cliWorkspaceFallback = linkPolicySession(
            id: "codexCli-/tmp/work",
            source: .codexCli
        )
        XCTAssertEqual(
            CodexThreadLinkPolicy.threadID(for: cliWorkspaceFallback),
            nil,
            "Synthetic workspace fallback ids are not treated as Codex thread ids"
        )

        let desktop = linkPolicySession(
            id: "codex-desktop-thread-1",
            source: .codexDesktop
        )
        XCTAssertEqual(CodexThreadLinkPolicy.threadID(for: desktop), "thread-1")
        XCTAssertEqual(CodexThreadLinkPolicy.deepLink(for: "thread-1"), "codex://threads/thread-1")
    }

    @Test func testSessionOpenPolicyRoutesCardsToExpectedTargets() {
        let desktop = linkPolicySession(
            id: "codex-desktop-thread-1",
            source: .codexDesktop
        )
        XCTAssertEqual(
            SessionOpenPolicy.action(for: desktop),
            .openCodexThread(
                threadID: "thread-1",
                logNamespace: "codex.desktop",
                errorMessage: "无法跳转到 Codex 对话"
            ),
            "Codex Desktop cards deep link to their thread instead of only selecting the row"
        )

        let cliExplicitThread = linkPolicySession(
            id: "display-id",
            source: .codexCli,
            threadID: "thread-non-uuid"
        )
        XCTAssertEqual(
            SessionOpenPolicy.action(for: cliExplicitThread),
            .openCodexThread(
                threadID: "thread-non-uuid",
                logNamespace: "codex.cli",
                errorMessage: "无法跳转到 Codex CLI 会话"
            ),
            "Codex CLI cards use explicit non-UUID thread ids from hook payloads"
        )

        let cliWithoutThread = linkPolicySession(
            id: "workspace-fallback",
            source: .codexCli
        )
        XCTAssertEqual(
            SessionOpenPolicy.action(for: cliWithoutThread),
            .focusApplication(.codexCli),
            "Codex CLI sessions without a real thread id still focus Codex instead of failing silently"
        )

        let claudeUUID = linkPolicySession(
            id: "123E4567-E89B-12D3-A456-426614174000",
            source: .claudeCode
        )
        XCTAssertEqual(
            SessionOpenPolicy.action(for: claudeUUID),
            .focusClaudeCodeTerminal(sessionID: "123E4567-E89B-12D3-A456-426614174000"),
            "Claude CLI cards prefer the matching terminal process when the session id is usable"
        )

        let claudeSynthetic = linkPolicySession(
            id: "claude-/tmp/work",
            source: .claudeCode
        )
        XCTAssertEqual(
            SessionOpenPolicy.action(for: claudeSynthetic),
            .focusClaudeCodeTerminal(sessionID: nil),
            "Synthetic Claude ids focus a running Claude terminal without pretending to know the exact session"
        )

        let unknown = linkPolicySession(
            id: "unknown",
            source: .unknown
        )
        XCTAssertEqual(
            SessionOpenPolicy.action(for: unknown),
            .selectOnly,
            "Unknown cards are selectable but do not try to open an unrelated app"
        )
    }

    @Test func testClaudeTerminalFocusPolicyRequiresRealClaudeProcess() {
        XCTAssertEqual(
            ClaudeTerminalFocusPolicy.terminalBundleIdentifier(
                forSessionID: nil,
                processSnapshots: [
                    ProcessSnapshot(pid: 10, ppid: 1, arguments: "/Applications/Terminal.app/Contents/MacOS/Terminal"),
                    ProcessSnapshot(pid: 11, ppid: 10, arguments: "-zsh")
                ],
                runningAppsByPID: [10: "com.apple.Terminal"]
            ),
            nil,
            "A random running terminal should not be focused for an old Claude card when no Claude CLI process is present"
        )
    }

    @Test func testClaudeTerminalFocusPolicyFindsParentTerminal() {
        XCTAssertEqual(
            ClaudeTerminalFocusPolicy.terminalBundleIdentifier(
                forSessionID: nil,
                processSnapshots: [
                    ProcessSnapshot(pid: 10, ppid: 1, arguments: "/Applications/Terminal.app/Contents/MacOS/Terminal"),
                    ProcessSnapshot(pid: 11, ppid: 10, arguments: "-zsh"),
                    ProcessSnapshot(pid: 12, ppid: 11, arguments: "claude --dangerously-skip-permissions")
                ],
                runningAppsByPID: [10: "com.apple.Terminal"]
            ),
            "com.apple.Terminal",
            "Claude CLI cards should focus the terminal that owns the active Claude process"
        )
    }

    @Test func testClaudeTerminalFocusPolicyDoesNotFocusClaudeDesktopParent() {
        XCTAssertEqual(
            ClaudeTerminalFocusPolicy.terminalBundleIdentifier(
                forSessionID: nil,
                processSnapshots: [
                    ProcessSnapshot(pid: 20, ppid: 1, arguments: "/Applications/Claude.app/Contents/MacOS/Claude"),
                    ProcessSnapshot(pid: 21, ppid: 20, arguments: "claude --print")
                ],
                runningAppsByPID: [20: "com.anthropic.claudefordesktop"]
            ),
            nil,
            "Claude CLI cards must not jump to Claude Desktop when the process parent is not a supported terminal"
        )
    }

    @Test func testClaudeTerminalFocusPolicyPrefersMatchingSessionID() {
        XCTAssertEqual(
            ClaudeTerminalFocusPolicy.terminalBundleIdentifier(
                forSessionID: "target-session",
                processSnapshots: [
                    ProcessSnapshot(pid: 10, ppid: 1, arguments: "/Applications/Terminal.app/Contents/MacOS/Terminal"),
                    ProcessSnapshot(pid: 11, ppid: 10, arguments: "-zsh"),
                    ProcessSnapshot(pid: 12, ppid: 11, arguments: "claude old-session"),
                    ProcessSnapshot(pid: 30, ppid: 1, arguments: "/Applications/iTerm.app/Contents/MacOS/iTerm2"),
                    ProcessSnapshot(pid: 31, ppid: 30, arguments: "-zsh"),
                    ProcessSnapshot(pid: 32, ppid: 31, arguments: "node /opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/cli.js target-session")
                ],
                runningAppsByPID: [
                    10: "com.apple.Terminal",
                    30: "com.googlecode.iterm2"
                ]
            ),
            "com.googlecode.iterm2",
            "When a session id is available, jump to the terminal that owns that Claude process"
        )
    }

    @Test func testCodexOpenCommandPolicyForcesDeepLinkIntoCodexApp() {
        XCTAssertEqual(
            CodexOpenCommandPolicy.deepLinkArguments(
                bundleID: "com.openai.codex",
                deepLink: "codex://threads/thread-1"
            ),
            ["-b", "com.openai.codex", "codex://threads/thread-1"],
            "Codex thread deep links should be opened by the Codex app directly"
        )
        XCTAssertEqual(
            CodexOpenCommandPolicy.fallbackDeepLinkArguments("codex://threads/thread-1"),
            ["codex://threads/thread-1"]
        )
        XCTAssertEqual(
            CodexOpenCommandPolicy.focusArguments(bundleID: "com.openai.codex"),
            ["-b", "com.openai.codex"]
        )
    }

    @Test func testMenuBarOpenPanelDoesNotHideVisibleIsland() {
        XCTAssertEqual(
            MenuBarIslandActionPolicy.openPanelAction(windowExists: false, windowVisible: false),
            .createAndShow
        )
        XCTAssertEqual(
            MenuBarIslandActionPolicy.openPanelAction(windowExists: true, windowVisible: false),
            .restoreVisible
        )
        XCTAssertEqual(
            MenuBarIslandActionPolicy.openPanelAction(windowExists: true, windowVisible: true),
            .keepVisible,
            "Menu bar Open Panel should never act as a hide toggle"
        )
    }

    @Test func testSystemOverviewRestorePolicy() {
        let now = Date(timeIntervalSince1970: 1_800_001_250)

        XCTAssertEqual(
            SystemOverviewRestorePolicy.decision(
                force: true,
                now: now,
                minimumRestoreAt: now.addingTimeInterval(10),
                forceRestoreAt: nil,
                overviewLikelyVisible: true,
                frontmostBundleID: SystemOverviewRestorePolicy.dockBundleIdentifier
            ),
            .restore,
            "Explicit menu restore can recover an offscreen hidden island"
        )

        XCTAssertEqual(
            SystemOverviewRestorePolicy.decision(
                force: false,
                now: now,
                minimumRestoreAt: now.addingTimeInterval(1),
                forceRestoreAt: now.addingTimeInterval(-1),
                overviewLikelyVisible: false,
                frontmostBundleID: "com.openai.codex"
            ),
            .wait,
            "Minimum hidden duration prevents immediate flicker"
        )

        XCTAssertEqual(
            SystemOverviewRestorePolicy.decision(
                force: false,
                now: now,
                minimumRestoreAt: now.addingTimeInterval(-1),
                forceRestoreAt: nil,
                overviewLikelyVisible: false,
                frontmostBundleID: "com.openai.codex"
            ),
            .restore,
            "Island restores normally once overview is no longer visible"
        )

        XCTAssertEqual(
            SystemOverviewRestorePolicy.decision(
                force: false,
                now: now,
                minimumRestoreAt: now.addingTimeInterval(-2),
                forceRestoreAt: now.addingTimeInterval(-1),
                overviewLikelyVisible: true,
                frontmostBundleID: SystemOverviewRestorePolicy.dockBundleIdentifier
            ),
            .wait,
            "The island stays hidden while Mission Control itself is still frontmost"
        )

        XCTAssertEqual(
            SystemOverviewRestorePolicy.decision(
                force: false,
                now: now,
                minimumRestoreAt: now.addingTimeInterval(-2),
                forceRestoreAt: now.addingTimeInterval(-1),
                overviewLikelyVisible: true,
                frontmostBundleID: "com.openai.codex"
            ),
            .forceRestore,
            "A stale overview detection cannot hide the island forever after the user returns to an app"
        )
    }

    @Test func testAppRestartPolicyReopensAfterCurrentInstanceCanExit() {
        let command = AppRestartPolicy.command(
            bundlePath: "/Applications/>_ - island.app",
            environment: [:],
            currentProcessID: 1234
        )
        XCTAssertEqual(command?.executablePath, "/bin/sh")
        XCTAssertEqual(
            command?.arguments,
            [
                "-c",
                "source_pid=\"$1\"; shift; if [ -n \"$source_pid\" ]; then i=0; while kill -0 \"$source_pid\" 2>/dev/null && [ \"$i\" -lt 40 ]; do sleep 0.1; i=$((i + 1)); done; else sleep 0.35; fi; exec /usr/bin/open \"$@\"",
                "vibelsland-restart",
                "1234",
                "-n",
                "/Applications/>_ - island.app"
            ],
            "Restart waits for the old process to exit before reopening so the old and new floating UI do not overlap"
        )
        XCTAssertEqual(AppRestartPolicy.command(bundlePath: "  "), nil, "Restart refuses an empty app path")
    }

    @Test func testAppRestartPolicyPreservesVerificationEnvironment() {
        let command = AppRestartPolicy.command(
            bundlePath: "/Applications/>_ - island.app",
            environment: [
                "PATH": "/usr/bin",
                "VIBELSLAND_HOME": "/tmp/vibelsland-restart",
                "VIBELSLAND_ENABLE_VERIFICATION_ACTIONS": "1",
                "VIBELSLAND_CODEX_IPC_SOCKET": "   "
            ],
            currentProcessID: 9876
        )
        XCTAssertEqual(
            command?.arguments,
            [
                "-c",
                "source_pid=\"$1\"; shift; if [ -n \"$source_pid\" ]; then i=0; while kill -0 \"$source_pid\" 2>/dev/null && [ \"$i\" -lt 40 ]; do sleep 0.1; i=$((i + 1)); done; else sleep 0.35; fi; exec /usr/bin/open \"$@\"",
                "vibelsland-restart",
                "9876",
                "--env",
                "VIBELSLAND_HOME=/tmp/vibelsland-restart",
                "--env",
                "VIBELSLAND_ENABLE_VERIFICATION_ACTIONS=1",
                "-n",
                "/Applications/>_ - island.app"
            ],
            "Internal restart keeps only the app-specific verification overrides needed by isolated regression scripts"
        )
    }

    @Test func testSingleInstancePolicyFindsExistingBundleInstance() {
        let existing = AppInstanceSnapshot(
            processID: 200,
            bundleIdentifier: "free.vibelsland.macos",
            executableName: "VibelslandFree",
            bundleName: ">_ - island.app",
            localizedName: ">_ - island",
            isTerminated: false
        )
        let match = AppSingleInstancePolicy.existingInstance(
            currentProcessID: 300,
            currentBundleIdentifier: "free.vibelsland.macos",
            currentExecutableName: "VibelslandFree",
            currentBundleName: ">_ - island.app",
            runningApplications: [
                AppInstanceSnapshot(
                    processID: 300,
                    bundleIdentifier: "free.vibelsland.macos",
                    executableName: "VibelslandFree",
                    bundleName: ">_ - island.app",
                    localizedName: ">_ - island",
                    isTerminated: false
                ),
                existing
            ]
        )
        XCTAssertEqual(match, existing, "A second launch should hand off to the already running app")
    }

    @Test func testSingleInstancePolicyFindsExistingDebugExecutableInstance() {
        let existingDebugRun = AppInstanceSnapshot(
            processID: 200,
            bundleIdentifier: nil,
            executableName: "VibelslandFree",
            bundleName: nil,
            localizedName: "VibelslandFree",
            isTerminated: false
        )
        let match = AppSingleInstancePolicy.existingInstance(
            currentProcessID: 300,
            currentBundleIdentifier: "free.vibelsland.macos",
            currentExecutableName: "VibelslandFree",
            currentBundleName: ">_ - island.app",
            runningApplications: [
                existingDebugRun,
                AppInstanceSnapshot(
                    processID: 300,
                    bundleIdentifier: "free.vibelsland.macos",
                    executableName: "VibelslandFree",
                    bundleName: ">_ - island.app",
                    localizedName: ">_ - island",
                    isTerminated: false
                )
            ]
        )
        XCTAssertEqual(match, existingDebugRun, "A packaged launch should hand off to an already running debug executable")
    }

    @Test func testSingleInstancePolicyFindsExistingBundleFromDebugExecutableLaunch() {
        let existingBundle = AppInstanceSnapshot(
            processID: 200,
            bundleIdentifier: "free.vibelsland.macos",
            executableName: "VibelslandFree",
            bundleName: ">_ - island.app",
            localizedName: ">_ - island",
            isTerminated: false
        )
        let match = AppSingleInstancePolicy.existingInstance(
            currentProcessID: 300,
            currentBundleIdentifier: nil,
            currentExecutableName: "VibelslandFree",
            currentBundleName: nil,
            runningApplications: [
                existingBundle,
                AppInstanceSnapshot(
                    processID: 300,
                    bundleIdentifier: nil,
                    executableName: "VibelslandFree",
                    bundleName: nil,
                    localizedName: "VibelslandFree",
                    isTerminated: false
                )
            ]
        )
        XCTAssertEqual(match, existingBundle, "A debug executable launch should hand off to an already running packaged app")
    }

    @Test func testSessionMemoryPolicyCompactsLongRunningSessionData() {
        let now = Date()
        let longText = String(repeating: "长", count: SessionMemoryPolicy.maxSessionMessageCharacters + 120)
        let activities = (0..<14).map { index in
            ActivityItem(
                id: "activity-\(index)",
                symbol: "circle",
                title: index == 2 ? "token_count" : "事件 \(index)",
                detail: index == 4 ? "" : "detail-\(index)",
                date: now.addingTimeInterval(TimeInterval(index))
            )
        }
        let session = AgentSession(
            id: "memory-session",
            title: longText,
            prompt: longText,
            source: .codexDesktop,
            workspace: "/tmp/work",
            terminal: "Codex",
            updatedAt: now,
            status: .thinking,
            activity: activities,
            subagents: [],
            lastAssistantMessage: longText,
            lastUserMessage: longText,
            usage: nil
        )

        let compacted = SessionMemoryPolicy.compact(session)

        XCTAssertEqual(
            compacted.activity.count,
            SessionMemoryPolicy.maxSessionActivityItems,
            "Long-running sessions retain only the recent display activity tail"
        )
        XCTAssertFalse(
            compacted.activity.contains { $0.title == "token_count" || $0.detail.isEmpty },
            "Non-display transcript noise is not retained in the in-memory session model"
        )
        XCTAssertEqual(compacted.activity.last?.detail, "detail-13", "Compaction keeps the newest useful activity")
        XCTAssertTrue(compacted.title.count <= SessionMemoryPolicy.maxSessionMessageCharacters, "Title text is bounded")
        XCTAssertTrue(compacted.prompt.count <= SessionMemoryPolicy.maxSessionMessageCharacters, "Prompt text is bounded")
        XCTAssertTrue(compacted.lastAssistantMessage?.count ?? 0 <= SessionMemoryPolicy.maxSessionMessageCharacters, "Assistant text is bounded")
        XCTAssertTrue(compacted.lastUserMessage?.count ?? 0 <= SessionMemoryPolicy.maxSessionMessageCharacters, "User text is bounded")

        let cooldowns = SessionMemoryPolicy.compactCooldowns(
            [
                "old": now.addingTimeInterval(-SessionMemoryPolicy.soundCooldownMaxAge - 1),
                "recent": now.addingTimeInterval(-30)
            ],
            now: now
        )
        XCTAssertEqual(cooldowns["old"], nil, "Stale sound cooldown keys are pruned")
        XCTAssertTrue(cooldowns["recent"] != nil, "Recent sound cooldown keys remain active")
    }

    @Test func testSingleInstancePolicyIgnoresTerminatedAndUnrelatedApps() {
        let match = AppSingleInstancePolicy.existingInstance(
            currentProcessID: 300,
            currentBundleIdentifier: "free.vibelsland.macos",
            currentExecutableName: "VibelslandFree",
            currentBundleName: ">_ - island.app",
            runningApplications: [
                AppInstanceSnapshot(
                    processID: 100,
                    bundleIdentifier: "free.vibelsland.macos",
                    executableName: "VibelslandFree",
                    bundleName: ">_ - island.app",
                    localizedName: ">_ - island",
                    isTerminated: true
                ),
                AppInstanceSnapshot(
                    processID: 101,
                    bundleIdentifier: "com.example.other",
                    executableName: "OtherTool",
                    bundleName: "Other.app",
                    localizedName: "Other",
                    isTerminated: false
                )
            ]
        )
        XCTAssertEqual(match, nil, "Only a live >_ - island instance should block a new launch")
    }

    @Test func testAppPathsSupportsExplicitVerificationHomeOverride() {
        XCTAssertEqual(
            AppPaths.home(environment: ["VIBELSLAND_HOME": "/tmp/vibelsland-isolated"]).path,
            "/tmp/vibelsland-isolated",
            "Verification scripts can isolate app runtime state without touching the user's real config"
        )
        XCTAssertEqual(
            AppPaths.home(environment: ["VIBELSLAND_HOME": "   "]),
            FileManager.default.homeDirectoryForCurrentUser,
            "Blank override falls back to the real user home"
        )
    }

    @Test func testApprovalTimeoutPolicySupportsFastVerificationOverride() {
        XCTAssertEqual(
            ApprovalTimeoutPolicy.timeout(
                configured: 7_200,
                environment: ["VIBELSLAND_APPROVAL_TIMEOUT_SECONDS": "1.25"]
            ),
            1.25,
            "Verification scripts can cover approval timeout behavior without waiting for the production timeout"
        )
        XCTAssertEqual(
            ApprovalTimeoutPolicy.timeout(configured: 10, environment: [:]),
            60,
            "Normal app configuration still keeps the production minimum timeout"
        )
        XCTAssertEqual(
            ApprovalTimeoutPolicy.timeout(configured: 99_999, environment: [:]),
            7_200,
            "Normal app configuration still keeps the production maximum timeout"
        )
    }

    @Test func testIslandPresentationPolicyKeepsIdleStateSmall() {
        let now = Date(timeIntervalSince1970: 1_800_001_300)
        let recentDone = presentationPolicySession(
            id: "recent-done",
            status: .done,
            updatedAt: now.addingTimeInterval(-20)
        )
        let staleThinking = presentationPolicySession(
            id: "stale-thinking",
            status: .thinking,
            updatedAt: now.addingTimeInterval(-3 * 60 * 60)
        )
        let activeTool = presentationPolicySession(
            id: "active-tool",
            status: .runningTool,
            updatedAt: now
        )
        let pendingApproval = AgentSession(
            id: "approval-session",
            title: "approval",
            prompt: "approval",
            source: .codexCli,
            workspace: "/tmp/vibelsland",
            terminal: "Codex",
            updatedAt: now,
            status: .waitingApproval,
            activity: [],
            approval: ApprovalRequest(
                id: "approval",
                source: .codexCli,
                title: "Codex 请求权限",
                detail: "swift test",
                tool: "Bash",
                workspace: "/tmp/vibelsland",
                availableDecisions: [.accept, .decline],
                suggestedSessionAllow: false,
                supportsCancel: false,
                createdAt: now
            ),
            question: nil,
            subagents: [],
            lastAssistantMessage: nil,
            lastUserMessage: nil,
            usage: nil
        )

        XCTAssertEqual(
            IslandPresentationPolicy.mode(sessions: [], isExpanded: false, now: now),
            .idleMini,
            "No sessions should present the small idle circle"
        )
        XCTAssertEqual(
            IslandPresentationPolicy.mode(sessions: [recentDone, staleThinking], isExpanded: false, now: now),
            .idleMini,
            "Recent completed and stale active-looking sessions do not keep the task pill open"
        )
        XCTAssertEqual(
            IslandPresentationPolicy.compactSize(sessions: [recentDone], now: now),
            CGSize(width: 34, height: 34),
            "Idle compact size is the small circle"
        )
        XCTAssertEqual(
            IslandPresentationPolicy.mode(sessions: [activeTool], isExpanded: false, now: now),
            .compactTask,
            "Active work expands to the task pill"
        )
        XCTAssertEqual(
            IslandPresentationPolicy.mode(sessions: [pendingApproval], isExpanded: false, now: now),
            .compactTask,
            "Pending approval keeps the task pill visible"
        )
        XCTAssertEqual(
            IslandPresentationPolicy.compactSize(sessions: [activeTool], now: now),
            CGSize(width: 244, height: 42),
            "Active compact size stays stable"
        )
        XCTAssertEqual(
            IslandPresentationPolicy.mode(sessions: [activeTool], isExpanded: true, now: now),
            .expanded,
            "Expanded presentation is explicit regardless of active status"
        )
    }

    @Test func testBridgeRuntimeHealthPolicyRequiresRealSecureSocket() {
        let healthySocket = BridgeSocketInspection(
            exists: true,
            isSocket: true,
            ownerMatchesCurrentUser: true,
            permissions: 0o600
        )
        let healthy = BridgeRuntimeHealthPolicy.item(
            bridgeEnabled: true,
            bridgeExecutable: true,
            socket: healthySocket
        )
        XCTAssertEqual(healthy.status, .normal)
        XCTAssertEqual(healthy.detail, "本机桥接脚本和 socket 正常")

        let regularFileSocket = BridgeSocketInspection(
            exists: true,
            isSocket: false,
            ownerMatchesCurrentUser: true,
            permissions: 0o600
        )
        XCTAssertEqual(
            BridgeRuntimeHealthPolicy.item(
                bridgeEnabled: true,
                bridgeExecutable: true,
                socket: regularFileSocket
            ).status,
            .needsAction,
            "A stale regular file at the socket path must not be shown as healthy"
        )

        let loosePermissionsSocket = BridgeSocketInspection(
            exists: true,
            isSocket: true,
            ownerMatchesCurrentUser: true,
            permissions: 0o644
        )
        let loosePermissions = BridgeRuntimeHealthPolicy.item(
            bridgeEnabled: true,
            bridgeExecutable: true,
            socket: loosePermissionsSocket
        )
        XCTAssertEqual(loosePermissions.status, .needsAction)
        XCTAssertTrue(
            loosePermissions.detail.contains("权限应为 600"),
            "Wrong socket permissions should tell the user what to repair"
        )

        let disabled = BridgeRuntimeHealthPolicy.item(
            bridgeEnabled: false,
            bridgeExecutable: false,
            socket: .missing
        )
        XCTAssertEqual(disabled.status, .disabled)
        XCTAssertFalse(
            disabled.isActionable,
            "Disabled sources stay out of exception-only health UI"
        )
    }

    @Test func testIslandLayoutSignatureOnlyChangesForLayoutRelevantState() {
        let now = Date(timeIntervalSince1970: 1_800_001_500)
        let active = presentationPolicySession(
            id: "active",
            status: .thinking,
            updatedAt: now.addingTimeInterval(-20)
        )
        let sameLayoutTextChange = presentationPolicySession(
            id: "active",
            title: "updated text",
            prompt: "updated text",
            status: .thinking,
            updatedAt: now.addingTimeInterval(-10)
        )
        let expiringActive = presentationPolicySession(
            id: "expiring-active",
            status: .thinking,
            updatedAt: now.addingTimeInterval(-DashboardSessionPolicy.activeHideAfter + 1)
        )
        let healthWarning = HealthCheckItem(
            id: "bridge",
            name: "Bridge",
            status: .needsAction,
            detail: "需要重新安装 Hook",
            suggestedAction: "安装 Hooks"
        )

        XCTAssertEqual(
            IslandLayoutSignature(
                sessions: [active],
                healthChecks: [],
                isExpanded: false,
                isApprovalDetailVisible: false,
                maxVisibleSessions: 5,
                position: .topCenter,
                now: now
            ),
            IslandLayoutSignature(
                sessions: [sameLayoutTextChange],
                healthChecks: [],
                isExpanded: false,
                isApprovalDetailVisible: false,
                maxVisibleSessions: 5,
                position: .topCenter,
                now: now
            ),
            "Text-only session refreshes should not resize or reorder the window"
        )

        XCTAssertNotEqual(
            IslandLayoutSignature(
                sessions: [expiringActive],
                healthChecks: [],
                isExpanded: false,
                isApprovalDetailVisible: false,
                maxVisibleSessions: 5,
                position: .topCenter,
                now: now
            ),
            IslandLayoutSignature(
                sessions: [expiringActive],
                healthChecks: [],
                isExpanded: false,
                isApprovalDetailVisible: false,
                maxVisibleSessions: 5,
                position: .topCenter,
                now: now.addingTimeInterval(2)
            ),
            "Aging active sessions must still shrink the compact task pill back to the idle circle"
        )

        XCTAssertNotEqual(
            IslandLayoutSignature(
                sessions: [active],
                healthChecks: [],
                isExpanded: true,
                isApprovalDetailVisible: false,
                maxVisibleSessions: 5,
                position: .topCenter,
                now: now
            ),
            IslandLayoutSignature(
                sessions: [active],
                healthChecks: [healthWarning],
                isExpanded: true,
                isApprovalDetailVisible: false,
                maxVisibleSessions: 5,
                position: .topCenter,
                now: now
            ),
            "Health warnings affect expanded window height"
        )
    }

    @Test func testIslandMotionPolicyKeepsLoadingSpinnerCalm() {
        XCTAssertEqual(IslandMotionPolicy.CompactLoadingSpinner.rotationCycle(for: .runningTool), 4.2)
        XCTAssertEqual(IslandMotionPolicy.CompactLoadingSpinner.rotationCycle(for: .thinking), 4.8)
        XCTAssertEqual(IslandMotionPolicy.CompactLoadingSpinner.rotationCycle(for: .waitingApproval), 5.2)
        XCTAssertTrue(
            IslandMotionPolicy.CompactLoadingSpinner.rotationCycle(for: .runningTool) >= 4.0,
            "Running spinner should stay slower than the earlier too-fast animation"
        )
        XCTAssertTrue(
            IslandMotionPolicy.CompactLoadingSpinner.rotationCycle(for: .thinking)
                > IslandMotionPolicy.CompactLoadingSpinner.rotationCycle(for: .runningTool),
            "Thinking state should feel calmer than active tool execution"
        )
    }

    @Test func testIslandMotionPolicyBoundsMiniRingAndBreathingLights() {
        XCTAssertEqual(IslandMotionPolicy.MiniProgressRing.rotationDegrees(time: 3.4, status: .runningTool), 0)
        XCTAssertEqual(IslandMotionPolicy.MiniProgressRing.rotationDegrees(time: 2.0, status: .idle), 0)
        XCTAssertTrue(
            IslandMotionPolicy.MiniProgressRing.refreshInterval(for: .idle)
                > IslandMotionPolicy.MiniProgressRing.refreshInterval(for: .runningTool),
            "Idle mini ring should refresh less often than active mini ring"
        )
        XCTAssertTrue(
            IslandMotionPolicy.MiniProgressRing.refreshInterval(for: .runningTool) <= 1.0 / 55.0,
            "Active mini ring should render close to display refresh instead of visibly stepping"
        )
        XCTAssertTrue(
            IslandMotionPolicy.BreathingLights.refreshInterval(for: .thinking) <= 1.0 / 28.0,
            "Breathing lights need a smooth active cadence"
        )
        XCTAssertFalse(IslandMotionPolicy.BreathingLights.shouldAnimate(for: .idle), "Idle mini lights should not keep a timeline alive")
        XCTAssertFalse(IslandMotionPolicy.BreathingLights.shouldAnimate(for: .failed), "Static warning lights avoid idle CPU work")
        XCTAssertTrue(IslandMotionPolicy.BreathingLights.shouldAnimate(for: .thinking), "Active sessions keep breathing lights animated")
        XCTAssertTrue(IslandMotionPolicy.BreathingLights.shouldAnimate(for: .waitingApproval), "Approval states keep breathing lights animated")

        for status in [SessionStatus.idle, .thinking, .runningTool, .waitingApproval, .done, .failed] {
            let lowOpacity = IslandMotionPolicy.BreathingLights.opacity(for: 0, status: status)
            let highOpacity = IslandMotionPolicy.BreathingLights.opacity(for: 1, status: status)
            XCTAssertTrue((0...1).contains(lowOpacity), "Breathing light low opacity is bounded")
            XCTAssertTrue((0...1).contains(highOpacity), "Breathing light high opacity is bounded")
            XCTAssertTrue(highOpacity >= lowOpacity, "Breathing light opacity increases with pulse")
        }
    }

    @Test func testIslandWindowTransitionPolicyAnimatesCollapse() {
        XCTAssertEqual(IslandMotionPolicy.WindowTransition.duration(expanded: true), 0.32)
        XCTAssertEqual(IslandMotionPolicy.WindowTransition.duration(expanded: false), 0.42)
        XCTAssertEqual(IslandMotionPolicy.ContentTransition.crossfadeDuration, 0.18)
        XCTAssertTrue(
            IslandMotionPolicy.WindowTransition.duration(expanded: false) >= 0.36,
            "Collapse should be long enough to survive SwiftUI content relayout instead of snapping closed"
        )
        XCTAssertTrue(
            IslandMotionPolicy.ContentTransition.crossfadeDuration <
                IslandMotionPolicy.WindowTransition.duration(expanded: false),
            "Content should crossfade inside the longer collapse frame transition"
        )
        XCTAssertTrue(
            IslandMotionPolicy.WindowTransition.resetDelay(expanded: false) >
                UInt64(IslandMotionPolicy.WindowTransition.duration(expanded: false) * 1_000_000_000),
            "Transition flags should clear only after the collapse animation settles"
        )
    }

    private func sessionEvent(
        id: String? = nil,
        kind: AgentEventKind,
        timestamp: Date,
        payload: [String: JSONValue]
    ) -> AgentEvent {
        AgentEvent(
            id: id ?? kind.rawValue,
            source: .codexCli,
            kind: kind,
            timestamp: timestamp,
            payload: .object(payload)
        )
    }

    private func approvalDisplaySession(
        state: ApprovalResolutionState,
        expired: Bool = false
    ) -> AgentSession {
        let approval = ApprovalRequest(
            id: "approval-\(state.rawValue)",
            source: .codexDesktop,
            title: "命令执行",
            detail: "swift test",
            tool: "命令执行",
            workspace: "/tmp/vibelsland",
            availableDecisions: [.accept, .decline, .cancel],
            suggestedSessionAllow: false,
            supportsCancel: true,
            isResolving: state == .resolving,
            isExpired: expired,
            resolutionState: state,
            resolutionMessage: state.title,
            createdAt: Date(timeIntervalSince1970: 1_800_000_400)
        )
        return AgentSession(
            id: "approval-display-\(state.rawValue)",
            title: "vibelsland",
            prompt: "vibelsland",
            source: .codexDesktop,
            workspace: "/tmp/vibelsland",
            terminal: "Codex",
            updatedAt: Date(timeIntervalSince1970: 1_800_000_401),
            status: .waitingApproval,
            activity: [],
            approval: approval,
            question: nil,
            subagents: [],
            lastAssistantMessage: nil,
            lastUserMessage: nil,
            usage: nil
        )
    }

    private func linkPolicySession(
        id: String,
        source: AgentSource,
        threadID: String? = nil
    ) -> AgentSession {
        AgentSession(
            id: id,
            title: "session",
            prompt: "session",
            source: source,
            workspace: "/tmp/vibelsland",
            terminal: "Codex",
            threadID: threadID,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_500),
            status: .thinking,
            activity: [],
            approval: nil,
            question: nil,
            subagents: [],
            lastAssistantMessage: nil,
            lastUserMessage: nil,
            usage: nil
        )
    }

    private func presentationPolicySession(
        id: String,
        title: String? = nil,
        prompt: String? = nil,
        status: SessionStatus,
        updatedAt: Date
    ) -> AgentSession {
        AgentSession(
            id: id,
            title: title ?? id,
            prompt: prompt ?? id,
            source: .codexDesktop,
            workspace: "/tmp/vibelsland",
            terminal: "Codex",
            updatedAt: updatedAt,
            status: status,
            activity: [],
            approval: nil,
            question: nil,
            subagents: [],
            lastAssistantMessage: nil,
            lastUserMessage: nil,
            usage: nil
        )
    }
}
