import AppKit
import Carbon.HIToolbox
import VibelslandFreeCore

/// 用 Carbon RegisterEventHotKey 注册全局快捷键。
/// 选 Carbon 而不是 NSEvent 全局监听：无需辅助功能权限、可吞掉按键事件、零第三方依赖。
@MainActor
final class GlobalHotKeyCenter {
    var onAction: ((GlobalHotKeyAction) -> Void)?

    private var registeredHotKeys: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    private let logger: AppLogger

    private static let signature: OSType = 0x5642_4652 // "VBFR"

    init(logger: AppLogger = .shared) {
        self.logger = logger
    }

    func apply(bindings: [(action: GlobalHotKeyAction, binding: HotKeyBinding)]) {
        unregisterAll()
        guard !bindings.isEmpty else { return }
        installEventHandlerIfNeeded()
        for entry in bindings {
            var hotKeyRef: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: Self.signature, id: entry.action.carbonHotKeyID)
            let status = RegisterEventHotKey(
                entry.binding.keyCode,
                entry.binding.carbonModifiers,
                hotKeyID,
                GetEventDispatcherTarget(),
                0,
                &hotKeyRef
            )
            if status == noErr, let hotKeyRef {
                registeredHotKeys.append(hotKeyRef)
                logger.info("hotkey.registered", detail: "\(entry.action.rawValue) \(GlobalHotKeyPolicy.displayText(for: entry.binding))")
            } else {
                logger.error("hotkey.register.failed", detail: "\(entry.action.rawValue) status=\(status)")
            }
        }
    }

    private func unregisterAll() {
        for hotKeyRef in registeredHotKeys {
            UnregisterEventHotKey(hotKeyRef)
        }
        registeredHotKeys.removeAll()
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr, hotKeyID.signature == GlobalHotKeyCenter.signature else {
                    return OSStatus(eventNotHandledErr)
                }
                let center = Unmanaged<GlobalHotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
                // Carbon 热键事件由主线程事件分发器派发，这里断言回到 MainActor。
                MainActor.assumeIsolated {
                    center.handleHotKey(id: hotKeyID.id)
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        if status != noErr {
            logger.error("hotkey.handler.install.failed", detail: "status=\(status)")
        }
    }

    private func handleHotKey(id: UInt32) {
        guard let action = GlobalHotKeyPolicy.action(forHotKeyID: id) else {
            logger.info("hotkey.unknown", detail: "id=\(id)")
            return
        }
        logger.info("hotkey.triggered", detail: action.rawValue)
        onAction?(action)
    }
}
