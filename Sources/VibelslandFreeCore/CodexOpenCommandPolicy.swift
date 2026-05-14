import Foundation

package enum CodexOpenCommandPolicy {
    package static func deepLinkArguments(bundleID: String, deepLink: String) -> [String] {
        ["-b", bundleID, deepLink]
    }

    package static func fallbackDeepLinkArguments(_ deepLink: String) -> [String] {
        [deepLink]
    }

    package static func focusArguments(bundleID: String) -> [String] {
        ["-b", bundleID]
    }
}
