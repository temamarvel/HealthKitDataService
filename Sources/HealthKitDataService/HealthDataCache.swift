//
//  HealthDataCache.swift
//  HealthKitDataService
//
//  Created by Artem Denisov on 12.12.2025.
//

import Foundation
import HealthKit
import Algorithms

enum PositionToAdd{
    case left
    case right
    case middle
}

//struct DailyInfo {
//    let date: Date
//    let value: Double
//}

struct DailyEnergyInfo: EnergyInfo {
    let id = UUID()
    let dayStart: Date
    let kcal: Double
    
    var date: Date { dayStart }
    var value: Double { kcal }
    var average: Double { kcal }
}

struct MonthlyEnergyInfo: EnergyInfo {
    let id = UUID()
    let monthStart: Date
    let kcal: Double
    
    var date: Date { monthStart }
    var value: Double { kcal }
    var average: Double {
        let calendar = Calendar.current
        
        guard let daysRange = calendar.range(of: .day, in: .month, for: monthStart) else {
            return kcal
        }
        
        let daysCount = daysRange.count
        guard daysCount > 0 else {
            return kcal
        }
        
        return kcal / Double(daysCount)
    }
}

protocol EnergyInfo: Identifiable {
    var date: Date { get }
    var value: Double { get }
    var average: Double { get }
}

struct HealthDataCache {
    private(set) var range: DateInterval? = nil
    private(set) var dailyInfos: [DailyEnergyInfo] = []
    private(set) var monthlyInfos: [MonthlyEnergyInfo] = []
    let id: HKQuantityTypeIdentifier
    
    typealias Loader = (_ id: HKQuantityTypeIdentifier, _ interval: DateInterval) async throws -> HKStatisticsCollection?
    private let loadDailyData: Loader

    init(id: HKQuantityTypeIdentifier, loadData: @escaping Loader) {
        self.id = id
        self.loadDailyData = loadData
    }
    
    mutating func getData(for interval: DateInterval, by aggregate: AggregatePeriod) async throws -> [any EnergyInfo]{
        try await ensureDataChached(for: interval)
        
        switch aggregate {
        case .day:
            return try await getCachedData(samples: dailyInfos, for: interval)
        case .month:
            return try await getCachedData(samples: monthlyInfos, for: interval)
        case .week:
            // TODO:
            return []
        }
    }
    
    private func getCachedData(samples: [any EnergyInfo], for interval: DateInterval) async throws -> [any EnergyInfo]{
        let startIndex = samples.partitioningIndex { sample in
            sample.date >= interval.start
        }

        let endIndex = samples.partitioningIndex { sample in
            sample.date >= interval.end
        }

        return Array(samples[startIndex..<endIndex])
    }
    
    
    private mutating func ensureDataChached(for interval: DateInterval) async throws {
        var leftInterval: DateInterval? = nil
        var rightInterval: DateInterval? = nil
        
        if let cachedRange = range {
            if interval.start < cachedRange.start {
                leftInterval = DateInterval(start: interval.start, end: cachedRange.start)
            }
            if interval.end > cachedRange.end {
                rightInterval = DateInterval(start: cachedRange.end, end: interval.end)
            }
        } else {
            let samplesToAdd = try await getDailySamples(for: id, for: interval)
            try await updateCache(newSamples: samplesToAdd, for: interval, to: .middle)
                
        }
        
        if let lInterval = leftInterval {
            let samplesToAdd = try await getDailySamples(for: id, for: lInterval)
            try await updateCache(newSamples: samplesToAdd, for: lInterval, to: .left)
        }
        
        if let rInterval = rightInterval {
            let samplesToAdd = try await getDailySamples(for: id, for: rInterval)
            try await updateCache(newSamples: samplesToAdd, for: rInterval, to: .right)
        }
    }
    
    private func aggregatedByMonth(dailyInfos: [DailyEnergyInfo], calendar: Calendar = .current) -> [MonthlyEnergyInfo] {
            let groupedByMonth = Dictionary(grouping: dailyInfos) { item in
                let dateComponents = calendar.dateComponents([.year, .month], from: item.date)
                return calendar.date(from: dateComponents)! // это будет 1-е число месяца в 00:00
            }

            return groupedByMonth
                .map { (monthStart, items) in
                    let monthSum = items.reduce(0) { $0 + $1.kcal }
                
                    return MonthlyEnergyInfo(
                        monthStart: monthStart,
                        kcal: monthSum
                    )
                }
                .sorted { $0.monthStart < $1.monthStart }
        }
    
    private mutating func updateCache(newSamples: [DailyEnergyInfo], for interval: DateInterval, to position: PositionToAdd ) async throws {
        switch position {
        case .left:
            let oldSamples = dailyInfos
            var mergedSamples: [DailyEnergyInfo] = []
            mergedSamples.reserveCapacity(oldSamples.count + newSamples.count)
            mergedSamples.append(contentsOf: newSamples)
            mergedSamples.append(contentsOf: oldSamples)
            dailyInfos = mergedSamples
        case .right:
            dailyInfos.append(contentsOf: newSamples)
        case .middle:
            dailyInfos.append(contentsOf: newSamples)
        }
        
        monthlyInfos = aggregatedByMonth(dailyInfos: dailyInfos)
        
        let newStart = min(range?.start ?? interval.start, interval.start)
        let newEnd = max(range?.end ?? interval.end, interval.end)
        range = DateInterval(start: newStart, end: newEnd)
    }
    
    private func getDailySamples(for id: HKQuantityTypeIdentifier, for interval: DateInterval) async throws -> [DailyEnergyInfo] {
        guard let collection = try await loadDailyData(id, interval) else {
            return []
        }
        
        var result: [DailyEnergyInfo] = []
        
        collection.enumerateStatistics(from: interval.start, to: interval.end) { stats, _ in
            let date = stats.startDate
            let kcal = stats.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
            result.append(DailyEnergyInfo(dayStart: date, kcal: kcal))
        }
        
        return result
    }
}
