import SwiftUI

/// specs/modules/04-history-and-navigation.md §1: the app's root
/// navigation — a 4-tab `TabView` replacing the single-screen
/// `DashboardView` root. Presented directly by `SetSyncApp`.
struct RootTabView: View {
    @Environment(\.healthKitService) private var healthKitService

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
        .task {
            // Requested here, at the app's root, rather than only from
            // TodayView's onAppear: an app only appears under Ajustes →
            // Privacidad y seguridad → Salud → Acceso y dispositivos once
            // it has actually called requestAuthorization at least once,
            // so this needs to run unconditionally at launch regardless
            // of which tab happens to render first — not depend on
            // TodayView specifically being shown/appearing.
            healthKitService?.requestAuthorization { _ in }
        }
    }
}
