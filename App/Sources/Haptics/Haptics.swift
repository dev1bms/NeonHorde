import CoreHaptics
import UIKit
import NeonHordeCore

/// Haptic feedback kinds mapped from world events (GOAL §4).
enum HapticKind: Equatable {
    case light    // gem pickup
    case medium   // player took a hit
    case heavy    // level-up, boss moments, victory/defeat
}

/// Pure event→haptic mapping — unit-testable without hardware.
enum HapticMapping {
    static func haptic(for event: WorldEvent) -> HapticKind? {
        switch event {
        case .gemCollected: return .light
        case .playerHit: return .medium
        case .leveledUp, .bossSpawned, .bossPhase, .victory, .playerDied, .revived: return .heavy
        case .chestCollected: return .heavy
        default: return nil
        }
    }
}

/// CoreHaptics wrapper with simulator guards, lifecycle recovery, and a
/// UIFeedbackGenerator fallback (GOAL §4 Audio & Haptics).
final class Haptics {
    static let shared = Haptics()

    var enabled = true

    private var engine: CHHapticEngine?
    private var engineFailed = false
    private var lastLight: TimeInterval = 0
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)

    private init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            engineFailed = true   // simulator / unsupported — no-op or UIKit fallback
            return
        }
        do {
            let engine = try CHHapticEngine()
            engine.resetHandler = { [weak self] in
                try? self?.engine?.start()
            }
            engine.stoppedHandler = { _ in /* lazily restarted on next play */ }
            try engine.start()
            self.engine = engine
        } catch {
            engineFailed = true
        }
    }

    func play(_ kind: HapticKind) {
        guard enabled else { return }
        if kind == .light {
            // Gem pickups fire constantly — throttle to 1 per 80 ms.
            let now = CACurrentMediaTime()
            guard now - lastLight > 0.08 else { return }
            lastLight = now
        }
        guard let engine, !engineFailed else {
            playFallback(kind)
            return
        }
        let (intensity, sharpness): (Float, Float)
        switch kind {
        case .light: (intensity, sharpness) = (0.35, 0.7)
        case .medium: (intensity, sharpness) = (0.7, 0.4)
        case .heavy: (intensity, sharpness) = (1.0, 0.5)
        }
        let event = CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
        ], relativeTime: 0)
        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try? engine.start()   // lazy restart after interruptions
            try player.start(atTime: 0)
        } catch {
            playFallback(kind)
        }
    }

    private func playFallback(_ kind: HapticKind) {
        #if !targetEnvironment(simulator)
        switch kind {
        case .light: impactLight.impactOccurred()
        case .medium: impactMedium.impactOccurred()
        case .heavy: impactHeavy.impactOccurred()
        }
        #endif
    }
}
