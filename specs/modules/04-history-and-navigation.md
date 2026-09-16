# Module Spec 04: Tab Navigation, Exercise Catalog & Session Analytics

Origin: requested directly by the user as a post-launch feature addition (not part of the original 5-phase plan); decisions below were resolved with the user before implementation, per `specs/RULES.md` §4.

---

## 1. Navigation Restructure

`SetSyncApp`'s root view becomes a `TabView` with 4 tabs:

1. **Today** — the existing `DashboardView` content (daily HealthKit summary, active-session banner, muscle activation for today). Garmin pairing/status moves out to Tab 4.
2. **Sessions** — chronological list (descending by `startDate`) of `WorkoutSession`s, navigating to `SessionDetailView` (§4).
3. **Exercises** — searchable list of all `Exercise`s (existing/custom), navigating to `ExerciseDetailView` (§3). Also the entry point for creating a new custom exercise.
4. **Watch / Settings** — Garmin device pairing/status (moved from `DashboardView`), `selectDevice()` action.

---

## 2. Extended `Exercise` Model

**Breaking SwiftData schema change, accepted by the user with data loss** (pre-launch, zero-cost project; no `SchemaMigrationPlan`/`VersionedSchema` written — existing local `Exercise`/`WorkoutSet` data from field testing will not survive the next install).

```swift
@Model
final class Exercise {
    var id: UUID
    var name: String                       // lowercase, per specs/01-system-spec.md §1.1
    var category: String
    var primaryMuscles: [MuscleGroup]       // was `primaryMuscle: MuscleGroup` (singular)
    var secondaryMuscles: [MuscleGroup]
    var isCustom: Bool
}
```

- `primaryMuscles`/`secondaryMuscles` reuse the existing `MuscleGroup` enum (`ios/App/Sources/Models/MuscleGroup.swift`, frozen taxonomy from `specs/01-system-spec.md` §3.1) — no new `MuscleRegion` type, to avoid duplicating an already-frozen taxonomy.
- `createdAt` is dropped (not used by any built feature).
- `category` is a free-form string (e.g. "Push", "Pull", "Legs") set by the pre-seed list or left to the classification/manual-edit flow for custom exercises.
- `isCustom`: `false` for pre-seeded exercises, `true` for user-created ones.

**Pre-seed library:** ~25 common strength exercises inserted once (on first launch / empty catalog) with `isCustom = false` and correct `primaryMuscles`/`secondaryMuscles` already assigned — no AI classification call needed for these.

---

## 3. Custom Exercise Creation & Classification

Renaming/evolving `MuscleClassifierService` (Task 5.1) into **`GeminiExerciseClassifier`**, since the result shape changed from a single `primaryMuscleGroup` to a `primaryMuscles` array — one service, not two competing ones calling Gemini for the same purpose.

- User enters only the exercise name (any language — the prompt handles translation/interpretation).
- **Request** — same endpoint/technique as Task 5.1 (`URLSession`, API key as a `key` query item on the URL):
  `https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=<apiKey>`.
  `generationConfig` body fields are **`response_mime_type`/`response_schema` (snake_case)** — verified directly against Google's REST API reference (`ai.google.dev/api/generate-content`) during this task, not assumed: the REST JSON wire format for `generateContent` uses snake_case internally even though the top-level `generationConfig` key itself is camelCase; some client SDKs additionally accept `responseSchema`, but the raw REST body (what a plain `URLSession` request sends) does not reliably. Kept as Task 5.1 already had it — a corrected instruction using camelCase here was not applied.
- **Response schema** (this project's own choice of JSON property names, not a Google-mandated shape): `{"primary": [STRING], "secondary": [STRING]}` — both arrays, matching the fixed `MuscleGroup` taxonomy (`specs/01-system-spec.md` §3.1). Renamed from Task 5.1's `primaryMuscleGroup`/`secondaryMuscleGroups` to match `Exercise`'s new plural fields.
- Response is parsed with the same safe/case-insensitive mapping as Task 5.1 (`MuscleGroup.init?(safeRawValue:)`); unmappable strings are dropped, not fabricated.
- **API key sourcing, extended from Task 5.1:** still checks `ProcessInfo.processInfo.environment["GEMINI_API_KEY"]` first, then falls back to a value the user enters once in the new **Settings** tab. Stored via **`UserDefaults`** (the user offered `UserDefaults` or `Keychain`; `UserDefaults` was chosen — this project's real threat model is "a single personal, sideloaded, never-distributed app," where Keychain's stronger-but-untestable-here API surface isn't worth the added risk of writing security-framework code with no local compiler to check it against; the key is exactly as sensitive on this device either way, and never leaves it except in the classification request itself).
- **Failure handling:** if no key is configured (after both sources) or the network request fails, show a plain SwiftUI alert, then fall back to **manual multi-select "chip" controls** for `primaryMuscles`/`secondaryMuscles` (a wrapping grid of toggleable capsules over `MuscleGroup.allCases` — no third-party layout package, per this project's zero-cost/no-heavy-dependency stance) instead of leaving the fields empty with no way to fill them in.
- **Interactive preview before saving:** the classified (or manually chip-selected) result renders in a small `MuscleHeatMapView`-style preview highlighting only the selected primary/secondary muscles (not a real score), with the same chip controls available to adjust before saving — the AI result is a starting point, not a locked-in answer.
- `ExercisePickerView` (Task 4.2) keeps its existing search + inline-creation entry point, now opening this full creation flow instead of the single-muscle quick-picker.

---

## 4. `ExerciseDetailView` (Exercises tab)

Per-exercise history and progression, reached from the Exercises tab list.

- **Header stats:**
  - PR / Top Weight: `max` of `weightKg` across all of this exercise's `WorkoutSet`s, ever.
  - Estimated max 1RM: Epley formula, `weightKg * (1 + reps / 30.0)`, taken over the single set with the highest computed value (not necessarily the PR set).
  - Total sets and total reps recorded, all-time.
- **Chronological history**, most recent first: grouped by day, each set showing reps × weight (`5 reps x 80 kg`).

This supersedes/extends `ExerciseHistoryView` (Task 5.3), which already implements PR + day-grouped history; Task 6.4 adds the 1RM/total-volume stats and the total-sets/total-reps counters on top of that existing view rather than building a parallel one from scratch.

---

## 5. `SessionDetailView` (Sessions tab) & Per-Session Muscle Map

- Header: date, start/end time, total duration.
- Sets grouped by exercise, each showing ordinal (Set 1, Set 2...), reps, weight, set duration, rest duration.
- **Muscle map for this session only:**
  - Same stimulus formula as the existing Dashboard heat map (`specs/01-system-spec.md` §3.2 / `MuscleHeatMapView.muscleScores(from:)`, Task 5.2): +1.0 per set to each of the set's exercise's `primaryMuscles`, +0.5 to each `secondaryMuscles` — now iterating an array of primaries instead of one.
  - **Same 6-level color scale already frozen in `specs/01-system-spec.md` §3.2** (reused via `MuscleGroup.heatColor(forScore:)`, zero new color logic) — the user's initially-proposed separate 4-tier "0 / 1-2 / 3-5 / 6+" palette for this view was not adopted, to keep exactly one heat scale across the whole app (Dashboard "today" map and this per-session map render identically for the same score).
  - Rendered with the same modular tile grid as `MuscleHeatMapView` (Task 5.2) — no anatomical body-silhouette artwork exists to render from (none was provided when asked); reuses that view/component directly, scoped to this session's sets instead of today's.
  - Legend: for each muscle group with `score > 0`, the number of sets that stimulated it this session.
