import Foundation
import CoreHaptics

/// Small, bounded Core Haptics patterns for user-facing feedback. Generated
/// apps cannot submit arbitrary audio or open-ended streams.
@MainActor
final class HTMLAppCoreHapticsService {
    private var engine: CHHapticEngine?

    static var available: Bool { CHHapticEngine.capabilitiesForHardware().supportsHaptics }

    func play(_ pulses: [[String: Any]]) throws -> [String: Any] {
        guard Self.available else {
            return ["played": false, "available": false]
        }
        guard !pulses.isEmpty, pulses.count <= 16 else {
            throw HapticError.invalidPattern
        }
        var events: [CHHapticEvent] = []
        for pulse in pulses {
            guard let time = pulse["time"] as? Double,
                  let intensity = pulse["intensity"] as? Double,
                  let sharpness = pulse["sharpness"] as? Double,
                  time.isFinite, intensity.isFinite, sharpness.isFinite,
                  (0...5).contains(time), (0...1).contains(intensity),
                  (0...1).contains(sharpness) else { throw HapticError.invalidPattern }
            events.append(CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(intensity)),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(sharpness))
                ], relativeTime: time))
        }
        let pattern = try CHHapticPattern(events: events, parameters: [])
        if engine == nil {
            engine = try CHHapticEngine()
            engine?.isAutoShutdownEnabled = true
        }
        guard let engine else { throw HapticError.unavailable }
        try engine.start()
        let player = try engine.makePlayer(with: pattern)
        try player.start(atTime: 0)
        return ["played": true, "available": true]
    }

    func stop() {
        engine?.stop(completionHandler: nil)
        engine = nil
    }

    enum HapticError: LocalizedError {
        case invalidPattern, unavailable
        var errorDescription: String? {
            switch self {
            case .invalidPattern: return "Provide 1–16 haptic pulses, each within 5 seconds and intensity/sharpness from 0 to 1."
            case .unavailable: return "Core Haptics is unavailable on this device."
            }
        }
    }
}
