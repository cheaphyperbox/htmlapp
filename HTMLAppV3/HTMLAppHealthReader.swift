import Foundation
import HealthKit

/// Read-only HealthKit summary service. The operating system owns data-type consent.
@MainActor
final class HTMLAppHealthReader {
    private let store = HKHealthStore()

    static var available: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func readToday(_ quantity: String) async throws -> [String: Any] {
        guard Self.available else { throw HealthError.unavailable }
        let type: HKQuantityType
        let unit: HKUnit
        switch quantity {
        case "steps":
            type = HKObjectType.quantityType(forIdentifier: .stepCount)!
            unit = .count()
        case "distance":
            type = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!
            unit = .meter()
        case "activeEnergy":
            type = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
            unit = .kilocalorie()
        default: throw HealthError.invalidType
        }
        try await store.requestAuthorization(toShare: [], read: [type])
        let start = Calendar.current.startOfDay(for: Date())
        let end = Date()
        return try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, statistics, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let sum = statistics?.sumQuantity()
                let value: Any = sum.map { $0.doubleValue(for: unit) as Any } ?? NSNull()
                continuation.resume(returning: ["quantity": quantity, "value": value, "hasData": sum != nil, "start": start.timeIntervalSince1970, "end": end.timeIntervalSince1970])
            }
            store.execute(query)
        }
    }

    enum HealthError: LocalizedError {
        case unavailable, invalidType
        var errorDescription: String? {
            switch self {
            case .unavailable: return "HealthKit is unavailable on this device or signing configuration."
            case .invalidType: return "Supported quantities: steps, distance, activeEnergy."
            }
        }
    }
}
