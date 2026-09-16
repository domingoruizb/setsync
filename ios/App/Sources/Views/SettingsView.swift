import ConnectIQ
import SwiftUI

/// specs/modules/04-history-and-navigation.md §1: "Watch / Settings" tab —
/// Garmin pairing/status (moved from `DashboardView`/`TodayView`, Task 6.3)
/// plus the entry point to `GeminiAPISettingsView` (built in Task 6.2, not
/// wired into navigation until now).
struct SettingsView: View {
    @EnvironmentObject private var garminSyncService: GarminSyncService

    var body: some View {
        NavigationStack {
            List {
                // specs/modules/02-ios-core-and-sync.md §2 step 1 (pairing
                // entry point).
                Section("Reloj Garmin") {
                    garminStatusContent
                }

                Section("IA") {
                    NavigationLink("Clave API de Gemini") {
                        GeminiAPISettingsView()
                    }
                }
            }
            .navigationTitle("Ajustes")
        }
    }

    private var garminStatusContent: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(garminSyncService.pairedDevice?.friendlyName ?? "Sin dispositivo emparejado")
                if let status = garminSyncService.deviceStatus {
                    Text(String(describing: status))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Emparejar") {
                garminSyncService.selectDevice()
            }
        }
    }
}
