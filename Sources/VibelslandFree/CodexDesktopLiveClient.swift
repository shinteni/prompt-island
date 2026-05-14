import Foundation
import VibelslandFreeCore

struct JSONRPCMessage: Codable {
    var id: Int
    var method: String
    var params: JSONValue
}

struct CodexAppServerProbeResult: Equatable {
    var reachable: Bool
    var codexHome: String?
    var userAgent: String?
    var threadListAvailable: Bool
    var threadCount: Int
}

final class CodexDesktopLiveClient: @unchecked Sendable {
    private let logger: AppLogger

    init(logger: AppLogger = .shared) {
        self.logger = logger
    }

    func initializeProbe() -> CodexAppServerProbeResult {
        guard let codexPath = findCodexExecutable() else {
            return .unavailable
        }

        do {
            let output = try runProbe(codexPath: codexPath, timeout: 5)
            let messages = parseJSONLines(output)
            guard let result = responseResult(id: 1, in: messages) else { return .unavailable }
            let threadList = responseResult(id: 2, in: messages)
            let threadData = threadList?["data"] as? [[String: Any]] ?? []
            return CodexAppServerProbeResult(
                reachable: result["codexHome"] as? String != nil,
                codexHome: result["codexHome"] as? String,
                userAgent: result["userAgent"] as? String,
                threadListAvailable: threadList != nil,
                threadCount: threadData.count
            )
        } catch {
            logger.error("codex.appserver.probe.failed", detail: error.localizedDescription)
            return .unavailable
        }
    }

    private func findCodexExecutable() -> String? {
        let candidates = [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/Applications/Codex.app/Contents/Resources/codex"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func runProbe(codexPath: String, timeout: TimeInterval) throws -> String {
        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        let state = CodexProbeState()

        func writeLine(_ line: String) throws {
            guard let data = (line + "\n").data(using: .utf8) else { return }
            try stdin.fileHandleForWriting.write(contentsOf: data)
        }

        func cleanup() {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            try? stdin.fileHandleForWriting.close()
            if process.isRunning {
                process.terminate()
            }
            process.waitUntilExit()
            _ = try? stdout.fileHandleForReading.readToEnd()
            _ = try? stderr.fileHandleForReading.readToEnd()
        }

        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            state.appendStdout(data)
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            state.appendStderr(data)
        }
        process.terminationHandler = { _ in
            state.wakeWaiters()
        }

        try process.run()
        defer { cleanup() }

        let deadline = Date().addingTimeInterval(timeout)
        try writeLine(#"{"id":1,"method":"initialize","params":{"clientInfo":{"name":"prompt-island","version":"0"},"capabilities":{}}}"#)
        guard state.waitForResponse(id: 1, process: process, until: deadline) else {
            throw NSError(domain: "VibelslandFree.codex", code: 1, userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for initialize response"])
        }

        try writeLine(#"{"method":"initialized"}"#)
        try writeLine(#"{"id":2,"method":"thread/list","params":{"limit":5,"archived":false,"sortKey":"updated_at","sortDirection":"desc","useStateDbOnly":true,"sourceKinds":[]}}"#)
        guard state.waitForResponse(id: 2, process: process, until: deadline) else {
            throw NSError(domain: "VibelslandFree.codex", code: 2, userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for thread/list response"])
        }

        let output = state.stdoutText()
        let errorText = state.stderrText()

        if output.isEmpty {
            if !errorText.isEmpty {
                throw NSError(domain: "VibelslandFree.codex", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: errorText])
            }
        }
        return output
    }

    private func parseJSONLines(_ text: String) -> [[String: Any]] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            guard let data = String(line).data(using: .utf8) else { return nil }
            return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }
    }

    private func responseResult(id: Int, in messages: [[String: Any]]) -> [String: Any]? {
        messages.first { message in
            if let value = message["id"] as? Int {
                return value == id
            }
            if let value = message["id"] as? Double {
                return Int(value) == id
            }
            return false
        }?["result"] as? [String: Any]
    }
}

private final class CodexProbeState: @unchecked Sendable {
    private let condition = NSCondition()
    private var stdoutData = Data()
    private var stdoutLineBuffer = Data()
    private var stderrData = Data()
    private var messages: [[String: Any]] = []

    func appendStdout(_ chunk: Data) {
        condition.lock()
        defer {
            condition.broadcast()
            condition.unlock()
        }

        stdoutData.append(chunk)
        stdoutLineBuffer.append(chunk)

        while let newlineIndex = stdoutLineBuffer.firstIndex(of: 0x0A) {
            let line = stdoutLineBuffer[..<newlineIndex]
            stdoutLineBuffer.removeSubrange(...newlineIndex)
            guard !line.isEmpty else { continue }
            if let message = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] {
                messages.append(message)
            }
        }
    }

    func appendStderr(_ chunk: Data) {
        condition.lock()
        stderrData.append(chunk)
        condition.unlock()
    }

    func wakeWaiters() {
        condition.lock()
        condition.broadcast()
        condition.unlock()
    }

    func waitForResponse(id: Int, process: Process, until deadline: Date) -> Bool {
        condition.lock()
        defer { condition.unlock() }
        while process.isRunning && !responseReceived(id: id) {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { return false }
            condition.wait(until: Date().addingTimeInterval(min(remaining, 0.1)))
        }
        return responseReceived(id: id)
    }

    func stdoutText() -> String {
        condition.lock()
        defer { condition.unlock() }
        return String(data: stdoutData, encoding: .utf8) ?? ""
    }

    func stderrText() -> String {
        condition.lock()
        defer { condition.unlock() }
        return String(data: stderrData, encoding: .utf8) ?? ""
    }

    private func responseReceived(id: Int) -> Bool {
        messages.contains { message in
            if let value = message["id"] as? Int {
                return value == id
            }
            if let value = message["id"] as? Double {
                return Int(value) == id
            }
            return false
        }
    }
}

extension CodexAppServerProbeResult {
    static let unavailable = CodexAppServerProbeResult(
        reachable: false,
        codexHome: nil,
        userAgent: nil,
        threadListAvailable: false,
        threadCount: 0
    )
}
