import SwiftUI
import SwiftData
import Combine
import HealthKit

public protocol HealthDataService: AnyObject {
    func requestAuthorization() async throws -> AuthorizationResult
    
    func fetchLatestWeight() async throws -> Double?
    func fetchLatestHeight() async throws -> Double?
    func fetchSex() throws -> HKBiologicalSex?
    func fetchAge() throws -> Int?
    
    func fetchEnergyToday(for id: HKQuantityTypeIdentifier) async throws -> Double
    func fetchEnergyDailySums(for id: HKQuantityTypeIdentifier, in interval: DateInterval) async throws -> [Date : Double]
}
