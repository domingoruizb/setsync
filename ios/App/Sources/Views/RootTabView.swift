import SwiftUI

/// specs/modules/04-history-and-navigation.md §1: the app's root
/// navigation — a 4-tab `TabView` replacing the single-screen
/// `DashboardView` root. Presented directly by `SetSyncApp`.
struct RootTabView: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "house") }

            SessionsListView()
                .tabItem { Label("Sessions", systemImage: "calendar") }

            ExercisesListView()
                .tabItem { Label("Exercises", systemImage: "dumbbell") }

            SettingsView()
                .tabItem { Label("Watch / Settings", systemImage: "applewatch") }
        }
    }
}
