import AppKit
import CryptoKit
import Foundation
import VibelslandFreeCore

enum UpdateStage: Equatable {
    case downloading
    case verifying
    case installing
    case restarting
}

struct UpdateInstallError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// 应用内自更新管线：下载发布 zip 与配套 .sha256 → 校验 SHA-256 →
/// 解压 → codesign 结构校验 → 去除 quarantine → 原子替换 app（失败回滚）。
/// 完整性由发布的校验和资产保证，与手动安装流程的信任模型一致。
enum UpdateInstaller {
    static var isRunningFromAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    @MainActor
    static func install(
        release: RemoteRelease,
        logger: AppLogger = .shared,
        onStage: @MainActor (UpdateStage) -> Void
    ) async throws {
        guard isRunningFromAppBundle else {
            throw UpdateInstallError(message: "当前不是打包的 .app，无法应用内更新")
        }
        guard let archiveName = release.archiveName,
              let archiveURL = release.archiveURL,
              let checksumURL = release.checksumURL else {
            throw UpdateInstallError(message: "该发布缺少可自更新的资产")
        }

        let bundleURL = Bundle.main.bundleURL
        let bundleName = bundleURL.lastPathComponent
        let fileManager = FileManager.default

        let staging = AppPaths.applicationSupportDirectory
            .appendingPathComponent("updates", isDirectory: true)
            .appendingPathComponent(release.version, isDirectory: true)
        try? fileManager.removeItem(at: staging)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)

        // 1. 下载 zip 与校验和
        onStage(.downloading)
        let session = URLSession(configuration: {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 600
            return configuration
        }())
        let archivePath = staging.appendingPathComponent(archiveName)
        let (downloadedArchive, archiveResponse) = try await session.download(from: archiveURL)
        try requireHTTPSuccess(archiveResponse, label: "下载安装包")
        try? fileManager.removeItem(at: archivePath)
        try fileManager.moveItem(at: downloadedArchive, to: archivePath)

        let (checksumData, checksumResponse) = try await session.data(from: checksumURL)
        try requireHTTPSuccess(checksumResponse, label: "下载校验和")

        // 2. 校验 SHA-256
        onStage(.verifying)
        guard let checksumContent = String(data: checksumData, encoding: .utf8),
              let expectedHash = UpdateCheckPolicy.parseChecksumContent(checksumContent, expectedArchiveName: archiveName) else {
            throw UpdateInstallError(message: "校验和文件格式异常")
        }
        let archiveData = try Data(contentsOf: archivePath)
        let actualHash = SHA256.hash(data: archiveData).map { String(format: "%02x", $0) }.joined()
        guard actualHash == expectedHash else {
            logger.error("update.checksum.mismatch", detail: "expected=\(expectedHash) actual=\(actualHash)")
            throw UpdateInstallError(message: "SHA-256 校验失败，已中止更新")
        }

        // 3. 解压并定位新 app
        let extractDir = staging.appendingPathComponent("extracted", isDirectory: true)
        try fileManager.createDirectory(at: extractDir, withIntermediateDirectories: true)
        try await runProcess("/usr/bin/ditto", ["-x", "-k", archivePath.path, extractDir.path], label: "解压安装包")
        let newApp = extractDir.appendingPathComponent(bundleName)
        guard fileManager.fileExists(atPath: newApp.path) else {
            throw UpdateInstallError(message: "安装包内未找到 \(bundleName)")
        }

        // 4. 签名结构校验 + 去除下载隔离标记（完整性已由校验和保证）
        try await runProcess("/usr/bin/codesign", ["--verify", "--deep", "--strict", newApp.path], label: "签名校验")
        _ = try? await runProcess("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newApp.path], label: "清除隔离标记", tolerateFailure: true)

        // 5. 原子替换：旧包先移到暂存区，失败则回滚
        onStage(.installing)
        let backup = staging.appendingPathComponent("previous-\(bundleName)")
        try? fileManager.removeItem(at: backup)
        do {
            try fileManager.moveItem(at: bundleURL, to: backup)
        } catch {
            throw UpdateInstallError(message: "无法替换应用（目录可能没有写入权限）：\(error.localizedDescription)")
        }
        do {
            try fileManager.moveItem(at: newApp, to: bundleURL)
        } catch {
            try? fileManager.moveItem(at: backup, to: bundleURL)
            throw UpdateInstallError(message: "安装新版本失败，已恢复原版本：\(error.localizedDescription)")
        }
        logger.info("update.installed", detail: release.version)
    }

    private static func requireHTTPSuccess(_ response: URLResponse, label: String) throws {
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw UpdateInstallError(message: "\(label)失败：HTTP \(http.statusCode)")
        }
    }

    @discardableResult
    private static func runProcess(
        _ executable: String,
        _ arguments: [String],
        label: String,
        tolerateFailure: Bool = false
    ) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { finished in
                let status = finished.terminationStatus
                if status == 0 || tolerateFailure {
                    continuation.resume(returning: status)
                } else {
                    continuation.resume(throwing: UpdateInstallError(message: "\(label)失败（exit \(status)）"))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: UpdateInstallError(message: "\(label)无法启动：\(error.localizedDescription)"))
            }
        }
    }
}
