import Foundation

package enum ApprovalTimeoutPolicy {
    package static let verificationOverrideKey = "VIBELSLAND_APPROVAL_TIMEOUT_SECONDS"

    package static func timeout(
        configured: TimeInterval,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> TimeInterval {
        if let override = environment[verificationOverrideKey],
           let value = TimeInterval(override.trimmingCharacters(in: .whitespacesAndNewlines)),
           value > 0 {
            return min(max(value, 0.2), 7_200)
        }

        return min(max(configured, 60), 7_200)
    }
}
