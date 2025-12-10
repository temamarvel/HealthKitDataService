//
//  Calendar+StartOf.swift
//  HealthKitDataService
//
//  Created by Artem Denisov on 10.12.2025.
//

import Foundation

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        let components = dateComponents([.year, .month], from: date)
        return self.date(from: components)!
    }
}
