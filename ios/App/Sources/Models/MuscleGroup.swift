import Foundation

/// Muscle taxonomy identifiers as frozen in specs/01-system-spec.md §3.1.
/// Color-mapping (heat map levels 0-5) is completed in Task 1.3.
enum MuscleGroup: String, Codable, CaseIterable {
    case chestUpper = "chest_upper"
    case chestMiddle = "chest_middle"
    case chestLower = "chest_lower"

    case lats
    case trapsUpper = "traps_upper"
    case trapsMiddle = "traps_middle"
    case rhomboids
    case lowerBack = "lower_back"

    case deltoidAnterior = "deltoid_anterior"
    case deltoidLateral = "deltoid_lateral"
    case deltoidPosterior = "deltoid_posterior"

    case biceps
    case tricepsLongHead = "triceps_long_head"
    case tricepsLateralHead = "triceps_lateral_head"
    case forearms

    case absUpper = "abs_upper"
    case absLower = "abs_lower"
    case obliques

    case quadriceps
    case hamstrings
    case glutes
    case calves
    case adductors
}
