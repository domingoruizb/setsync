import Foundation
import SwiftData

/// specs/01-system-spec.md §1.4 (HealthKit daily snapshot)
@Model
final class DailySummaryMetrics {
    @Attribute(.unique) var date: Date
    var stepCount: Int
    var activeEnergyBurnedKcal: Double
    var restingEnergyBurnedKcal: Double

    init(
        date: Date,
        stepCount: Int,
        activeEnergyBurnedKcal: Double,
        restingEnergyBurnedKcal: Double
    ) {
        self.date = date
        self.stepCount = stepCount
        self.activeEnergyBurnedKcal = activeEnergyBurnedKcal
        self.restingEnergyBurnedKcal = restingEnergyBurnedKcal
    }
}
