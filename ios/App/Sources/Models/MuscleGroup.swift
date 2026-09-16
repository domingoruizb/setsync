import Foundation
import SwiftUI

/// Muscle taxonomy identifiers as frozen in specs/01-system-spec.md §3.1.
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

/// specs/01-system-spec.md §3.2: heat scale (5 levels) derived from an
/// accumulated activation Score (1.0 per set as primary muscle, 0.4 as secondary).
extension MuscleGroup {
    static func heatLevel(forScore score: Double) -> Int {
        switch score {
        case 0:
            return 0
        case ...1.5:
            return 1
        case ...3.0:
            return 2
        case ...5.0:
            return 3
        case ...7.0:
            return 4
        default:
            return 5
        }
    }

    static func heatColor(forScore score: Double) -> Color {
        switch heatLevel(forScore: score) {
        case 0: return Color(hex: 0x2C2C2E)
        case 1: return Color(hex: 0xFFE082)
        case 2: return Color(hex: 0xFFB74D)
        case 3: return Color(hex: 0xFF7043)
        case 4: return Color(hex: 0xF4511E)
        default: return Color(hex: 0xD32F2F)
        }
    }
}

// Refactor "Localización al Español": display names shown anywhere in the
// UI (chip pickers, exercise detail, session legends) are always Spanish
// gym terminology — a display-only layer. The frozen English snake_case
// `rawValue`s above (the Bluetooth/AI wire taxonomy) are never touched, so
// GeminiExerciseClassifier's output matching (`MuscleGroup(safeRawValue:)`)
// is unaffected. This single source of truth replaces four private
// per-file `displayName(for:)` duplicates that previously just
// capitalized the raw English identifier.
extension MuscleGroup {
    var displayName: String {
        switch self {
        case .chestUpper: return "Pecho superior"
        case .chestMiddle: return "Pecho medio"
        case .chestLower: return "Pecho inferior"
        case .lats: return "Dorsal"
        case .trapsUpper: return "Trapecio superior"
        case .trapsMiddle: return "Trapecio medio"
        case .rhomboids: return "Romboides"
        case .lowerBack: return "Lumbar"
        case .deltoidAnterior: return "Hombro anterior"
        case .deltoidLateral: return "Hombro lateral"
        case .deltoidPosterior: return "Hombro posterior"
        case .biceps: return "Bíceps"
        case .tricepsLongHead: return "Tríceps (cabeza larga)"
        case .tricepsLateralHead: return "Tríceps (cabeza lateral)"
        case .forearms: return "Antebrazos"
        case .absUpper: return "Abdomen superior"
        case .absLower: return "Abdomen inferior"
        case .obliques: return "Oblicuos"
        case .quadriceps: return "Cuádriceps"
        case .hamstrings: return "Isquiotibiales"
        case .glutes: return "Glúteos"
        case .calves: return "Gemelos"
        case .adductors: return "Aductores"
        }
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
