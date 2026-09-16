import SwiftUI

/// specs/modules/04-history-and-navigation.md §3: manual multi-select
/// fallback for `primaryMuscles`/`secondaryMuscles` when AI classification
/// fails or needs adjusting — a wrapping grid of toggleable capsules over
/// `MuscleGroup.allCases`. Plain SwiftUI (`LazyVGrid` + tap gesture), no
/// third-party layout package, per this project's zero-cost/no-heavy-
/// dependency stance.
struct MuscleChipPicker: View {
    let title: String
    @Binding var selection: Set<MuscleGroup>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 6)], spacing: 6) {
                ForEach(MuscleGroup.allCases, id: \.self) { muscle in
                    chip(for: muscle)
                }
            }
        }
    }

    private func chip(for muscle: MuscleGroup) -> some View {
        let isSelected = selection.contains(muscle)
        return Text(displayName(for: muscle))
            .font(.caption2)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor : Color.gray.opacity(0.2))
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .clipShape(Capsule())
            .onTapGesture {
                if isSelected {
                    selection.remove(muscle)
                } else {
                    selection.insert(muscle)
                }
            }
    }

    private func displayName(for muscle: MuscleGroup) -> String {
        muscle.rawValue.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
