import Foundation
import UserNotifications
import VibelslandFreeCore

/// UNUserNotificationCenter 的薄封装：发/撤审批通知，把通知动作路由回审批决定。
/// 标识符编码与触发条件在 ApprovalNotificationPolicy（可单测），这里只做框架调用。
@MainActor
final class ApprovalNotificationCenter: NSObject {
    var onDecision: ((_ approvalID: String, _ decision: ApprovalDecision) -> Void)?
    var onOpenApproval: ((_ approvalID: String) -> Void)?
    /// 点击横幅时按 ID 找回审批请求，用于校验动作是否仍受支持。
    var approvalProvider: ((_ approvalID: String) -> ApprovalRequest?)?

    private let logger: AppLogger
    private var isActivated = false
    private(set) var authorizationDenied = false

    /// swift build 直接跑的裸可执行没有 bundle，UNUserNotificationCenter.current() 会抛
    /// Objective-C 异常且 Swift 无法捕获，所以先按 bundle 存在与否降级。
    nonisolated static var isSupportedProcess: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    init(logger: AppLogger = .shared) {
        self.logger = logger
        super.init()
    }

    func activate(language: AppLanguage) {
        guard Self.isSupportedProcess else {
            logger.info("notification.unsupported", detail: "no bundle identifier")
            return
        }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        registerCategory(language: language)
        guard !isActivated else { return }
        isActivated = true
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            Task { @MainActor [weak self] in
                self?.authorizationDenied = !granted
                if let error {
                    self?.logger.error("notification.authorization.failed", detail: error.localizedDescription)
                } else {
                    self?.logger.info("notification.authorization", detail: granted ? "granted" : "denied")
                }
            }
        }
    }

    func registerCategory(language: AppLanguage) {
        guard Self.isSupportedProcess else { return }
        let accept = UNNotificationAction(
            identifier: ApprovalNotificationPolicy.acceptActionIdentifier,
            title: ApprovalDecision.accept.title(language: language),
            options: []
        )
        let decline = UNNotificationAction(
            identifier: ApprovalNotificationPolicy.declineActionIdentifier,
            title: ApprovalDecision.decline.title(language: language),
            options: [.destructive]
        )
        let category = UNNotificationCategory(
            identifier: ApprovalNotificationPolicy.categoryIdentifier,
            actions: [accept, decline],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    func post(approval: ApprovalRequest, language: AppLanguage) {
        guard Self.isSupportedProcess else { return }
        let content = UNMutableNotificationContent()
        content.title = AppText.pick(
            language,
            english: "\(approval.source.shortName) requests approval",
            japanese: "\(approval.source.shortName) が承認を要求",
            chinese: "\(approval.source.shortName) 请求审批"
        )
        content.body = ApprovalNotificationPolicy.body(for: approval)
        content.categoryIdentifier = ApprovalNotificationPolicy.categoryIdentifier
        // 浮岛已经播放审批提示音，这里不再叠加系统提示音。
        let request = UNNotificationRequest(
            identifier: ApprovalNotificationPolicy.notificationIdentifier(approvalID: approval.id),
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            guard let error else { return }
            Task { @MainActor [weak self] in
                self?.logger.error("notification.post.failed", detail: error.localizedDescription)
            }
        }
        logger.info("notification.posted", detail: approval.id)
    }

    func withdraw(approvalID: String) {
        guard Self.isSupportedProcess else { return }
        let identifier = ApprovalNotificationPolicy.notificationIdentifier(approvalID: approvalID)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
}

extension ApprovalNotificationCenter: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let requestIdentifier = response.notification.request.identifier
        let actionIdentifier = response.actionIdentifier
        // 决定动作只改本地状态，不需要让系统等待，这里直接完成回调。
        completionHandler()
        Task { @MainActor [weak self] in
            self?.handleResponse(requestIdentifier: requestIdentifier, actionIdentifier: actionIdentifier)
        }
    }

    private func handleResponse(requestIdentifier: String, actionIdentifier: String) {
        guard let approvalID = ApprovalNotificationPolicy.approvalID(fromNotificationIdentifier: requestIdentifier) else {
            return
        }
        if actionIdentifier == UNNotificationDefaultActionIdentifier {
            onOpenApproval?(approvalID)
            return
        }
        guard actionIdentifier != UNNotificationDismissActionIdentifier else { return }
        guard let approval = approvalProvider?(approvalID),
              let decision = ApprovalNotificationPolicy.decision(
                forActionIdentifier: actionIdentifier,
                approval: approval
              ) else {
            logger.info("notification.action.ignored", detail: actionIdentifier)
            onOpenApproval?(approvalID)
            return
        }
        onDecision?(approvalID, decision)
    }
}
