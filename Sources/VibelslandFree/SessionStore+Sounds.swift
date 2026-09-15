import VibelslandFreeCore
import Foundation


extension SessionStore {
    func playSoundPreview(_ kind: RetroSoundKind) {
        guard configurationStore.config.enableSounds else {
            lastError = soundsDisabledText
            return
        }
        soundPlayer(kind, configurationStore.config.soundTheme)
        lastError = nil
    }

    func playStatusTransitionSound(previous: AgentSession?, current: AgentSession) {
        guard let previous, previous.status.isActiveVisual, current.status == .done else { return }
        playSound(.taskCompleted, key: "done:\(current.id)", minimumInterval: 4.0)
    }

    func playSound(_ kind: RetroSoundKind, key: String, minimumInterval: TimeInterval) {
        guard configurationStore.config.enableSounds,
              !configurationStore.config.doNotDisturb else {
            return
        }
        let now = Date()
        soundCooldowns = SessionMemoryPolicy.compactCooldowns(soundCooldowns, now: now)
        if let lastPlayed = soundCooldowns[key],
           now.timeIntervalSince(lastPlayed) < minimumInterval {
            return
        }
        soundCooldowns[key] = now
        soundPlayer(kind, configurationStore.config.soundTheme)
    }

    func assistantMessage(from event: AgentEvent) -> String? {
        let object = event.payload.objectValue ?? [:]
        let candidates = [
            object["codex_last_assistant_message"]?.stringValue,
            object["last_assistant_message"]?.stringValue,
            object["last_agent_message"]?.stringValue,
            object["assistant_response"]?.stringValue,
            object["type"]?.stringValue == "agent_message" ? object["message"]?.stringValue : nil
        ]
        return candidates.compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return DisplayTextSanitizer.sanitize(String(value.prefix(700)))
        }.first
    }

    private var soundsDisabledText: String {
        AppText.pick(
            configurationStore.config.language,
            english: "Sounds are off",
            japanese: "サウンドはオフです",
            chinese: "声音已关闭"
        )
    }
}
