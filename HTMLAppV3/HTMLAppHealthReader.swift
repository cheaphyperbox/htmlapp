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

    /// Date-scoped summary; explicit timestamps prevent a missing day from
    /// being confused with a measured zero.
    func readRange(_ quantity: String, start: Date, end: Date) async throws -> [String: Any] {
        guard Self.available else { throw HealthError.unavailable }
        guard start < end, end.timeIntervalSince(start) <= 366 * 86_400 else {
            throw HealthError.invalidRange
        }
        let identifier: HKQuantityTypeIdentifier
        let unit: HKUnit
        switch quantity {
        case "steps": identifier = .stepCount; unit = .count()
        case "distance": identifier = .distanceWalkingRunning; unit = .meter()
        case "activeEnergy": identifier = .activeEnergyBurned; unit = .kilocalorie()
        default: throw HealthError.invalidType
        }
        let type = HKQuantityType.quantityType(forIdentifier: identifier)!
        try await store.requestAuthorization(toShare: [], read: [type])
        return try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, statistics, error in
                if let error { continuation.resume(throwing: error); return }
                let sum = statistics?.sumQuantity()
                let value: Any = sum.map { $0.doubleValue(for: unit) as Any } ?? NSNull()
                continuation.resume(returning: [
                    "quantity": quantity, "value": value, "hasData": sum != nil,
                    "start": start.timeIntervalSince1970, "end": end.timeIntervalSince1970
                ])
            }
            store.execute(query)
        }
    }

    enum HealthError: LocalizedError {
        case unavailable, invalidType, invalidRange
        var errorDescription: String? {
            switch self {
            case .unavailable: return "HealthKit is unavailable on this device or signing configuration."
            case .invalidType: return "Supported quantities: steps, distance, activeEnergy."
            case .invalidRange: return "Health history requires a valid range of up to 366 days."
            }
        }
    }
}
