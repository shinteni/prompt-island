import AppKit
import VibelslandFreeCore
import AVFoundation
import Foundation

enum RetroSoundKind: Hashable {
    case launch
    case taskStarted
    case toolTick
    case taskCompleted
    case taskFailed
    case approval
}

@MainActor
final class RetroSoundPlayer {
    static let shared = RetroSoundPlayer()

    private var players: [AVAudioPlayer] = []
    private var generatedDataCache: [SoundCacheKey: Data] = [:]
    private var systemSoundCache: [RetroSoundKind: NSSound] = [:]
    private var preparedPlayers: [SoundCacheKey: AVAudioPlayer] = [:]

    private init() {}

    /// 预热：提前生成波形并让播放器完成缓冲，避免首次播放时的
    /// 音频引擎初始化卡顿（启动动画中途播声音会掉帧就是这个原因）。
    func prepare(_ kind: RetroSoundKind, theme: SoundTheme = .soft) {
        if theme == .system {
            if systemSoundCache[kind] == nil, let sound = NSSound(named: kind.systemSoundName) {
                systemSoundCache[kind] = sound
            }
            return
        }
        let key = SoundCacheKey(kind: kind, theme: theme.rawValue)
        guard preparedPlayers[key] == nil else { return }
        let data = generatedData(for: kind, theme: theme)
        guard let player = try? AVAudioPlayer(data: data) else { return }
        player.volume = kind.volume(for: theme)
        player.prepareToPlay()
        preparedPlayers[key] = player
    }

    func play(_ kind: RetroSoundKind, theme: SoundTheme = .soft) {
        if theme == .system {
            playSystemSound(kind)
            return
        }

        let key = SoundCacheKey(kind: kind, theme: theme.rawValue)
        if let prepared = preparedPlayers.removeValue(forKey: key) {
            players.removeAll { !$0.isPlaying }
            players.append(prepared)
            prepared.play()
            return
        }

        do {
            let data = generatedData(for: kind, theme: theme)
            let player = try AVAudioPlayer(data: data)
            player.volume = kind.volume(for: theme)
            player.prepareToPlay()
            players.removeAll { !$0.isPlaying }
            players.append(player)
            player.play()
        } catch {
            playSystemSound(kind)
        }
    }

    func playApprovalPing() {
        play(.approval)
    }

    private func playSystemSound(_ kind: RetroSoundKind) {
        if let sound = systemSoundCache[kind] {
            sound.play()
            return
        }
        guard let sound = NSSound(named: kind.systemSoundName) else { return }
        systemSoundCache[kind] = sound
        sound.play()
    }

    private func generatedData(for kind: RetroSoundKind, theme: SoundTheme) -> Data {
        let key = SoundCacheKey(kind: kind, theme: theme.rawValue)
        if let cached = generatedDataCache[key] {
            return cached
        }

        let data: Data
        switch theme {
        case .eightBit:
            data = Self.makeSquareWaveWAV(notes: kind.retroNotes)
        case .soft:
            data = Self.makeSineWaveWAV(notes: kind.softNotes)
        case .glass:
            data = Self.makeGlassWaveWAV(notes: kind.glassNotes)
        case .system:
            data = Data()
        }
        generatedDataCache[key] = data
        return data
    }

    private static func makeSquareWaveWAV(notes: [(frequency: Double, duration: Double)]) -> Data {
        let sampleRate = 22_050
        let pauseSamples = Int(Double(sampleRate) * 0.012)
        var samples: [UInt8] = []

        for note in notes {
            let count = max(1, Int(Double(sampleRate) * note.duration))
            for index in 0..<count {
                let phase = (Double(index) * note.frequency / Double(sampleRate)).truncatingRemainder(dividingBy: 1)
                let envelope = min(1.0, Double(index) / 120.0) * min(1.0, Double(count - index) / 180.0)
                let amplitude = UInt8(42 * envelope)
                samples.append(phase < 0.5 ? 128 + amplitude : 128 - amplitude)
            }
            samples.append(contentsOf: Array(repeating: 128, count: pauseSamples))
        }

        var data = Data()
        data.appendASCII("RIFF")
        data.appendUInt32LE(UInt32(36 + samples.count))
        data.appendASCII("WAVE")
        data.appendASCII("fmt ")
        data.appendUInt32LE(16)
        data.appendUInt16LE(1)
        data.appendUInt16LE(1)
        data.appendUInt32LE(UInt32(sampleRate))
        data.appendUInt32LE(UInt32(sampleRate))
        data.appendUInt16LE(1)
        data.appendUInt16LE(8)
        data.appendASCII("data")
        data.appendUInt32LE(UInt32(samples.count))
        data.append(contentsOf: samples)
        return data
    }

    private static func makeSineWaveWAV(notes: [SoundNote]) -> Data {
        make16BitWAV(notes: notes, sampleRate: 44_100, mode: .soft)
    }

    private static func makeGlassWaveWAV(notes: [SoundNote]) -> Data {
        make16BitWAV(notes: notes, sampleRate: 44_100, mode: .glass)
    }

    private static func make16BitWAV(notes: [SoundNote], sampleRate: Int, mode: GeneratedWaveMode) -> Data {
        let pauseSamples = Int(Double(sampleRate) * 0.018)
        var samples: [Int16] = []

        for note in notes {
            let count = max(1, Int(Double(sampleRate) * note.duration))
            for index in 0..<count {
                let t = Double(index) / Double(sampleRate)
                let progress = Double(index) / Double(max(count - 1, 1))
                let attack = min(1.0, progress / 0.08)
                let release = pow(max(0, 1 - progress), mode.releasePower)
                let envelope = attack * release
                let base = sin(2 * Double.pi * note.frequency * t)
                let shaped: Double
                switch mode {
                case .soft:
                    shaped = base
                case .glass:
                    shaped = base * 0.72
                        + sin(2 * Double.pi * note.frequency * 1.72 * t) * 0.20
                        + sin(2 * Double.pi * note.frequency * 2.51 * t) * 0.08
                }
                let value = shaped * envelope * note.gain * 22_000
                samples.append(Int16(max(-32_000, min(32_000, value))))
            }
            samples.append(contentsOf: Array(repeating: 0, count: pauseSamples))
        }

        var data = Data()
        data.appendASCII("RIFF")
        data.appendUInt32LE(UInt32(36 + samples.count * 2))
        data.appendASCII("WAVE")
        data.appendASCII("fmt ")
        data.appendUInt32LE(16)
        data.appendUInt16LE(1)
        data.appendUInt16LE(1)
        data.appendUInt32LE(UInt32(sampleRate))
        data.appendUInt32LE(UInt32(sampleRate * 2))
        data.appendUInt16LE(2)
        data.appendUInt16LE(16)
        data.appendASCII("data")
        data.appendUInt32LE(UInt32(samples.count * 2))
        for sample in samples {
            data.appendInt16LE(sample)
        }
        return data
    }
}

private struct SoundCacheKey: Hashable {
    let kind: RetroSoundKind
    let theme: String
}

private struct SoundNote {
    var frequency: Double
    var duration: Double
    var gain: Double = 1.0
}

private enum GeneratedWaveMode {
    case soft
    case glass

    var releasePower: Double {
        switch self {
        case .soft: 1.55
        case .glass: 2.45
        }
    }
}

private extension RetroSoundKind {
    var retroNotes: [(frequency: Double, duration: Double)] {
        switch self {
        case .launch:
            [
                (frequency: 520, duration: 0.040),
                (frequency: 780, duration: 0.055),
                (frequency: 1_040, duration: 0.060)
            ]
        case .taskStarted:
            [
                (frequency: 660, duration: 0.045),
                (frequency: 990, duration: 0.050)
            ]
        case .toolTick:
            [
                (frequency: 1_180, duration: 0.030),
                (frequency: 920, duration: 0.026)
            ]
        case .taskCompleted:
            [
                (frequency: 784, duration: 0.040),
                (frequency: 988, duration: 0.050),
                (frequency: 1_318, duration: 0.070)
            ]
        case .taskFailed:
            [
                (frequency: 440, duration: 0.070),
                (frequency: 330, duration: 0.080)
            ]
        case .approval:
            [
                (frequency: 880, duration: 0.055),
                (frequency: 1_320, duration: 0.045),
                (frequency: 1_760, duration: 0.070)
            ]
        }
    }

    var softNotes: [SoundNote] {
        switch self {
        case .launch:
            [
                SoundNote(frequency: 392.00, duration: 0.070, gain: 0.46),
                SoundNote(frequency: 587.33, duration: 0.090, gain: 0.44),
                SoundNote(frequency: 783.99, duration: 0.120, gain: 0.42)
            ]
        case .taskStarted:
            [
                SoundNote(frequency: 523.25, duration: 0.080, gain: 0.62),
                SoundNote(frequency: 659.25, duration: 0.105, gain: 0.58)
            ]
        case .toolTick:
            [
                SoundNote(frequency: 740.00, duration: 0.045, gain: 0.36)
            ]
        case .taskCompleted:
            [
                SoundNote(frequency: 659.25, duration: 0.075, gain: 0.52),
                SoundNote(frequency: 783.99, duration: 0.085, gain: 0.54),
                SoundNote(frequency: 1_046.50, duration: 0.145, gain: 0.50)
            ]
        case .taskFailed:
            [
                SoundNote(frequency: 392.00, duration: 0.105, gain: 0.58),
                SoundNote(frequency: 293.66, duration: 0.145, gain: 0.56)
            ]
        case .approval:
            [
                SoundNote(frequency: 587.33, duration: 0.085, gain: 0.58),
                SoundNote(frequency: 880.00, duration: 0.120, gain: 0.56)
            ]
        }
    }

    var glassNotes: [SoundNote] {
        switch self {
        case .launch:
            [
                SoundNote(frequency: 783.99, duration: 0.080, gain: 0.34),
                SoundNote(frequency: 1_174.66, duration: 0.105, gain: 0.32),
                SoundNote(frequency: 1_568.00, duration: 0.135, gain: 0.28)
            ]
        case .taskStarted:
            [
                SoundNote(frequency: 880.00, duration: 0.090, gain: 0.42),
                SoundNote(frequency: 1_174.66, duration: 0.135, gain: 0.38)
            ]
        case .toolTick:
            [
                SoundNote(frequency: 1_318.51, duration: 0.052, gain: 0.24)
            ]
        case .taskCompleted:
            [
                SoundNote(frequency: 783.99, duration: 0.090, gain: 0.36),
                SoundNote(frequency: 1_046.50, duration: 0.110, gain: 0.38),
                SoundNote(frequency: 1_568.00, duration: 0.180, gain: 0.32)
            ]
        case .taskFailed:
            [
                SoundNote(frequency: 466.16, duration: 0.130, gain: 0.40),
                SoundNote(frequency: 349.23, duration: 0.170, gain: 0.38)
            ]
        case .approval:
            [
                SoundNote(frequency: 987.77, duration: 0.085, gain: 0.42),
                SoundNote(frequency: 1_479.98, duration: 0.130, gain: 0.40)
            ]
        }
    }

    func volume(for theme: SoundTheme) -> Float {
        switch theme {
        case .eightBit:
            return retroVolume
        case .soft:
            return softVolume
        case .glass:
            return glassVolume
        case .system:
            return 1.0
        }
    }

    private var retroVolume: Float {
        switch self {
        case .launch:
            0.34
        case .toolTick:
            0.30
        case .taskStarted:
            0.42
        case .taskCompleted:
            0.48
        case .taskFailed:
            0.46
        case .approval:
            0.58
        }
    }

    private var softVolume: Float {
        switch self {
        case .launch:
            0.38
        case .toolTick:
            0.26
        case .taskStarted:
            0.38
        case .taskCompleted:
            0.42
        case .taskFailed:
            0.40
        case .approval:
            0.46
        }
    }

    private var glassVolume: Float {
        switch self {
        case .launch:
            0.36
        case .toolTick:
            0.24
        case .taskStarted:
            0.34
        case .taskCompleted:
            0.40
        case .taskFailed:
            0.38
        case .approval:
            0.44
        }
    }

    var systemSoundName: String {
        switch self {
        case .launch:
            "Pop"
        case .taskFailed:
            "Basso"
        case .taskCompleted:
            "Glass"
        case .approval:
            "Ping"
        case .taskStarted:
            "Pop"
        case .toolTick:
            "Tink"
        }
    }
}

private extension Data {
    mutating func appendASCII(_ string: String) {
        append(contentsOf: string.utf8)
    }

    mutating func appendUInt16LE(_ value: UInt16) {
        append(contentsOf: [
            UInt8(value & 0xff),
            UInt8((value >> 8) & 0xff)
        ])
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        append(contentsOf: [
            UInt8(value & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 24) & 0xff)
        ])
    }

    mutating func appendInt16LE(_ value: Int16) {
        let unsigned = UInt16(bitPattern: value)
        appendUInt16LE(unsigned)
    }
}
