import SwiftUI

/// specs/modules/04-history-and-navigation.md §1: the app's root
/// navigation — a 4-tab `TabView` replacing the single-screen
/// `DashboardView` root. Presented directly by `SetSyncApp`.
struct RootTabView: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Hoy", systemImage: "house") }

            SessionsListView()
                .tabItem { Label("Sesiones", systemImage: "calendar") }

            ExercisesListView()
                .tabItem { Label("Ejercicios", systemImage: "dumbbell") }

            SettingsView()
                .tabItem { Label("Ajustes", systemImage: "applewatch") }
        }
    }
}
