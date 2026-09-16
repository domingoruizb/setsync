import SwiftData
import SwiftUI

/// specs/modules/04-history-and-navigation.md §1/§4: "Sessions" tab —
/// every `WorkoutSession`, most recent first, navigating to
/// `SessionDetailView`.
struct SessionsListView: View {
    @Query(sort: \WorkoutSession.startDate, order: .reverse)
    private var sessions: [WorkoutSession]

    var body: some View {
        NavigationStack {
            Group {
                if sessions.isEmpty {
                    ContentUnavailableView("No sessions yet", systemImage: "calendar")
                } else {
                    List(sessions) { session in
                        NavigationLink {
                            SessionDetailView(session: session)
                        } label: {
                            sessionRow(session)
                        }
                    }
                }
            }
            .navigationTitle("Sessions")
        }
    }

    private func sessionRow(_ session: WorkoutSession) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(session.startDate.formatted(date: .abbreviated, time: .shortened))
                .font(.headline)
            Text("\(session.sets.count) set(s) · \(session.status.rawValue.capitalized)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
