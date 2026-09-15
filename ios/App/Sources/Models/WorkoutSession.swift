import Foundation
import SwiftData

/// specs/01-system-spec.md §1.3
@Model
final class WorkoutSession {
    enum Status: String, Codable {
        case inProgress
        case completed
        case discarded
    }

    @Attribute(.unique) var id: UUID
    var startDate: Date
    var endDate: Date?
    @Relationship(deleteRule: .cascade) var sets: [WorkoutSet]
    var totalActiveTime: TimeInterval
    var totalRestTime: TimeInterval
    var status: Status

    init(
        id: UUID = UUID(),
        startDate: Date = Date(),
        endDate: Date? = nil,
        sets: [WorkoutSet] = [],
        totalActiveTime: TimeInterval = 0,
        totalRestTime: TimeInterval = 0,
        status: Status = .inProgress
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.sets = sets
        self.totalActiveTime = totalActiveTime
        self.totalRestTime = totalRestTime
        self.status = status
    }
}
