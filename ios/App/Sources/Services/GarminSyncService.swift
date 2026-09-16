import Combine
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
final class GarminSyncService: NSObject, ObservableObject, IQUIOverrideDelegate, IQDeviceEventDelegate, IQAppMessageDelegate {

    // Must match garmin/manifest.xml's <iq:application id="..."> exactly —
    // this identifies our Monkey C app to the ConnectIQ Mobile SDK. Not
    // published to the Connect IQ Store, so the same UUID is reused as the
    // (otherwise meaningless, for a personal sideloaded app) store id.
    private static let garminAppUUID = UUID(uuidString: "145fa933-0711-4e6f-9263-d5d10098afff")!

    private let modelContext: ModelContext
    private let healthKitService: HealthKitService
    @Published private(set) var pairedDevice: IQDevice?
    @Published private(set) var deviceStatus: IQDeviceStatus?
    private var garminApp: IQApp?

    init(modelContext: ModelContext, healthKitService: HealthKitService) {
        self.modelContext = modelContext
        self.healthKitService = healthKitService
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
        // The SDK's delegate callbacks aren't guaranteed to fire on the
        // main thread/actor; @Published mutations (which drive SwiftUI)
        // must happen there.
        DispatchQueue.main.async { [weak self] in
            self?.deviceStatus = status
        }
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
        // SYNC_ACK is sent immediately, independent of this persistence
        // (matches §4's "respuesta inmediata"); the SwiftData write is
        // dispatched to the main thread/actor since this delegate callback
        // isn't guaranteed to fire there and modelContext (container.mainContext,
        // wired in SetSyncApp) is meant to be used from main.
        // Idempotency: CommunicationsService's 10s retry timer on Garmin
        // can re-transmit the same queued SET_COMPLETED before its
        // SYNC_ACK round-trip completes (BLE latency), so the exact same
        // payload can legitimately arrive twice. Field testing confirmed
        // this produced two identical WorkoutSets. `timestamp` is the
        // payload's own de-dup key (assigned once by Garmin when the set
        // was confirmed, so a genuine retry always repeats it exactly);
        // comparing whole seconds avoids any Date/TimeInterval rounding.
        DispatchQueue.main.async { [weak self] in
            guard let self, let activeSession = self.fetchActiveSession() else { return }
            let alreadyStored = activeSession.sets.contains {
                Int($0.timestamp.timeIntervalSince1970) == timestamp
            }
            guard !alreadyStored else { return }

            let workoutSet = WorkoutSet(
                exercise: nil,
                reps: reps,
                weightKg: weightKg,
                setDurationSeconds: durationSec,
                restDurationSeconds: restSec,
                detectedAutomatically: true,
                timestamp: Date(timeIntervalSince1970: TimeInterval(timestamp))
            )
            self.modelContext.insert(workoutSet)
            activeSession.sets.append(workoutSet)
            try? self.modelContext.save()
        }

        // Sent unconditionally, whether this was a fresh set or a
        // duplicate — Garmin's queue must be drained either way (§4).
        sendSyncAck(setId: setId, to: app)
    }

    // specs/01-system-spec.md §2.2.
    private func handleSessionEvent(_ payload: [String: Any]) {
        guard let action = payload["action"] as? String else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if action == "START" {
                let session = WorkoutSession(status: .inProgress)
                self.modelContext.insert(session)
                try? self.modelContext.save()
            } else if action == "STOP" {
                if let activeSession = self.fetchActiveSession() {
                    activeSession.endDate = Date()
                    activeSession.status = .completed
                    try? self.modelContext.save()
                    // Post-launch addition: auto-export to Apple Health the
                    // instant a session finishes via the watch's own STOP
                    // event, mirroring ActiveWorkoutView's manual "Finalizar
                    // Entrenamiento" trigger (finishWorkout()).
                    self.healthKitService.saveWorkout(session: activeSession)
                }
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
