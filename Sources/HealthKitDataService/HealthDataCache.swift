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
    private(set) var daylyInfos: [DailyEnergyInfo] = []
    private(set) var monthlyInfos: [MonthlyEnergyInfo] = []
    let id: HKQuantityTypeIdentifier
    
    typealias Loader = (_ id: HKQuantityTypeIdentifier, _ interval: DateInterval, _ aggravatedBy: AggregatePeriod) async throws -> HKStatisticsCollection?
    private let loadData: Loader

    init(id: HKQuantityTypeIdentifier, loadData: @escaping Loader) {
        self.id = id
        self.loadData = loadData
    }
    
    mutating func getData(for interval: DateInterval, by: AggregatePeriod) async throws -> [any EnergyInfo]{
        try await ensureDataChached(for: interval)
        return try await getCachedData(for: interval)
    }
    
    private func getCachedData(for interval: DateInterval) async throws -> [any EnergyInfo]{
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
            let samplesToAdd = try await getSamples(for: id, for: interval)
            try await addToCache(newSamples: samplesToAdd, for: interval, to: .middle)
                
        }
        
        if let lInterval = leftInterval {
            let samplesToAdd = try await getSamples(for: id, for: lInterval)
            try await addToCache(newSamples: samplesToAdd, for: lInterval, to: .left)
        }
        
        if let rInterval = rightInterval {
            let samplesToAdd = try await getSamples(for: id, for: rInterval)
            try await addToCache(newSamples: samplesToAdd, for: rInterval, to: .right)
        }
    }
    
    private mutating func addToCache(newSamples: [DailyInfo], for interval: DateInterval, to position: PositionToAdd ) async throws {
        switch position {
        case .left:
            let oldSamples = samples
            var mergedSamples: [DailyInfo] = []
            mergedSamples.reserveCapacity(oldSamples.count + newSamples.count)
            mergedSamples.append(contentsOf: newSamples)
            mergedSamples.append(contentsOf: oldSamples)
        case .right:
            samples.append(contentsOf: newSamples)
        case .middle:
            samples.append(contentsOf: newSamples)
        }
        
        let newStart = min(range?.start ?? interval.start, interval.start)
        let newEnd = max(range?.end ?? interval.end, interval.end)
        range = DateInterval(start: newStart, end: newEnd)
    }
    
    private func getSamples(for id: HKQuantityTypeIdentifier, for interval: DateInterval, by aggregate: AggregatePeriod) async throws -> [any EnergyInfo] {
        guard let collection = try await loadData(id, interval, aggregate) else {
            return []
        }
        
        var result: [any EnergyInfo] = []
        
        let createInfo = { (date: Date, value: Double) -> any EnergyInfo in
            switch aggregate {
            case .day:
                return DailyEnergyInfo(dayStart: date, kcal: value)
            case .month:
                return MonthlyEnergyInfo(monthStart: date, kcal: value)
            }
        }
        
        collection.enumerateStatistics(from: interval.start, to: interval.end) { stats, _ in
            let date = stats.startDate
            let kcal = stats.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
            result.append(createInfo(date, kcal))
        }
        
        return result
    }
}
