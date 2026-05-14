import Foundation

package struct AppInstanceSnapshot: Equatable {
    package var processID: Int32
    package var bundleIdentifier: String?
    package var executableName: String?
    package var bundleName: String?
    package var localizedName: String?
    package var isTerminated: Bool

    package init(
        processID: Int32,
        bundleIdentifier: String?,
        executableName: String?,
        bundleName: String?,
        localizedName: String?,
        isTerminated: Bool
    ) {
        self.processID = processID
        self.bundleIdentifier = bundleIdentifier
        self.executableName = executableName
        self.bundleName = bundleName
        self.localizedName = localizedName
        self.isTerminated = isTerminated
    }
}

package enum AppSingleInstancePolicy {
    package static let productionBundleIdentifier = "free.vibelsland.macos"
    package static let executableName = "VibelslandFree"
    package static let appBundleName = "Vibelsland Free.app"
    package static let appDisplayName = "Vibelsland Free"

    package static func existingInstance(
        currentProcessID: Int32,
        currentBundleIdentifier: String?,
        currentExecutableName: String?,
        currentBundleName: String?,
        runningApplications: [AppInstanceSnapshot]
    ) -> AppInstanceSnapshot? {
        runningApplications
            .filter { app in
                app.processID != currentProcessID &&
                !app.isTerminated &&
                matchesVibelslandInstance(
                    app,
                    currentBundleIdentifier: currentBundleIdentifier,
                    currentExecutableName: currentExecutableName,
                    currentBundleName: currentBundleName
                )
            }
            .sorted { $0.processID < $1.processID }
            .first
    }

    private static func matchesVibelslandInstance(
        _ app: AppInstanceSnapshot,
        currentBundleIdentifier: String?,
        currentExecutableName: String?,
        currentBundleName: String?
    ) -> Bool {
        if let currentBundleIdentifier,
           app.bundleIdentifier == currentBundleIdentifier {
            return true
        }
        if app.bundleIdentifier == productionBundleIdentifier {
            return true
        }

        let expectedExecutableName = currentExecutableName ?? executableName
        let executableMatches =
            app.executableName == expectedExecutableName ||
            app.executableName == executableName
        guard executableMatches else { return false }

        let expectedBundleName = currentBundleName ?? appBundleName
        if app.bundleName == expectedBundleName ||
            app.bundleName == appBundleName ||
            app.localizedName == appDisplayName {
            return true
        }

        return app.bundleIdentifier == nil &&
            app.bundleName == nil &&
            (app.localizedName == nil ||
                app.localizedName == executableName ||
                app.localizedName == expectedExecutableName)
    }
}
