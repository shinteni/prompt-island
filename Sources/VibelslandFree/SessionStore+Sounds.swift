import VibelslandFreeCore
import Foundation


extension SessionStore {
    func playSoundPreview(_ kind: RetroSoundKind) {
        guard configurationStore.config.enableSounds else {
            lastError = "声音已关闭"
            return
        }
        RetroSoundPlayer.shared.play(kind, theme: configurationStore.config.soundTheme)
        lastError = nil
    }

    func playAllSoundPreviews() {
        guard configurationStore.config.enableSounds else {
            lastError = "声音已关闭"
            return
        }
        lastError = nil
        Task { @MainActor in
            let kinds: [RetroSoundKind] = [
                .taskStarted,
                .toolTick,
                .taskCompleted,
                .taskFailed,
                .approval
            ]
            for kind in kinds {
                RetroSoundPlayer.shared.play(kind, theme: configurationStore.config.soundTheme)
                try? await Task.sleep(nanoseconds: 360_000_000)
            }
        }
    }

    func playEventSound(event: AgentEvent, previous: AgentSession?, current: AgentSession) {
        playStatusTransitionSound(previous: previous, current: current)

        switch event.kind {
        case .tool, .subagent:
            playSound(.toolTick, key: "tool:\(current.id)", minimumInterval: 0.85)
        case .prompt, .session:
            if current.status.isActiveVisual {
                playSound(.taskStarted, key: "start:\(current.id)", minimumInterval: 2.0)
            }
        case .approval:
            playSound(.approval, key: "approval:\(current.id)", minimumInterval: 1.0)
        case .notification, .status:
            break
        }
    }

    func playStatusTransitionSound(previous: AgentSession?, current: AgentSession) {
        guard let previous,
              previous.status != current.status else {
            return
        }

        switch current.status {
        case .thinking, .runningTool:
            if !previous.status.isActiveVisual {
                playSound(.taskStarted, key: "start:\(current.id)", minimumInterval: 2.0)
            }
        case .done:
            playSound(.taskCompleted, key: "done:\(current.id)", minimumInterval: 4.0)
        case .failed:
            playSound(.taskFailed, key: "failed:\(current.id)", minimumInterval: 4.0)
        case .waitingApproval, .waitingQuestion:
            playSound(.approval, key: "approval:\(current.id)", minimumInterval: 1.0)
        case .idle:
            break
        }
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
        RetroSoundPlayer.shared.play(kind, theme: configurationStore.config.soundTheme)
    }

    func assistantMessage(from event: AgentEvent) -> String? {
        let object = event.payload.objectValue ?? [:]
        let candidates = [
            object["codex_last_assistant_message"]?.stringValue,
            object["last_assistant_message"]?.stringValue,
            object["last_agent_message"]?.stringValue,
            object["assistant_response"]?.stringValue,
            object["message"]?.stringValue
        ]
        return candidates.compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return DisplayTextSanitizer.sanitize(String(value.prefix(700)))
        }.first
    }
}
