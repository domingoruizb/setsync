# SunFit - Project Context & Development Guidelines

## Project Overview
SunFit is a personal, zero-cost workout tracking ecosystem composed of:
1. **Garmin Connect IQ Watch App** (`/garmin`): Runs on a Garmin Forerunner 165. Handles real-time set timing, automatic repetition counting via accelerometer peak detection, manual rep/weight correction via physical buttons, and local Bluetooth transmission.
2. **iOS Companion App** (`/ios`): Native SwiftUI app for iPhone. Receives sets via Garmin Connect Mobile SDK, provides live workout logging with drag/copy exercise utilities, queries an LLM (Gemini Flash via free tier) to classify muscle activation, renders a 5-tier dynamic muscle heat map, and aggregates daily steps/calories via HealthKit.

---

## Core Philosophy & Cost Constraints
- **Zero Cost (0 €):** Strictly rely on open-source libraries, local on-device persistence, free developer signing (SideStore/personal provisioning), and free-tier APIs (Google AI Studio / Gemini 1.5 Flash). No paid cloud backends or subscriptions.
- **Local-First:** All workout history and exercise catalogs persist locally on the iPhone. AI classification is executed once per new exercise and cached permanently. The app functions entirely offline in the gym.
- **Cross-Platform Host Environment:** Development takes place on Windows 11. Monkey C is compiled locally with the Connect IQ VS Code extension. Swift/iOS is compiled remotely using free GitHub Actions macOS runners to produce `.ipa` artifacts for local installation (SideStore / Sideloadly).
- **Spec-Driven Development (SDD):** 
  - Never write production code without an approved technical specification under `/specs`.
  - Specs act as contracts: payload formats, state machines, and data schemas must be frozen before implementation.
  - Implement task by task following `specs/implementation-plan.md`.

---

## Architecture & Technology Stack

### Garmin Component (`/garmin`)
- **Language & Framework:** Monkey C, Garmin Connect IQ SDK (latest 7.x).
- **Target Device:** Garmin Forerunner 165 (390x390 AMOLED, button-operated).
- **Key Modules:**
  - `Toybox.Sensor`: Accelerometer listener (`registerSensorDataListener`) for peak-detection repetition counting.
  - `Toybox.Communications`: Direct payload transmission to iOS companion via `transmit()`.
  - `Toybox.Attention`: Vibration feedback for set start/stop.
  - `Toybox.Time`: Active set duration vs. rest period stopwatch tracking.

### iOS Component (`/ios`) & CI/CD Pipeline
- **Language & Framework:** Swift (latest stable), SwiftUI.
- **Persistence:** SwiftData (local storage with optional private CloudKit sync).
- **Health Integration:** HealthKit (`HKHealthStore`) for daily step count and active/basal caloric burn.
- **Device Communication:** Official `ConnectIQ.framework` (Garmin Connect Mobile SDK for iOS).
- **AI Integration:** Direct REST calls to Google AI Studio (Gemini Flash endpoint) with strict JSON schema outputs.
- **Build Pipeline (`.github/workflows/build-ios.yml`):** macOS runner executing `xcodebuild` without code signing, packaging the payload into an unsigned `.ipa` artifact ready for sideloading.

---

## Repository Structure
```text
/sunfit
├── .github/
│   └── workflows/
│       └── build-ios.yml        # Cloud macOS build pipeline for iOS app
├── CLAUDE.md                    # Operational guidelines and project context
├── specs/                       # Source of truth specifications
│   ├── 01-system-spec.md        # Unified domain model, payloads & heat formulas
│   ├── RULES.md                 # Development policy & monotask guardrails
│   ├── implementation-plan.md   # Atomic implementation checklists
│   └── modules/
│       ├── 01-garmin-app.md     # Monkey C architecture & signal processing
│       ├── 02-ios-core-sync.md  # SwiftUI, SwiftData, HealthKit, Bluetooth & CI/CD
│       └── 03-ai-muscle-map.md  # LLM prompts, caching & visual heat map
├── garmin/                      # Connect IQ source code
└── ios/                         # SwiftUI source code & project scaffolding

SDD Workflow Rules for Claude Code
Spec First: If a requested feature or change is not defined in /specs, update or draft the spec before writing code.

Deterministic Interfaces: Payloads exchanged over Bluetooth (Garmin -> iOS) must strictly match the schemas declared in specs/01-system-spec.md.

Incremental Progress: Complete one atomic task from specs/implementation-plan.md at a time. Validate compilation and logic before marking it done and moving forward.

No Premature Complexity: Avoid third-party abstractions when native SDK APIs suffice. Keep the codebase lightweight and maintainable.

Execution Guardrails: Follow all directives in specs/RULES.md strictly on every turn.

