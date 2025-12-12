//
//  HealthDataCache.swift
//  HealthKitDataService
//
//  Created by Artem Denisov on 12.12.2025.
//

import Foundation
import HealthKit

enum PositionToAdd{
    case left
    case right
    case middle
}

struct DailyInfo {
    let date: Date
    let value: Double
}

private struct HealthDataCache {
    private(set) var range: DateInterval? = nil
    private(set) var samples: [DailyInfo] = []
    let id: HKQuantityTypeIdentifier
    
    typealias Loader = (_ id: HKQuantityTypeIdentifier, _ interval: DateInterval) async throws -> HKStatisticsCollection?
    private let loadData: Loader

    init(id: HKQuantityTypeIdentifier, loadData: @escaping Loader) {
        self.id = id
        self.loadData = loadData
    }
    
    func getData(for interval: DateInterval) async throws -> [DailyInfo]{
        try await ensureDataChached(for: interval)
        return try await getCachedData(for: interval)
    }
    
    func getCachedData(for interval: DateInterval) async throws -> [DailyInfo]{
        
    }
    
    
    func ensureDataChached(for interval: DateInterval) async throws {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else {
            return
        }
        
        var leftInterval: DateInterval? = nil
        var rightInterval: DateInterval? = nil
        
        if let cachedRange = range {
            // Нужен интервал левее уже имеющегося
            if interval.start < cachedRange.start {
                leftInterval = DateInterval(start: interval.start, end: cachedRange.start)
            }
            
            // Нужен интервал правее уже имеющегося
            if interval.end > cachedRange.end {
                rightInterval = DateInterval(start: cachedRange.end, end: interval.end)
                
            }
        } else {
            let samplesToAdd = try await getSamples(for: id, for: interval)
            try await addToCache(samples: samplesToAdd, for: interval)
                
        }
        
        // Если всё уже покрыто кэшем — выходим
        if let lInterval = leftInterval {
            let samplesToAdd = try await getSamples(for: id, for: lInterval)
            try await addToCache(samples: samplesToAdd, for: lInterval)
        }
        
        if let rInterval = rightInterval {
            let samplesToAdd = try await getSamples(for: id, for: rInterval)
            try await addToCache(samples: samplesToAdd, for: rInterval)
        }
        
        // Для каждого недостающего кусочка делаем запрос в HealthKit
//        let sort = SortDescriptor<HKQuantitySample>(\.startDate, order: .forward)
//        
//        for part in intervalsToFetch {
//            let predicate = HKSamplePredicate.quantitySample(
//                type: type,
//                predicate: HKQuery.predicateForSamples(withStart: part.start, end: part.end)
//            )
//            
//            let descriptor = HKSampleQueryDescriptor(
//                predicates: [predicate],
//                sortDescriptors: [sort]
//            )
//            
//            let results = try await descriptor.result(for: healthStore)
//            let newSamples = results.compactMap { $0 as? HKQuantitySample }
//            
//            if !newSamples.isEmpty {
//                cache.samples.append(contentsOf: newSamples)
//            }
//        }
//        
//        // Сортируем общий массив и расширяем диапазон
//        cache.samples.sort { $0.startDate < $1.startDate }
//        
//        let newRange: DateInterval
//        if let cachedRange = cache.range {
//            let start = min(cachedRange.start, interval.start)
//            let end = max(cachedRange.end, interval.end)
//            newRange = DateInterval(start: start, end: end)
//        } else {
//            newRange = interval
//        }
//        cache.range = newRange
//        
//        energySampleCaches[id] = cache
        
    }
    
    func addToCache(newSamples: [DailyInfo], for interval: DateInterval, to position: PositionToAdd ) async throws {
        switch position {
        case .left:
            let oldSamples = samples
            var mergedSamples: [DailyInfo] = []
            mergedSamples.reserveCapacity(oldSamples.count + newSamples.count)
            mergedSamples.append(contentsOf: newSamples)
            mergedSamples.append(contentsOf: oldSamples)
            
        case .right:
        case .middle:
            
        }
        
    }
    
    func getSamples(for id: HKQuantityTypeIdentifier, for interval: DateInterval) async throws -> [DailyInfo] {
        guard let collection = try await loadData(id, interval) else {
            return []
        }
        
        var result: [DailyInfo] = []
        
        collection.enumerateStatistics(from: interval.start, to: interval.end) { stats, _ in
            let date = stats.startDate
            let kcal = stats.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
            result.append(DailyInfo(date: date, value: kcal))
        }
        
        return result
    }
}
