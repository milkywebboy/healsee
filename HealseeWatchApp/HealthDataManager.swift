import Foundation
import HealthKit

@MainActor
final class HealthDataManager: ObservableObject {
    private let healthStore = HKHealthStore()

    @Published var dailySteps: Int = 0
    @Published var heartRateText: String = "-- bpm"
    @Published var sleepDurationText: String = "-- 時間"
    @Published var recoveryText: String = "--"
    @Published var readinessScore: Int?
    @Published var insights: [String] = []

    private var calendar: Calendar { Calendar.current }

    func requestAuthorization() async throws -> Bool {
        let readTypes: Set = [
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        ]
        return try await withCheckedThrowingContinuation { continuation in
            healthStore.requestAuthorization(toShare: [], read: readTypes) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }

    func refreshAllData() async {
        async let steps = fetchSteps()
        async let heartRate = fetchRestingHeartRate()
        async let sleep = fetchLastNightSleep()

        let results = await (steps, heartRate, sleep)
        publish(steps: results.0, heartRate: results.1, sleepHours: results.2)
    }

    private func publish(steps: Int?, heartRate: Double?, sleepHours: Double?) {
        if let steps {
            dailySteps = steps
        }
        if let heartRate {
            heartRateText = String(format: "%.0f bpm", heartRate)
        }
        if let sleepHours {
            sleepDurationText = String(format: "%.1f 時間", sleepHours)
        }
        readinessScore = estimateReadiness(steps: steps, heartRate: heartRate, sleepHours: sleepHours)
        recoveryText = readinessScore.map { "\($0) / 100" } ?? "--"
        insights = buildInsights(steps: steps, heartRate: heartRate, sleepHours: sleepHours, readiness: readinessScore)
    }

    private func fetchSteps() async -> Int? {
        guard let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return nil }
        let startOfDay = calendar.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date())
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: stepsType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                let count = stats?.sumQuantity()?.doubleValue(for: .count())
                continuation.resume(returning: count.map { Int($0) })
            }
            healthStore.execute(query)
        }
    }

    private func fetchRestingHeartRate() async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: calendar.date(byAdding: .day, value: -7, to: Date()), end: Date())
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                let rates = samples?
                    .compactMap { ($0 as? HKQuantitySample)?.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) }
                continuation.resume(returning: rates?.average)
            }
            healthStore.execute(query)
        }
    }

    private func fetchLastNightSleep() async -> Double? {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        let start = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date()))
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                let sleepSamples = samples?.compactMap { $0 as? HKCategorySample } ?? []
                let asleep = sleepSamples
                    .filter { $0.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue || $0.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue || $0.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue }
                    .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                continuation.resume(returning: asleep > 0 ? asleep / 3600 : nil)
            }
            healthStore.execute(query)
        }
    }

    private func estimateReadiness(steps: Int?, heartRate: Double?, sleepHours: Double?) -> Int? {
        guard let steps, let heartRate, let sleepHours else { return nil }
        let normalizedSteps = min(Double(steps) / 10000.0, 1.0)
        let restingScore = max(0, min((80 - heartRate) / 40.0, 1.0))
        let sleepScore = min(sleepHours / 8.0, 1.0)
        let composite = (normalizedSteps * 0.35) + (sleepScore * 0.4) + (restingScore * 0.25)
        return Int((composite * 100).rounded())
    }

    private func buildInsights(steps: Int?, heartRate: Double?, sleepHours: Double?, readiness: Int?) -> [String] {
        var results: [String] = []
        if let readiness {
            if readiness < 50 {
                results.append("今日は回復重視の日。無理のない活動に抑え、ストレッチや軽い有酸素運動を取り入れましょう。")
            } else if readiness < 75 {
                results.append("バランスのとれた日です。ウォーキングや中強度のワークアウトで体を動かしましょう。")
            } else {
                results.append("コンディション良好。インターバルトレーニングや筋トレでパフォーマンスを高めるチャンスです。")
            }
        }
        if let sleepHours, sleepHours < 7 {
            results.append("睡眠が短めです。就寝前のスクリーンタイムを減らし、リラックス習慣を取り入れて睡眠の質を高めましょう。")
        }
        if let heartRate, heartRate > 65 {
            results.append("安静時心拍数が高め。水分補給とストレス管理を意識して、深呼吸や短い散歩を挟みましょう。")
        }
        if let steps, steps < 6000 {
            results.append("歩数が少なめです。エレベーターの代わりに階段を使うなど、こまめに歩数を稼ぎましょう。")
        }
        return results.isEmpty ? ["データを取得しました。今日も健康的に過ごしましょう！"] : results
    }
}

private extension Array where Element == Double {
    var average: Double? {
        guard !isEmpty else { return nil }
        let total = reduce(0, +)
        return total / Double(count)
    }
}
