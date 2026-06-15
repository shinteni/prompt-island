import Foundation
import Testing
@testable import VibelslandFreeCore

@Suite
struct AppLifecyclePolicyTests {
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
}
