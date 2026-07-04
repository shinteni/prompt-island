import Foundation

package struct RemoteRelease: Equatable {
    package var version: String
    package var pageURL: URL
    package var archiveName: String?
    package var archiveURL: URL?
    package var checksumURL: URL?

    package init(
        version: String,
        pageURL: URL,
        archiveName: String? = nil,
        archiveURL: URL? = nil,
        checksumURL: URL? = nil
    ) {
        self.version = version
        self.pageURL = pageURL
        self.archiveName = archiveName
        self.archiveURL = archiveURL
        self.checksumURL = checksumURL
    }

    /// 应用内自更新需要发布同时携带 zip 与配套 .sha256 资产。
    package var supportsSelfUpdate: Bool {
        archiveName != nil && archiveURL != nil && checksumURL != nil
    }
}

/// 更新检查的纯逻辑：接口地址、GitHub Release JSON 解析、版本比较。
/// 网络请求留在界面层；本地优先承诺由调用方保证——仅在用户手动点击
/// 或显式开启自动检查时才发起请求。
package enum UpdateCheckPolicy {
    package static let latestReleaseAPIURL = URL(string: "https://api.github.com/repos/shinteni/prompt-island/releases/latest")!
    package static let releasesPageURL = URL(string: "https://github.com/shinteni/prompt-island/releases")!

    /// 从 GitHub `releases/latest` 响应中取 tag、发布页与自更新所需资产
    /// （macOS zip 及其配套 .sha256）。
    package static func parseRelease(from data: Data) -> RemoteRelease? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = object["tag_name"] as? String else {
            return nil
        }
        let version = normalizedVersion(tag)
        guard !version.isEmpty else { return nil }
        let pageURL = (object["html_url"] as? String).flatMap(URL.init(string:)) ?? releasesPageURL

        var archiveName: String?
        var archiveURL: URL?
        var checksumURL: URL?
        if let assets = object["assets"] as? [[String: Any]] {
            for asset in assets {
                guard let name = asset["name"] as? String,
                      let urlString = asset["browser_download_url"] as? String,
                      let url = URL(string: urlString) else {
                    continue
                }
                if name.hasSuffix("-macos.zip") {
                    archiveName = name
                    archiveURL = url
                }
            }
            // 校验和资产必须与选中的 zip 严格配对，避免拿错文件校验。
            if let archiveName {
                for asset in assets {
                    guard let name = asset["name"] as? String,
                          name == "\(archiveName).sha256",
                          let urlString = asset["browser_download_url"] as? String,
                          let url = URL(string: urlString) else {
                        continue
                    }
                    checksumURL = url
                }
            }
        }
        return RemoteRelease(
            version: version,
            pageURL: pageURL,
            archiveName: archiveName,
            archiveURL: archiveURL,
            checksumURL: checksumURL
        )
    }

    /// 解析 shasum 输出格式的校验和文件（`<hex64>  <文件名>`）。
    /// 文件名必须与目标压缩包一致，防止校验对象错位。
    package static func parseChecksumContent(_ content: String, expectedArchiveName: String) -> String? {
        let parts = content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .map(String.init)
        guard parts.count == 2 else { return nil }
        let hash = parts[0].lowercased()
        guard hash.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else { return nil }
        // shasum 的第二列可能带 `*` 前缀（二进制模式），一并容忍。
        let name = parts[1].hasPrefix("*") ? String(parts[1].dropFirst()) : parts[1]
        guard name == expectedArchiveName else { return nil }
        return hash
    }

    /// 去掉前导 v/V 与空白："v0.2.0" -> "0.2.0"。
    package static func normalizedVersion(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("v") {
            value = String(value.dropFirst())
        }
        return value
    }

    /// 点分数字比较；分段缺失按 0。任一版本含非数字分段（如预发布后缀）
    /// 时整体保守视为不更新——必须先整体校验，逐段校验会在遇到非数字段
    /// 之前就因高位分段差异提前返回。
    package static func isNewer(remote: String, current: String) -> Bool {
        guard let remoteValues = numericParts(normalizedVersion(remote)),
              let currentValues = numericParts(normalizedVersion(current)) else {
            return false
        }
        let count = max(remoteValues.count, currentValues.count)
        for index in 0..<count {
            let remoteValue = index < remoteValues.count ? remoteValues[index] : 0
            let currentValue = index < currentValues.count ? currentValues[index] : 0
            if remoteValue != currentValue {
                return remoteValue > currentValue
            }
        }
        return false
    }

    private static func numericParts(_ value: String) -> [Int]? {
        guard !value.isEmpty else { return nil }
        var result: [Int] = []
        for part in value.split(separator: ".") {
            guard let number = Int(part) else { return nil }
            result.append(number)
        }
        return result.isEmpty ? nil : result
    }
}
