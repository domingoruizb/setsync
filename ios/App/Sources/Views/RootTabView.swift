import SwiftData
import SwiftUI

/// specs/modules/04-history-and-navigation.md §1: the app's root
/// navigation — a 5-tab `TabView` (added a central "+" action tab for
/// manual/retroactive workout entry, for use without a paired Garmin
/// watch) replacing the original 4-tab layout. Presented directly by
/// `SetSyncApp`.
struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \WorkoutSession.startDate, order: .reverse)
    private var sessions: [WorkoutSession]

    private enum Tab: Hashable {
        case today, sessions, addWorkout, exercises, settings
    }

    @State private var selection: Tab = .today
    @State private var previousSelection: Tab = .today
    @State private var activeWorkoutSession: WorkoutSession?

    var body: some View {
        TabView(selection: $selection) {
            TodayView()
                .tabItem { Label("Hoy", systemImage: "house") }
                .tag(Tab.today)

            SessionsListView()
                .tabItem { Label("Sesiones", systemImage: "calendar") }
                .tag(Tab.sessions)

            // Never actually shown as a page — selecting it is
            // immediately bounced back to `previousSelection` in
            // `onChange` below, so the tab bar's own selected indicator
            // never lands on "+". A plain icon, deliberately no label
            // ("+ Entrenar" was explicitly rejected in favor of just the
            // icon), matching a pure action button rather than content.
            Color.clear
                .tabItem { Image(systemName: "plus") }
                .tag(Tab.addWorkout)

            ExercisesListView()
                .tabItem { Label("Ejercicios", systemImage: "dumbbell") }
                .tag(Tab.exercises)

            SettingsView()
                .tabItem { Label("Ajustes", systemImage: "applewatch") }
                .tag(Tab.settings)
        }
        .onChange(of: selection) { _, newValue in
            if newValue == .addWorkout {
                selection = previousSelection
                activeWorkoutSession = existingOrNewActiveSession()
            } else {
                previousSelection = newValue
            }
        }
        // A full-screen cover (not a small sheet) so ActiveWorkoutView
        // gets its own real navigation bar/toolbar via a fresh
        // NavigationStack, and dismiss() from "Finalizar Entrenamiento"
        // (or the new close button) closes it cleanly regardless of which
        // tab was showing underneath.
        .fullScreenCover(item: $activeWorkoutSession) { session in
            NavigationStack {
                ActiveWorkoutView(session: session)
            }
        }
    }

    // "Si ya existe una WorkoutSession con estado en curso, navega
    // directamente a su ActiveWorkoutView. Si no, crea una nueva de
    // inmediato." `status: .inProgress` is this app's existing in-progress
    // flag (the same one GarminSyncService/every other view already
    // checks) — no separate `inProgress: Bool` was added alongside it,
    // since that would just be a second, easily-desynced source of truth
    // for the same thing.
    private func existingOrNewActiveSession() -> WorkoutSession {
        if let existing = sessions.first(where: { $0.status == .inProgress }) {
            return existing
        }
        let session = WorkoutSession(startDate: Date(), status: .inProgress)
        modelContext.insert(session)
        try? modelContext.save()
        return session
    }
}
