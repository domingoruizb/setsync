import SwiftData
import SwiftUI

/// specs/modules/04-history-and-navigation.md §1/§4: "Sessions" tab —
/// every `WorkoutSession`, most recent first, navigating to
/// `SessionDetailView`.
struct SessionsListView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \WorkoutSession.startDate, order: .reverse)
    private var sessions: [WorkoutSession]

    // Swiping reveals the delete action (`.onDelete`) but only stages it
    // here — the actual `modelContext.delete` only runs once the user
    // confirms the destructive alert below, since deleting a session
    // cascades (`WorkoutSession.sets`' `.cascade` delete rule) to every
    // one of its sets and can't be undone.
    @State private var pendingDeleteOffsets: IndexSet?

    var body: some View {
        NavigationStack {
            Group {
                if sessions.isEmpty {
                    ContentUnavailableView("Sin sesiones todavía", systemImage: "calendar")
                } else {
                    List {
                        ForEach(sessions) { session in
                            NavigationLink {
                                SessionDetailView(session: session)
                            } label: {
                                sessionRow(session)
                            }
                        }
                        .onDelete { offsets in
                            pendingDeleteOffsets = offsets
                        }
                    }
                }
            }
            .navigationTitle("Sesiones")
            .alert(
                "¿Eliminar entrenamiento?",
                isPresented: Binding(
                    get: { pendingDeleteOffsets != nil },
                    set: { isPresented in
                        if !isPresented { pendingDeleteOffsets = nil }
                    }
                )
            ) {
                Button("Cancelar", role: .cancel) { pendingDeleteOffsets = nil }
                Button("Eliminar", role: .destructive) { confirmDelete() }
            } message: {
                Text("Esta acción no se puede deshacer.")
            }
        }
    }

    // Deleting the WorkoutSession cascades to all of its WorkoutSets
    // (model-level `.cascade` rule); every dependent view — the Sessions
    // list itself, Today's muscle map/session banner, and any
    // ExerciseDetailView showing one of the deleted sets — recomputes
    // automatically since they all read from `@Query`s or observed
    // relationships over the same shared modelContext, not a snapshot.
    private func confirmDelete() {
        guard let offsets = pendingDeleteOffsets else { return }
        for index in offsets {
            modelContext.delete(sessions[index])
        }
        try? modelContext.save()
        pendingDeleteOffsets = nil
    }

    private func sessionRow(_ session: WorkoutSession) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(session.startDate.formatted(date: .abbreviated, time: .shortened))
                .font(.headline)
            Text("\(session.sets.count) series · \(session.status.displayName)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
