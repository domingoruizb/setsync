import SwiftUI

/// Minimal entry point so the headless CI build (Task 1.4) has a linkable
/// app target. Superseded by DashboardView in Task 3.4.
@main
struct SetSyncApp: App {
    var body: some Scene {
        WindowGroup {
            Text("SetSync")
        }
    }
}
