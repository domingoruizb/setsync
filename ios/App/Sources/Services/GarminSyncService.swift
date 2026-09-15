import ConnectIQ
import Foundation
import SwiftData

/// specs/modules/02-ios-core-and-sync.md §2: listens for Garmin Connect IQ
/// app messages and replies with SYNC_ACK. Device pairing/selection and the
/// SDK's own initialization are included here since the service cannot
/// receive anything without them — not wired into any View/App yet (no
/// DashboardView/URL-handling exists before Task 3.4).
///
/// API usage (register/unregister "forX", receivedMessage's "from", and
/// sendMessage's "to" labels) is verified against a working third-party
/// Swift integration (github.com/MatyasKriz/ios-connect-iq-comms), not
/// derived solely from the Objective-C headers: Swift's importer strips
/// "App"/"DeviceEvents"-style redundant words differently than a literal
/// reading of the selector would suggest, and there is no local Xcode/
/// Swift toolchain in this environment to compile-check it directly.
final class GarminSyncService: NSObject, IQUIOverrideDelegate, IQDeviceEventDelegate, IQAppMessageDelegate {

    // Must match garmin/manifest.xml's <iq:application id="..."> exactly —
    // this identifies our Monkey C app to the ConnectIQ Mobile SDK. Not
    // published to the Connect IQ Store, so the same UUID is reused as the
    // (otherwise meaningless, for a personal sideloaded app) store id.
    private static let garminAppUUID = UUID(uuidString: "145fa933-0711-4e6f-9263-d5d10098afff")!

    private let modelContext: ModelContext
    private(set) var pairedDevice: IQDevice?
    private var garminApp: IQApp?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        super.init()
        ConnectIQ.sharedInstance().initialize(withUrlScheme: "setsync-ciq", uiOverrideDelegate: self)
    }

    deinit {
        ConnectIQ.sharedInstance().unregister(forAllDeviceEvents: self)
        ConnectIQ.sharedInstance().unregister(forAllAppMessages: self)
    }

    /// specs/modules/02-ios-core-and-sync.md §2 step 1: launches Garmin
    /// Connect Mobile's device-selection UI.
    func selectDevice() {
        ConnectIQ.sharedInstance().showDeviceSelection()
    }

    /// Handles the URL callback Garmin Connect Mobile sends back to the
    /// `setsync-ciq` scheme (Task 3.1) after device selection.
    func handleOpenURL(_ url: URL) {
        guard let devices = ConnectIQ.sharedInstance().parseDeviceSelectionResponse(from: url) as? [IQDevice],
              let device = devices.first else {
            return
        }

        pairedDevice = device
        let app = IQApp(
            uuid: GarminSyncService.garminAppUUID,
            store: GarminSyncService.garminAppUUID,
            device: device
        )
        garminApp = app

        ConnectIQ.sharedInstance().register(forDeviceEvents: device, delegate: self)
        ConnectIQ.sharedInstance().register(forAppMessages: app, delegate: self)
    }

    // MARK: - IQUIOverrideDelegate

    func needsToInstallConnectMobile() {
        // Presenting an install prompt is a UI concern for a later task;
        // this is a required hook point only.
    }

    // MARK: - IQDeviceEventDelegate

    func deviceStatusChanged(_ device: IQDevice!, status: IQDeviceStatus) {
        // Connection status is informational only for this task; the
        // actual sync work happens in receivedMessage(_:from:).
    }

    // MARK: - IQAppMessageDelegate

    /// specs/modules/02-ios-core-and-sync.md §2 step 3: parses SET_COMPLETED
    /// and SESSION_EVENT payloads (both listed under the same parsing step;
    /// SESSION_EVENT is included because SET_COMPLETED has no
    /// WorkoutSession to attach to otherwise).
    func receivedMessage(_ message: Any!, from app: IQApp!) {
        guard let dictionary = message as? [String: Any],
              let msgType = dictionary["msgType"] as? String,
              let payload = dictionary["payload"] as? [String: Any] else {
            return
        }

        switch msgType {
        case "SET_COMPLETED":
            handleSetCompleted(payload, app: app)
        case "SESSION_EVENT":
            handleSessionEvent(payload)
        default:
            break
        }
    }

    // specs/01-system-spec.md §2.1 (SET_COMPLETED) + §2.3 (SYNC_ACK reply).
    private func handleSetCompleted(_ payload: [String: Any], app: IQApp) {
        guard let setId = payload["setId"] as? String,
              let reps = payload["reps"] as? Int,
              let weightKg = payload["weightKg"] as? Double,
              let durationSec = payload["durationSec"] as? Int,
              let restSec = payload["restSec"] as? Int,
              let timestamp = payload["timestamp"] as? Int else {
            return
        }

        // specs/01-system-spec.md §4: "Toda serie recibida entra con
        // exercise = nil" — assigned later in ActiveWorkoutView (Task 4.1).
        if let activeSession = fetchActiveSession() {
            let workoutSet = WorkoutSet(
                exercise: nil,
                reps: reps,
                weightKg: weightKg,
                setDurationSeconds: durationSec,
                restDurationSeconds: restSec,
                detectedAutomatically: true,
                timestamp: Date(timeIntervalSince1970: TimeInterval(timestamp))
            )
            modelContext.insert(workoutSet)
            activeSession.sets.append(workoutSet)
            try? modelContext.save()
        }

        sendSyncAck(setId: setId, to: app)
    }

    // specs/01-system-spec.md §2.2.
    private func handleSessionEvent(_ payload: [String: Any]) {
        guard let action = payload["action"] as? String else {
            return
        }

        if action == "START" {
            let session = WorkoutSession(status: .inProgress)
            modelContext.insert(session)
            try? modelContext.save()
        } else if action == "STOP" {
            if let activeSession = fetchActiveSession() {
                activeSession.endDate = Date()
                activeSession.status = .completed
                try? modelContext.save()
            }
        }
    }

    private func fetchActiveSession() -> WorkoutSession? {
        let descriptor = FetchDescriptor<WorkoutSession>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        let sessions = (try? modelContext.fetch(descriptor)) ?? []
        return sessions.first { $0.status == .inProgress }
    }

    // specs/01-system-spec.md §2.3: SYNC_ACK (iOS -> Garmin), matching the
    // spec's payload keys exactly (RULES.md §3 payload invariance).
    private func sendSyncAck(setId: String, to app: IQApp) {
        let ackMessage: [String: Any] = [
            "msgType": "SYNC_ACK",
            "payload": [
                "setId": setId,
                "status": "OK"
            ]
        ]
        ConnectIQ.sharedInstance().sendMessage(
            ackMessage,
            to: app,
            progress: { _, _ in },
            completion: { _ in }
        )
    }
}
