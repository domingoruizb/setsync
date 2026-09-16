# SetSync

SetSync is a personal, zero-cost workout tracking ecosystem pairing a **Garmin Forerunner 165** (Connect IQ / Monkey C) with an **iOS companion app** (SwiftUI + SwiftData, fully localized to Spanish). The watch handles real-time set timing and automatic rep counting via the accelerometer; the phone receives completed sets over Bluetooth, persists workout history locally, classifies exercises' muscle activation with a free-tier LLM, visualizes training load on an anatomical muscle map, and exports finished workouts as `.tcx` files for Strava.

No paid backend, no subscriptions, no App Store distribution — everything runs locally, compiled by free tooling and sideloaded onto personal hardware.

---

## 1. Context

- **Target hardware:** Garmin Forerunner 165 (390×390 round AMOLED, 5 physical buttons + touch) and a personal iPhone.
- **Cost:** €0 — open-source/free-tier tooling only (Connect IQ SDK, XcodeGen, GitHub Actions free runners, Google AI Studio's Gemini free tier).
- **Distribution:** never published to the Connect IQ Store or the App Store. The watch app is sideloaded over USB; the iOS app is built unsigned in CI and sideloaded with a free Apple ID (SideStore / Sideloadly).
- **Offline-first:** the iOS app works fully offline in the gym. AI classification is a best-effort, cached-once enhancement — its absence never blocks logging a workout.
- **No HealthKit.** A provisioning profile generated from a free/personal-team Apple ID (this app's actual signing path via Sideloadly) never gets the `com.apple.developer.healthkit` entitlement granted by Apple at all, so HealthKit access — read or write — is blocked at the OS level regardless of any app-side fix. The app never touches HealthKit; Strava integration goes through a plain exported file instead (§2.4).

---

## 2. Architecture & Modules

### 2.1 Garmin Connect IQ App (Monkey C)

A Device App implementing a strict 4-state finite state machine (`WorkoutStateMachine`, `WorkoutState.mc`):

```
IDLE → RESTING → ACTIVE_SET → EDIT_SET → RESTING → ... → IDLE
```

| State | Meaning |
|---|---|
| `IDLE` | No workout in progress. |
| `RESTING` | Rest timer running, plus the total elapsed workout time since the session started. |
| `ACTIVE_SET` | Accelerometer sampling live, counting reps. |
| `EDIT_SET` | Reps/weight confirmation screen before the set is queued for transmission. |

Key components:
- **`RepDetector` + `AccelerometerSensor`** — 25 Hz accelerometer sampling, a 5-sample circular-buffer SMA filter, and hysteresis peak detection (1.2g dynamic threshold, 800 ms refractory lockout, 0.9g valley confirmation) to count repetitions without double-counting.
- **`CommunicationsService` + `SyncQueue`** — sends `SET_COMPLETED`/`SESSION_EVENT` payloads via `Toybox.Communications.transmit()`. Deliberately tolerant of unreliable BLE:
  - An in-memory FIFO queue retries unacknowledged `SET_COMPLETED` payloads every 10 s until a real `SYNC_ACK` arrives from the phone (not merely on transmit success, which only confirms the packet reached the phone's Bluetooth stack).
  - Ending a session vibrates, shows a brief "Session Saved" screen, and blocks `System.exit()` until the `SESSION_EVENT: STOP` transmit has actually settled — found necessary after field testing showed the watch process could otherwise be torn down before the packet left the device.
- **`SetSyncView` / `SetSyncDelegate`** — per-state rendering (state-specific accent colors, a live rep/rest timer, a 6-level heat-color palette shared with iOS) and physical-button/touch input handling:
  - Button behavior was corrected against **real hardware**, not just the simulator: a genuine BACK-hold gesture is intercepted by the watch's firmware before ever reaching the app, so ending a session from `RESTING` uses a plain BACK press instead.
  - `RESTING`'s secondary readout shows the session's total elapsed time (`"Total: MM:SS"`, `H:MM:SS` past an hour) instead of the previous last-completed-set summary.
  - Holding UP/DOWN while `EDIT_SET`'s weight-whole field is focused jumps the value by ±5 kg instead of the usual ±1 kg short-press step (clamped to 0–500 kg). `Toybox.WatchUi.InputDelegate.onHold()` turned out to only fire for *touch-screen* holds (confirmed by the SDK's own API metadata and a real compile error), so this is hand-timed via `onKeyPressed`/`onKeyReleased`, designed to degrade to normal short-press behavior if those raw hooks never fire on a given device.

### 2.2 iOS Companion App (SwiftUI + SwiftData)

- **Navigation:** `RootTabView` with 5 tabs, all in Spanish — **Hoy** (weekly strength dashboard), **Sesiones** (full workout history), a central icon-only **+** action tab (manual workout entry, below), **Ejercicios** (catalog + progression), **Ajustes** (Garmin pairing and Gemini API key configuration).
- **Persistence:** SwiftData (`Exercise`, `WorkoutSet`, `WorkoutSession`), local-only, no CloudKit.
- **Garmin sync (`GarminSyncService`):** implements the ConnectIQ Mobile SDK's device/app-message delegates. Parses `SET_COMPLETED`/`SESSION_EVENT`, persists `WorkoutSet`/`WorkoutSession`, and always replies with `SYNC_ACK`. Hardened against real-world Bluetooth behavior:
  - **Idempotent set insertion:** the watch's 10 s retry can legitimately re-deliver the same `SET_COMPLETED` before its `SYNC_ACK` round-trip completes over real (higher-latency) BLE; sets are de-duplicated by the payload's own `timestamp` before insertion, while `SYNC_ACK` is still always sent to drain the watch's queue either way.
  - `SESSION_EVENT: START` reuses an already-open session instead of creating a second one, in case the phone (see manual entry, below) already started one.
  - A manual **"Finalizar Entrenamiento"** button in `ActiveWorkoutView` closes a session locally if the watch's `SESSION_EVENT: STOP` never arrives. Both the Hoy tab's day list and the Sesiones tab route an `.inProgress` session to `ActiveWorkoutView` specifically (not the review-only `SessionDetailView`) so this button — and the live exercise-assignment/"Copy Down" flow — stays reachable for as long as a session is open.
- **Manual/retroactive workout entry (no Garmin needed):** the tab bar's central **+** button opens the current in-progress session, or creates one on the spot, in a full-screen `ActiveWorkoutView`. There, an editable "Horario" section lets the real start time (live-bound, editable at any point) and an optional end time (committed only when the workout is finished) diverge from "whenever + was tapped" — for logging a session after the fact with its real historical times. A prominent **"Añadir Serie"** button inserts sets by hand, pre-filled from the previous set's exercise/reps/weight to speed up repeated straight sets; manual sets carry no set/rest duration (there's no accelerometer or rest timer without the watch), and reuse the exact same inline editing (`SetEditView`) and single-step "Copiar hacia abajo" fill-down as Garmin-sourced sets.
- **Editing & deletion:** sessions support swipe-to-delete with a destructive confirmation alert (cascades to all of their sets via SwiftData's `.cascade` delete rule); individual sets support swipe-to-delete directly, and tapping one opens `SetEditView` (reps, weight, and reassigning the exercise) from either an active or a finished session. No dedicated "recompute metrics" step exists anywhere — every derived stat (PRs, estimated 1RM, muscle maps) is a computed property over live `@Query` results, so it updates automatically after any edit, regardless of whether a session/set came from the watch or was entered by hand.

### 2.3 AI Exercise Classification

New custom exercises are classified automatically instead of requiring the user to look up which muscles they train:

- **`GeminiExerciseClassifier`** calls Google AI Studio's `gemini-3.5-flash-lite:generateContent` REST endpoint directly via `URLSession` (no vendor SDK, to avoid CI linking risk), requesting strict JSON output (`generationConfig.response_mime_type`/`response_schema`) shaped as `{"primary": [...], "secondary": [...]}` against the app's fixed muscle taxonomy. The prompt expects exercise names in Spanish gym terminology but classifies correctly regardless of the input language; the taxonomy identifiers it returns are always the frozen English snake_case values (`chest_upper`, `biceps`, ...), matched case- and diacritic-insensitively, with a defensive strip of any stray ```` ```json ``` ```` code fence before decoding.
- **API key:** read from the `GEMINI_API_KEY` environment variable first (useful for local development), falling back to a key the user saves once in **Ajustes → Clave API de Gemini**, persisted in `UserDefaults` (`GeminiAPIKeyStore`). The key is re-read on every classification call, so saving a new one in Settings takes effect immediately.
- **Descriptive, non-blocking failures:** `classify(exerciseName:)` returns a `Result` distinguishing a missing API key, a network/server error, or an unparsable response — `ExerciseCreationView` shows the specific reason inline, with a direct shortcut into the API key settings for the missing-key case and a retry button otherwise. Classification failing never blocks saving an exercise: `MuscleChipPicker` (a manual multi-select chip grid over every muscle group) stays fully usable either way, and a successful AI suggestion is always editable before saving, never a locked-in answer.

### 2.4 Analytics, Muscle Map & Strava Export

- **Weekly dashboard (`TodayView`, the "Hoy" tab):** a horizontally paged, Monday-first week selector (swipe right for earlier weeks, left back toward the present; the current week is the default page) built on a locale-independent `Calendar`. Each day cell shows its weekday initial (L, M, X, J, V, S, D), day number, a ring for today, a filled circle for the selected day, and a dot for any day with at least one *completed* session. Below it, the selected day's sessions render as tappable cards (start time, duration, set count, volume); the anatomical muscle map underneath aggregates **every set from every session in the currently visible week**, not just the selected day.
- **Per-exercise progression (`ExerciseDetailView`):** all-time PR (max weight), estimated max 1RM (Epley formula, `weight × (1 + reps / 30)`, evaluated per set and taking the maximum — not necessarily the same set as the raw PR), total sets/reps, and a day-grouped chronological history.
- **Muscle heat map (`AnatomicalBodyView`):** an anterior/posterior anatomical body diagram rendered from **real vector path data** (`ios/App/Sources/Views/BodyAtlasData.swift`), vendored from the MIT-licensed [react-native-body-highlighter](https://github.com/HichamELBSI/react-native-body-highlighter) project — see `THIRD_PARTY_NOTICES.md`. After earlier hand-authored attempts (a tile grid, then hand-placed `Path` geometry) were found visually unacceptable, this uses a real, professionally traced illustration instead: `SVGPathParser.swift` parses the vendored SVG `d`-string data (including elliptical arcs, per the SVG 1.1 spec's arc-to-Bézier conversion) into SwiftUI `Path`s. Each of the dataset's ~35 real anatomical regions is mapped onto the frozen 23-case `MuscleGroup` taxonomy for scoring/coloring (e.g. `chestUpper`/`chestMiddle`/`chestLower` all color the dataset's one "chest" shape, via the max of their scores); regions outside the tracked taxonomy (head, hands, feet, etc.) render in a fixed neutral tone. Rendered both on the weekly dashboard and per-session in `SessionDetailView` (that session's sets only, plus a legend of how many sets stimulated each muscle).
  - **Stimulus score:** +1.0 per set for each of an exercise's primary muscles, +0.4 for each secondary muscle.
  - **Color scale (6 levels, shared by both platforms' color logic):**

    | Score | Color |
    |---|---|
    | 0 | `#2C2C2E` (neutral gray) |
    | 0 – 1.5 | `#FFE082` (soft yellow) |
    | 1.5 – 3.0 | `#FFB74D` (amber) |
    | 3.0 – 5.0 | `#FF7043` (intense orange) |
    | 5.0 – 7.0 | `#F4511E` (orange-red) |
    | > 7.0 | `#D32F2F` (deep red) |
- **Strava export (`TCXExportService`), not HealthKit:** `SessionDetailView` offers "Exportar para Strava (.tcx)" via a native `ShareLink` once a session is finished. `TCXExportService` generates a Training Center Database (TCX) v2 XML file — `<Activity Sport="Other">`, a `<Lap>` with the real start time/duration in UTC ISO 8601, a two-`Trackpoint` `<Track>`, and a `<Notes>` summary of sets/reps/weight/volume per exercise. Strava's own upload flow (`strava.com/upload/select`, or the app's "Add Activity → Upload File") accepts `.tcx` natively, with no API key, OAuth flow, or app entitlement of any kind.

---

## 3. Repository Structure

```text
/sunfit
├── .github/
│   └── workflows/
│       └── build-ios.yml          # Headless macOS CI: XcodeGen -> xcodebuild -> unsigned .ipa
├── CLAUDE.md                      # Operating guidelines for AI-assisted development on this repo
├── THIRD_PARTY_NOTICES.md         # react-native-body-highlighter (MIT) attribution
├── specs/                         # Source-of-truth specifications (spec-driven development)
│   ├── 01-system-spec.md          # Domain model, Bluetooth payload schemas, heat-map formula
│   ├── RULES.md                   # Development policy & monotask guardrails
│   ├── implementation-plan.md     # Atomic task checklist + post-launch fix/feature log
│   └── modules/
│       ├── 01-garmin-app.md               # Monkey C FSM, sensor algorithm, button map
│       ├── 02-ios-core-and-sync.md        # SwiftUI/SwiftData/Bluetooth/CI
│       ├── 03-ai-and-muscle-map.md        # AI classifier + anatomical muscle map spec
│       └── 04-history-and-navigation.md   # Tab navigation, exercise catalog, session analytics
├── garmin/                        # Connect IQ (Monkey C) source
│   ├── manifest.xml
│   ├── monkey.jungle
│   ├── resources/
│   └── source/
└── ios/                           # SwiftUI source + XcodeGen project spec
    ├── project.yml
    └── App/Sources/
        ├── Models/                # Exercise, WorkoutSet, WorkoutSession, MuscleGroup
        ├── Services/               # GarminSyncService, GeminiExerciseClassifier, TCXExportService, ExerciseLibrarySeeder, GeminiAPIKeyStore
        ├── Views/                 # RootTabView, TodayView, SessionsListView, SessionDetailView, AnatomicalBodyView, ...
        └── SetSyncApp.swift
```

---

## 4. Deployment

### 4.1 Garmin Forerunner 165

Compiled locally with the Connect IQ SDK (no cloud build needed for the watch side):

```bash
cd garmin
monkeyc -d fr165 -f monkey.jungle -o bin/SetSync.prg -y <path-to-developer_key> -r
```

Then loaded over USB:

1. Connect the watch via USB; it mounts as a mass-storage drive.
2. Copy `garmin/bin/SetSync.prg` into `GARMIN/APPS/` on the device.
3. Safely eject and disconnect. The app appears in the watch's app list after it restarts.

### 4.2 iOS Companion App

Built headlessly in GitHub Actions (`.github/workflows/build-ios.yml`), since the app is developed on Windows with no local Xcode:

1. `xcodegen generate` turns `ios/project.yml` into an `.xcodeproj` (declaring the `ConnectIQ` Swift Package dependency, Info.plist, Bluetooth permissions). No entitlements file is generated — nothing this app does needs one.
2. `xcodebuild -resolvePackageDependencies` fetches the ConnectIQ SDK.
3. `xcodebuild ... CODE_SIGNING_ALLOWED=NO` produces an **unsigned** `Release` build.
4. The `.app` is zipped into `SetSync.ipa` and uploaded as a workflow artifact (`SetSync-unsigned-ipa`).

To install on a personal iPhone:

1. Download and unzip the `.ipa` artifact from the latest green run under the repo's **Actions** tab.
2. Sideload it with **Sideloadly** (or SideStore): connect the iPhone, drop in the `.ipa`, sign in with a free Apple ID to sign it on-device.
3. On the iPhone, trust the developer certificate under **Settings → General → VPN & Device Management**.
4. Free Apple ID signatures expire after 7 days — re-sideload periodically to keep the app installed.

---

## 5. Configuration

### Gemini API Key (optional, enables automatic exercise classification)

Without a key, creating a new exercise simply skips straight to manual muscle selection (chips) — nothing breaks.

To enable AI classification:

1. Get a free API key from [Google AI Studio](https://aistudio.google.com/).
2. In the app, go to **Ajustes → Clave API de Gemini**.
3. Paste the key and tap **Guardar**. It's stored locally in `UserDefaults` and takes effect on the next exercise you create — no restart needed.

(For local development builds, the key can alternatively be supplied via the `GEMINI_API_KEY` environment variable, which takes priority over the one saved in Settings.)

### Exporting a workout to Strava

No configuration needed. Open any finished session (**Sesiones** tab, or the day list on **Hoy**) and tap **"Exportar para Strava (.tcx)"** to bring up the native share sheet — save the file to Files, AirDrop it to another device, or upload it directly at [strava.com/upload/select](https://www.strava.com/upload/select) from Safari.

### Logging a workout without a Garmin (or after the fact)

Tap the **+** tab. It opens (or starts) an in-progress session immediately — no setup screen. Add sets by hand with **"Añadir Serie"**, editing each one's reps/weight/exercise the same way as a Garmin-sourced set. To log a past session with its real times, adjust **Inicio** and (optionally) **Fin** under "Horario" before tapping **"Finalizar Entrenamiento"** — leaving "Fin" unset just uses the current time.
