import Foundation
import HealthKit
import Combine

public final class HealthKitDataService: ObservableObject, HealthDataService {
    private let healthStore = HKHealthStore()
    private(set) var isAuthorized: Bool = false
    
    private lazy var basalEnergyCache = HealthDataCache(id: .basalEnergyBurned) { id, interval in
        try await self.fetchEnergyDailyStatisticsCollection(for: id, in: interval)
    }
    
    private lazy var activeEnergyCache = HealthDataCache(id: .activeEnergyBurned) { id, interval in
        try await self.fetchEnergyDailyStatisticsCollection(for: id, in: interval)
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
    
    public init() {}
    
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
    
    public func fetchTotalEnergyToday() async throws -> Double {
        let basal = try await fetchEnergyToday(for: .basalEnergyBurned)
        let active = try await fetchEnergyToday(for: .activeEnergyBurned)
        return basal + active
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
        let kcal = stats?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
        return kcal
    }
    
    func fetchEnergyDailyStatisticsCollection(
        for id: HKQuantityTypeIdentifier,
        in interval: DateInterval
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
            anchorDate: cal.startOfDay(for: interval.start),
            intervalComponents: DateComponents(day: 1)
        )
        return try await statsDesc.result(for: healthStore)
    }
    
    private func getFromCache(id: HKQuantityTypeIdentifier, for interval: DateInterval) async throws -> [DailyInfo]? {
        if id == .activeEnergyBurned{
            return try await activeEnergyCache.getData(for: interval)
        }
        if id == .basalEnergyBurned{
            return try await basalEnergyCache.getData(for: interval)
        }
        return nil
    }
    
    public func fetchEnergySums(
        for id: HKQuantityTypeIdentifier,
        in interval: DateInterval,
        by: AggregatePeriod
    ) async throws -> [Date : Double] {
        let collection = try await getFromCache(id: id, for: interval)
        
        var result: [Date: Double] = [:]
        
        if let collection = collection{
            for dayInfo in collection {
                let date = dayInfo.date
                let kcal = dayInfo.value
                result[date] = kcal
            }
        }
        
        return result
    }
}
