# Implementation Plan: SunFit Atomic Milestones

## Phase 1: Foundations, Scaffolding & Models
- [x] **Task 1.1:** Scaffold empty directory tree (`/garmin`, `/ios`, `.github/workflows`).
- [x] **Task 1.2:** Implement SwiftData models in iOS (`ios/App/Sources/Models/`): `Exercise`, `WorkoutSet`, `WorkoutSession`, `DailySummaryMetrics` according to `specs/01-system-spec.md`. Path corrected from `ios/Sources/Models/` to match the `ios/App/Sources` project structure declared in `specs/modules/02-ios-core-and-sync.md` §5. `Exercise.primaryMuscle`/`secondaryMuscles` depend on a minimal `MuscleGroup` stub enum (cases only, no color logic) introduced in this task to allow compilation; Task 1.3 completes it with the color-mapping function.
- [x] **Task 1.3:** Complete `MuscleGroup` enum (started as a stub in Task 1.2) with all remaining taxonomy cases and implement the color-mapping function (levels 0-5) in iOS.
- [x] **Task 1.4:** Create declarative `ios/project.yml` (XcodeGen spec) and configure `.github/workflows/build-ios.yml` pipeline for remote headless builds. **Naming decision:** the Xcode project/scheme/app target is named `SetSync` (matching the GitHub repository `setsync`), not `SunFit`; `.github/workflows/build-ios.yml` is updated accordingly (project file, scheme, `.app`/`.ipa` filenames, artifact name). Other spec documents still using "SunFit" as the legacy project label are out of scope for this task and unchanged. A minimal `@main` SwiftUI entry point (`ios/App/Sources/SetSyncApp.swift`, empty `WindowGroup`) is added solely so the headless CI build has a linkable app target; it will be superseded by the real `DashboardView` in Task 3.4. No HealthKit/Bluetooth entitlements are configured here — that remains Task 3.1 scope.

---

## Phase 2: Garmin Connect IQ App
- [x] **Task 2.1:** Create baseline Connect IQ Device App project targeting Forerunner 165. **Naming decision:** product name is `SetSync` (consistent with the Task 1.4 iOS/repo naming), used as the manifest `app-name` string and as the Monkey C class prefix (`SetSyncApp`, `SetSyncView`, `SetSyncDelegate`). Scaffolding only: an empty `IDLE`-equivalent starter screen, no FSM/state logic (Task 2.2), no sensor code (Task 2.3), no button bindings (Task 2.4), no `Communications` transmission logic (Task 2.5). The `Communications` manifest permission is declared upfront since it is a documented core module (`CLAUDE.md` Key Modules) the app will require.
- [x] **Task 2.2:** Implement Finite State Machine (`IDLE`, `ACTIVE_SET`, `EDIT_SET`, `RESTING`). Implemented as a standalone `WorkoutStateMachine` (not yet wired into `SetSyncDelegate`/`SetSyncView`, which is Task 2.4's scope) covering exactly the transitions in `specs/modules/01-garmin-app.md` §3: START/STOP cycles `IDLE → RESTING → ACTIVE_SET → EDIT_SET → RESTING`; `BACK (Hold)` only transitions `RESTING → IDLE`; `UP/DOWN` never changes state (`canAdjustSet()` invariant, true only in `EDIT_SET`). Any trigger undefined for the current state is a no-op — no implicit/undefined transitions. Accelerometer start/stop (Task 2.3), vibration/SET_COMPLETED enqueueing (Task 2.5), and physical button wiring (Task 2.4) are intentionally out of scope here.
- [x] **Task 2.3:** Implement accelerometer sampling (25 Hz) and SMA peak-detection filter. `RepDetector` implements `specs/modules/01-garmin-app.md` §2 exactly: 5-sample circular-buffer SMA, then hysteresis peak detection (1.2g dynamic threshold → 800 ms refractory lockout → 0.9g valley confirmation before re-arming). `AccelerometerSensor` wraps `Sensor.registerSensorDataListener` at `{:period => 1, :accelerometer => {:enabled => true, :sampleRate => 25, :includeTimestamps => true}}` (verified against the installed Connect IQ 9.2.0 SDK's own `PitchCounter` sample and `AccelerometerData` API docs, since values are in milli-G — divided by 1000 before computing `a(t) = sqrt(x²+y²+z²)`), feeding each raw sample + its real timestamp to `RepDetector`. **Manifest change:** compiling surfaced `Permission 'Sensor' required for Toybox.Sensor...`, so `<iq:uses-permission id="Sensor"/>` was added to `garmin/manifest.xml` (alongside the existing `Communications` permission). Standalone/unwired from `WorkoutStateMachine`/`SetSyncDelegate`, consistent with Task 2.2 — starting/stopping the sensor on `ACTIVE_SET` entry/exit is integration left for Task 2.4.
- [ ] **Task 2.4:** Implement manual rep and weight adjustment screens with physical button bindings.
- [ ] **Task 2.5:** Implement `Toybox.Communications` sender and local FIFO queue for `SET_COMPLETED` payloads.

---

## Phase 3: iOS Core & Sync Layer
- [ ] **Task 3.1:** Download/link `ConnectIQ.framework` in CI pipeline and configure iOS Info.plist entitlements (Bluetooth & HealthKit).
- [ ] **Task 3.2:** Implement `GarminSyncService` listening for `SET_COMPLETED` and returning `SYNC_ACK`.
- [ ] **Task 3.3:** Implement `HealthKitService` querying daily steps and active/resting energy burn.
- [ ] **Task 3.4:** Build `DashboardView` with daily metrics overview.

---

## Phase 4: Active Workout & Replicate UI
- [ ] **Task 4.1:** Build `ActiveWorkoutView` showing live sets arriving from Garmin.
- [ ] **Task 4.2:** Implement searchable exercise dropdown and inline exercise creation form.
- [ ] **Task 4.3:** Implement replicate ("Copy Down") action button on the last labeled set row.

---

## Phase 5: AI Categorization & Muscle Heat Map
- [ ] **Task 5.1:** Implement `MuscleClassifierService` with Gemini 1.5 Flash structured output calling Google AI Studio.
- [ ] **Task 5.2:** Build `MuscleHeatMapView` vectorial component (anterior/posterior) reactive to calculated muscle scores.
- [ ] **Task 5.3:** Build `ExerciseHistoryView` with progress calendar and rep/load progression logs.