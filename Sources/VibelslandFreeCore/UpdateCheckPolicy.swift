import Foundation

package struct RemoteRelease: Equatable {
    package var version: String
    package var pageURL: URL

    package init(version: String, pageURL: URL) {
        self.version = version
        self.pageURL = pageURL
    }
}

/// 更新检查的纯逻辑：接口地址、GitHub Release JSON 解析、版本比较。
/// 网络请求留在界面层；本地优先承诺由调用方保证——仅在用户手动点击
/// 或显式开启自动检查时才发起请求。
package enum UpdateCheckPolicy {
    package static let latestReleaseAPIURL = URL(string: "https://api.github.com/repos/shinteni/prompt-island/releases/latest")!
    package static let releasesPageURL = URL(string: "https://github.com/shinteni/prompt-island/releases")!

    /// 从 GitHub `releases/latest` 响应中取 tag 与发布页。
    package static func parseRelease(from data: Data) -> RemoteRelease? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = object["tag_name"] as? String else {
            return nil
        }
        let version = normalizedVersion(tag)
        guard !version.isEmpty else { return nil }
        let pageURL = (object["html_url"] as? String).flatMap(URL.init(string:)) ?? releasesPageURL
        return RemoteRelease(version: version, pageURL: pageURL)
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
