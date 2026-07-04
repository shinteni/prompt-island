import Foundation
import VibelslandFreeCore

enum UpdateCheckState: Equatable {
    case idle
    case checking
    case upToDate(current: String)
    case available(RemoteRelease)
    case updating(UpdateStage, RemoteRelease)
    case updateFailed(message: String, release: RemoteRelease)
    case failed(message: String)

    var isBusy: Bool {
        switch self {
        case .checking, .updating:
            return true
        case .idle, .upToDate, .available, .updateFailed, .failed:
            return false
        }
    }
}

/// 更新检查的网络调用。只在用户手动触发或显式开启自动检查时被调用，
/// 与「核心功能零网络」的本地优先承诺不冲突。
struct UpdateChecker {
    var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        return URLSession(configuration: configuration)
    }()

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    func fetchLatestRelease() async -> Result<RemoteRelease, Error> {
        var request = URLRequest(url: UpdateCheckPolicy.latestReleaseAPIURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return .failure(UpdateCheckError.badStatus(http.statusCode))
            }
            guard let release = UpdateCheckPolicy.parseRelease(from: data) else {
                return .failure(UpdateCheckError.unparseableResponse)
            }
            return .success(release)
        } catch {
            return .failure(error)
        }
    }
}

enum UpdateCheckError: Error, LocalizedError {
    case badStatus(Int)
    case unparseableResponse

    var errorDescription: String? {
        switch self {
        case .badStatus(let code):
            "HTTP \(code)"
        case .unparseableResponse:
            "unexpected response format"
        }
    }
}
