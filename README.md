# SetSync

SetSync is a personal, zero-cost workout tracking ecosystem pairing a **Garmin Forerunner 165** (Connect IQ / Monkey C) with an **iOS companion app** (SwiftUI + SwiftData). The watch handles real-time set timing and automatic rep counting via the accelerometer; the phone receives completed sets over Bluetooth, persists workout history locally, classifies exercises' muscle activation with a free-tier LLM, and visualizes training load as a per-muscle heat map.

No paid backend, no subscriptions, no App Store distribution — everything runs locally, compiled by free tooling and sideloaded onto personal hardware.

---

## 1. Context

- **Target hardware:** Garmin Forerunner 165 (390×390 round AMOLED, 5 physical buttons + touch) and a personal iPhone.
- **Cost:** €0 — open-source/free-tier tooling only (Connect IQ SDK, XcodeGen, GitHub Actions free runners, Google AI Studio's Gemini free tier).
- **Distribution:** never published to the Connect IQ Store or the App Store. The watch app is sideloaded over USB; the iOS app is built unsigned in CI and sideloaded with a free Apple ID (SideStore / Sideloadly).
- **Offline-first:** the iOS app works fully offline in the gym. AI classification is a best-effort, cached-once enhancement — its absence never blocks logging a workout.

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
| `RESTING` | Rest timer running; shows the last completed set's summary. |
| `ACTIVE_SET` | Accelerometer sampling live, counting reps. |
| `EDIT_SET` | Reps/weight confirmation screen before the set is queued for transmission. |

Key components:
- **`RepDetector` + `AccelerometerSensor`** — 25 Hz accelerometer sampling, a 5-sample circular-buffer SMA filter, and hysteresis peak detection (1.2g dynamic threshold, 800 ms refractory lockout, 0.9g valley confirmation) to count repetitions without double-counting.
- **`CommunicationsService` + `SyncQueue`** — sends `SET_COMPLETED`/`SESSION_EVENT` payloads via `Toybox.Communications.transmit()`. Deliberately tolerant of unreliable BLE:
  - An in-memory FIFO queue retries unacknowledged `SET_COMPLETED` payloads every 10 s until a real `SYNC_ACK` arrives from the phone (not merely on transmit success, which only confirms the packet reached the phone's Bluetooth stack).
  - Ending a session vibrates, shows a brief "Session Saved" screen, and blocks `System.exit()` until the `SESSION_EVENT: STOP` transmit has actually settled — found necessary after field testing showed the watch process could otherwise be torn down before the packet left the device.
- **`SetSyncView` / `SetSyncDelegate`** — per-state rendering (state-specific accent colors, a live rep/rest timer, a 6-level heat-color palette shared with iOS) and physical-button/touch input handling. Button behavior was corrected against **real hardware**, not just the simulator: a genuine BACK-hold gesture is intercepted by the watch's firmware before ever reaching the app, so ending a session from `RESTING` uses a plain BACK press instead.

### 2.2 iOS Companion App (SwiftUI + SwiftData)

- **Navigation:** `RootTabView` with 4 tabs — **Today** (daily HealthKit summary, active-session banner, today's muscle activation), **Sessions** (workout history), **Exercises** (catalog + progression), **Watch / Settings** (Garmin pairing status and app configuration).
- **Persistence:** SwiftData (`Exercise`, `WorkoutSet`, `WorkoutSession`, `DailySummaryMetrics`), local-only, no CloudKit.
- **Garmin sync (`GarminSyncService`):** implements the ConnectIQ Mobile SDK's device/app-message delegates. Parses `SET_COMPLETED`/`SESSION_EVENT`, persists `WorkoutSet`/`WorkoutSession`, and always replies with `SYNC_ACK`. Hardened against real-world Bluetooth behavior:
  - **Idempotent set insertion:** the watch's 10 s retry can legitimately re-deliver the same `SET_COMPLETED` before its `SYNC_ACK` round-trip completes over real (higher-latency) BLE; sets are de-duplicated by the payload's own `timestamp` before insertion, while `SYNC_ACK` is still always sent to drain the watch's queue either way.
  - A manual **"Finish Workout"** button in the active-session view closes a session locally if the watch's `SESSION_EVENT: STOP` never arrives.
- **HealthKit (`HealthKitService`):** read-only daily steps/active/basal energy, queried on demand; fully defensive (`HKHealthStore.isHealthDataAvailable()` gates, never throws, never blocks the rest of the app if denied or unavailable).

### 2.3 AI Exercise Classification

New custom exercises are classified automatically instead of requiring the user to look up which muscles they train:

- **`GeminiExerciseClassifier`** calls Google AI Studio's `gemini-1.5-flash:generateContent` REST endpoint directly via `URLSession` (no vendor SDK, to avoid CI linking risk), requesting strict JSON output (`generationConfig.response_mime_type`/`response_schema`) shaped as `{"primary": [...], "secondary": [...]}` against the app's fixed muscle taxonomy.
- **API key:** read from the `GEMINI_API_KEY` environment variable first (useful for local development), falling back to a key the user saves once in **Settings → Gemini API Key**, persisted in `UserDefaults` (`GeminiAPIKeyStore`). The key is re-read on every classification call, so saving a new one in Settings takes effect immediately.
- **Manual fallback:** if no key is configured, the network call fails, or the response can't be parsed, the app shows an alert and falls back to `MuscleChipPicker` — a manual multi-select "chip" grid over every supported muscle group. The AI's suggestion is always editable before saving, never a locked-in answer.

### 2.4 Analytics & Muscle Map

- **Per-exercise progression (`ExerciseDetailView`):** all-time PR (max weight), estimated max 1RM (Epley formula, `weight × (1 + reps / 30)`, evaluated per set and taking the maximum — not necessarily the same set as the raw PR), total sets/reps, and a day-grouped chronological history.
- **Muscle heat map (`AnatomicalBodyView`):** an anterior/posterior anatomical body silhouette built from composed SwiftUI primitives (`Ellipse`/`Capsule`/`RoundedRectangle` regions over a light-gray outline `Shape`) — a schematic diagram at standard body-proportion ratios, not a hand-traced illustration, since there's still no design reference or local SwiftUI preview environment to visually verify freehand anatomical `Path` art. The frozen 23-case muscle taxonomy is grouped into 14 coarser visual regions for rendering only (e.g. `chestUpper`/`chestMiddle`/`chestLower` all color the same "chest" shape, using the max of their scores); the underlying per-muscle scoring is unchanged.
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
  - Rendered both on the **Today** tab (today's cumulative activation) and per-session in `SessionDetailView` (that session's sets only, plus a legend of how many sets stimulated each muscle).

---

## 3. Repository Structure

```text
/sunfit
├── .github/
│   └── workflows/
│       └── build-ios.yml          # Headless macOS CI: XcodeGen -> xcodebuild -> unsigned .ipa
├── CLAUDE.md                      # Operating guidelines for AI-assisted development on this repo
├── specs/                         # Source-of-truth specifications (spec-driven development)
│   ├── 01-system-spec.md          # Domain model, Bluetooth payload schemas, heat-map formula
│   ├── RULES.md                   # Development policy & monotask guardrails
│   ├── implementation-plan.md     # Atomic task checklist (all phases closed)
│   └── modules/
│       ├── 01-garmin-app.md               # Monkey C FSM, sensor algorithm, button map
│       ├── 02-ios-core-and-sync.md        # SwiftUI/SwiftData/HealthKit/Bluetooth/CI
│       ├── 03-ai-and-muscle-map.md        # Original AI classifier + heat map spec
│       └── 04-history-and-navigation.md   # Tab navigation, exercise catalog, session analytics
├── garmin/                        # Connect IQ (Monkey C) source
│   ├── manifest.xml
│   ├── monkey.jungle
│   ├── resources/
│   └── source/
└── ios/                           # SwiftUI source + XcodeGen project spec
    ├── project.yml
    └── App/Sources/
        ├── Models/                # Exercise, WorkoutSet, WorkoutSession, DailySummaryMetrics, MuscleGroup
        ├── Services/              # GarminSyncService, HealthKitService, GeminiExerciseClassifier, ...
        ├── Views/                 # RootTabView, TodayView, SessionsListView, ExercisesListView, ...
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

1. `xcodegen generate` turns `ios/project.yml` into an `.xcodeproj` (declaring the `ConnectIQ` Swift Package dependency, Info.plist/entitlements, Bluetooth/HealthKit permissions).
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
2. In the app, go to **Watch / Settings → Gemini API Key**.
3. Paste the key and tap **Save**. It's stored locally in `UserDefaults` and takes effect on the next exercise you create — no restart needed.

(For local development builds, the key can alternatively be supplied via the `GEMINI_API_KEY` environment variable, which takes priority over the one saved in Settings.)
