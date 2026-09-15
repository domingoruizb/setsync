# 01 - System Specification: Domain Model, Communication & Heat Maps

## 1. Domain Entities (SwiftData)

### 1.1 Exercise
- id: UUID
- name: String (lowercase, e.g., "press inclinado con mancuernas")
- primaryMuscle: MuscleGroup
- secondaryMuscles: [MuscleGroup]
- createdAt: Date

### 1.2 WorkoutSet
- id: UUID
- exercise: Exercise? (nil until assigned in iOS)
- reps: Int
- weightKg: Double
- setDurationSeconds: Int
- restDurationSeconds: Int
- detectedAutomatically: Bool
- timestamp: Date

### 1.3 WorkoutSession
- id: UUID
- startDate: Date
- endDate: Date?
- sets: [WorkoutSet]
- totalActiveTime: TimeInterval
- totalRestTime: TimeInterval
- status: Enum (inProgress, completed, discarded)

### 1.4 DailySummaryMetrics (HealthKit)
- date: Date
- stepCount: Int
- activeEnergyBurnedKcal: Double
- restingEnergyBurnedKcal: Double

---

## 2. Garmin <-> iOS Bluetooth Protocol

### 2.1 SET_COMPLETED (Garmin -> iOS)
```json
{
  "msgType": "SET_COMPLETED",
  "payload": {
    "setId": "1694707200000",
    "reps": 10,
    "weightKg": 24.0,
    "durationSec": 42,
    "restSec": 95,
    "timestamp": 1726329600
  }
}

### 2.2 SESSION_EVENT (Garmin -> iOS)
```json
{
  "msgType": "SESSION_EVENT",
  "payload": {
    "action": "START",
    "timestamp": 1726329000
  }
}

### 2.3 SYNC_ACK (iOS -> Garmin)
```json 
{
  "msgType": "SYNC_ACK",
  "payload": {
    "setId": "1694707200000",
    "status": "OK"
  }
}

## 3. Muscle Taxonomy & Heat Map

### 3.1 Identificadores de Músculos
Pecho: chest_upper, chest_middle, chest_lower

Espalda: lats, traps_upper, traps_middle, rhomboids, lower_back

Hombros: deltoid_anterior, deltoid_lateral, deltoid_posterior

Brazos: biceps, triceps_long_head, triceps_lateral_head, forearms

Core: abs_upper, abs_lower, obliques

Piernas: quadriceps, hamstrings, glutes, calves, adductors

### 3.2 Escala de Calor (5 Niveles)
Cálculo: Score = Suma(1.0 si es primario, 0.4 si es secundario por cada serie)

Nivel 0 (Score = 0): #2C2C2E (Gris neutro)

Nivel 1 (0 < Score <= 1.5): #FFE082 (Amarillo suave)

Nivel 2 (1.5 < Score <= 3.0): #FFB74D (Ámbar)

Nivel 3 (3.0 < Score <= 5.0): #FF7043 (Naranja intenso)

Nivel 4 (5.0 < Score <= 7.0): #F4511E (Rojo anaranjado)

Nivel 5 (Score > 7.0): #D32F2F (Rojo profundo)

## 4. Lógica de Replicación en UI (iOS)
Toda serie recibida entra con exercise = nil.

En la última serie con ejercicio asignado, se habilita un botón que copia ese ejercicio a la fila siguiente sin modificar repeticiones ni peso.
