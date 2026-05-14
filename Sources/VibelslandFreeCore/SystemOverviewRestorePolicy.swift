import Foundation

package enum SystemOverviewRestoreDecision: Equatable {
    case restore
    case forceRestore
    case wait
}

package enum SystemOverviewRestorePolicy {
    package static let dockBundleIdentifier = "com.apple.dock"

    package static func decision(
        force: Bool,
        now: Date,
        minimumRestoreAt: Date?,
        forceRestoreAt: Date?,
        overviewLikelyVisible: Bool,
        frontmostBundleID: String?
    ) -> SystemOverviewRestoreDecision {
        if force {
            return .restore
        }

        if let minimumRestoreAt, now < minimumRestoreAt {
            return .wait
        }

        guard overviewLikelyVisible else {
            return .restore
        }

        if let forceRestoreAt,
           now >= forceRestoreAt,
           frontmostBundleID != dockBundleIdentifier {
            return .forceRestore
        }

        return .wait
    }
}
