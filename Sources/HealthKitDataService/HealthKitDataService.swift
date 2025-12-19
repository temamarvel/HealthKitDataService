import Foundation
import HealthKit
import Combine

public final class HealthKitDataService: ObservableObject, HealthDataService {
    private let healthStore = HKHealthStore()
    private(set) var isAuthorized: Bool = false
    // TODO:
    public var basalEnergyDelta: Double = 0
    
    private lazy var basalEnergyCache = HealthDataCache(id: .basalEnergyBurned) { id, interval in
        try await self.fetchEnergyDailyStatisticsCollection(for: id, in: interval, by: .day)
    }
    
    private lazy var activeEnergyCache = HealthDataCache(id: .activeEnergyBurned) { id, interval in
        try await self.fetchEnergyDailyStatisticsCollection(for: id, in: interval, by: .day)
    }
    
    private var readTypes: Set<HKObjectType> {
        var set = Set<HKObjectType>()
        if let weight = HKObjectType.quantityType(forIdentifier: .bodyMass) {
            set.insert(weight)
        }
        if let height = HKObjectType.quantityType(forIdentifier: .height) {
            set.insert(height)
        }
        if let dob = HKObjectType.characteristicType(forIdentifier: .dateOfBirth) {
            set.insert(dob)
        }
        if let sex = HKObjectType.characteristicType(forIdentifier: .biologicalSex) {
            set.insert(sex)
        }
        if let activeEnergyBurned = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
            set.insert(activeEnergyBurned)
        }
        if let basalEnergyBurned = HKObjectType.quantityType(forIdentifier: .basalEnergyBurned) {
            set.insert(basalEnergyBurned)
        }
        return set
    }
    
    public init() { }
    
    public func requestAuthorization() async throws -> AuthorizationResult {
        guard HKHealthStore.isHealthDataAvailable() else {
            return AuthorizationResult(isAuthorized: false)
        }
        
        do {
            try await healthStore.requestAuthorization(toShare: [], read: readTypes)
            return AuthorizationResult(isAuthorized: true)
        } catch {
            print("HealthKit authorization failed: \(error.localizedDescription)")
            throw error
        }
    }
    
    public func fetchLatestWeight() async throws -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return nil }
        
        // Swift sort descriptor, а не NSSortDescriptor
        let sort: SortDescriptor<HKQuantitySample> = .init(\.startDate, order: .reverse)
        let predicate = HKSamplePredicate.quantitySample(type: type)
        
        let descriptor = HKSampleQueryDescriptor(
            predicates: [predicate],
            sortDescriptors: [sort],
            limit: 1
        )
        
        let results = try await descriptor.result(for: healthStore)
        guard let sample = results.first as? HKQuantitySample else { return nil }
        return sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
    }
    
    public func fetchLatestHeight() async throws -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .height) else { return nil }
        
        let sort: SortDescriptor<HKQuantitySample> = .init(\.startDate, order: .reverse)
        let predicate = HKSamplePredicate.quantitySample(type: type)
        
        let descriptor = HKSampleQueryDescriptor(
            predicates: [predicate],
            sortDescriptors: [sort],
            limit: 1
        )
        
        let results = try await descriptor.result(for: healthStore)
        guard let sample = results.first as? HKQuantitySample else { return nil }
        
        let meters = sample.quantity.doubleValue(for: .meter())
        return meters * 100.0
    }
    
    public func fetchSex() throws -> HKBiologicalSex? {
        return try? healthStore.biologicalSex().biologicalSex
    }
    
    public func fetchAge() throws -> Int? {
        var calculatedAge: Int?
        
        if let components = try? healthStore.dateOfBirthComponents(),
           let birthDate = Calendar.current.date(from: components) {
            let now = Date()
            let ageComponents = Calendar.current.dateComponents([.year], from: birthDate, to: now)
            calculatedAge = ageComponents.year
        }
        
        return calculatedAge
    }
    
    public func fetchEnergyToday(for id: HKQuantityTypeIdentifier) async throws -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return 0 }
        
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let predicate = HKSamplePredicate.quantitySample(
            type: type,
            predicate: HKQuery.predicateForSamples(withStart: startOfDay, end: now)
        )
        
        let statsDescriptor = HKStatisticsQueryDescriptor(
            predicate: predicate,
            options: .cumulativeSum
        )
        
        let stats = try await statsDescriptor.result(for: healthStore)
        
        let rawKcal = stats?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
        let adjustedKcal = (id == .basalEnergyBurned) ? (rawKcal - basalEnergyDelta) : rawKcal
        let kcal = max(0, adjustedKcal)
        
        return kcal
    }
    
    func fetchEnergyDailyStatisticsCollection(
        for id: HKQuantityTypeIdentifier,
        in interval: DateInterval,
        by aggregate: AggregatePeriod
    ) async throws -> HKStatisticsCollection? {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return nil }
        let cal = Calendar.current
        
        let predicate = HKSamplePredicate.quantitySample(
            type: type,
            predicate: HKQuery.predicateForSamples(withStart: interval.start, end: interval.end)
        )
        
        let statsDesc = HKStatisticsCollectionQueryDescriptor(
            predicate: predicate,
            options: .cumulativeSum,
            anchorDate: aggregate == .day ? cal.startOfDay(for: interval.start) : cal.startOfMonth(for: interval.start),
            intervalComponents: aggregate == .day ? DateComponents(day: 1) : DateComponents(month: 1)
        )
        return try await statsDesc.result(for: healthStore)
    }
    
    private func getFromCache(id: HKQuantityTypeIdentifier, for interval: DateInterval, by aggregate: AggregatePeriod) async throws -> [any EnergyInfo]? {
        if id == .activeEnergyBurned{
            return try await activeEnergyCache.getData(for: interval, by: aggregate)
        }
        if id == .basalEnergyBurned{
            return try await basalEnergyCache.getData(for: interval, by: aggregate)
        }
        return nil
    }
    
    public func fetchEnergySums(
        for id: HKQuantityTypeIdentifier,
        in interval: DateInterval,
        by aggregate: AggregatePeriod
    ) async throws -> [Date : Double] {
        let collection = try await getFromCache(id: id, for: interval, by: aggregate)
        
        var result: [Date: Double] = [:]
        
        if let collection = collection{
            for dayInfo in collection {
                let date = dayInfo.date
                let kcal = id == .basalEnergyBurned ? dayInfo.value - basalEnergyDelta : dayInfo.value
                result[date] = kcal
            }
            
            var startOfLastPeriod: Date = Calendar.current.startOfDay(for: Date())
            switch aggregate {
            case .day: startOfLastPeriod
            case .week: startOfLastPeriod// TODO: implement
            case .month: startOfLastPeriod = Calendar.current.startOfMonth(for: Date())
            }
            
            result[startOfLastPeriod] = try await fetchEnergyToday(for: id)
        }
        
        return result
    }
}
