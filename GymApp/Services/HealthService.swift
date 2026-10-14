import Foundation
import GRDB
import HealthKit

/// Card 6.2: read-only daily steps and body mass from Apple Health. Access is asked for from
/// Settings, never at launch; once granted, every launch and return to the app re-syncs the
/// last year so edits made in Health are mirrored.
@MainActor
final class HealthService {
    static let shared = HealthService()
    static let didSync = Notification.Name("HealthService.didSync")
    private let store = HKHealthStore()
    private let connectedKey = "healthConnected"
    private let lastSyncKey = "healthLastSync"
    private let types: Set<HKObjectType> = [HKQuantityType(.stepCount), HKQuantityType(.bodyMass)]

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }
    var isConnected: Bool { UserDefaults.standard.bool(forKey: connectedKey) }
    var lastSync: Date? { UserDefaults.standard.object(forKey: lastSyncKey) as? Date }

    func connect() async throws {
        guard isAvailable else { throw HealthError.unavailable }
        try await store.requestAuthorization(toShare: [], read: types)
        UserDefaults.standard.set(true, forKey: connectedKey)
    }

    func disconnect() { UserDefaults.standard.set(false, forKey: connectedKey) }

    /// Reads daily totals for the last `days` days and stores them. Returns the number of days
    /// with any value. Health doesn't say whether read access was granted, so an empty result
    /// may mean "denied" as much as "no data".
    @discardableResult
    func sync(into db: AppDatabase, days: Int = 365, now: Date = .now) async throws -> Int {
        guard isAvailable, isConnected else { return 0 }
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: now).addingTimeInterval(86_400)
        guard let start = calendar.date(byAdding: .day, value: -days, to: end) else { return 0 }
        async let steps = dailySteps(from: start, to: end)
        async let weights = dailyWeights(from: start, to: end)
        let (s, w) = try await (steps, weights)
        let allDays = Set(s.keys).union(w.keys).sorted()
        let rows = allDays.map { HealthWrites.Day(date: $0, steps: s[$0], weightKg: w[$0]) }
        try await db.writer.write { try HealthWrites.upsert($0, days: rows) }
        UserDefaults.standard.set(now, forKey: lastSyncKey)
        NotificationCenter.default.post(name: Self.didSync, object: nil)
        return rows.count
    }

    private func dailySteps(from start: Date, to end: Date) async throws -> [String: Int] {
        let type = HKQuantityType(.stepCount)
        let query = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: HKQuery.predicateForSamples(withStart: start, end: end)),
            options: .cumulativeSum, anchorDate: Calendar.current.startOfDay(for: start), intervalComponents: DateComponents(day: 1))
        let collection = try await query.result(for: store)
        var out: [String: Int] = [:]
        collection.enumerateStatistics(from: start, to: end) { stats, _ in
            if let sum = stats.sumQuantity() {
                out[DayString.from(stats.startDate)] = Int(sum.doubleValue(for: .count()).rounded())
            }
        }
        return out
    }

    /// The last weight recorded each day, in kg.
    private func dailyWeights(from start: Date, to end: Date) async throws -> [String: Double] {
        let query = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.bodyMass), predicate: HKQuery.predicateForSamples(withStart: start, end: end))],
            sortDescriptors: [SortDescriptor(\.startDate)])
        var out: [String: Double] = [:]
        for sample in try await query.result(for: store) {
            out[DayString.from(sample.startDate)] = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
        }
        return out
    }

    enum HealthError: LocalizedError {
        case unavailable
        var errorDescription: String? { "Apple Health isn't available on this device." }
    }
}
