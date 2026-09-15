# Module Spec 03: AI Muscle Classifier & Dynamic Heat Map

## 1. AI Muscle Classifier Service (`MuscleClassifierService`)
- **Proveedor:** Google AI Studio REST API (Gemini 1.5 Flash via Free Tier).
- **Trigger:** Únicamente al registrar un nuevo ejercicio no existente en la base de datos local.
- **Formato:** Inferencia estricta con Structured Outputs (JSON Schema).

### 1.1 Contrato del System Prompt
```text
Clasifica el ejercicio de fuerza proporcionado dentro de la taxonomía muscular estandarizada.
Responde ÚNICAMENTE con un objeto JSON válido con las claves "primary" (un solo identificador)
y "secondaries" (array de identificadores).

Taxonomía permitida:
chest_upper, chest_middle, chest_lower, lats, traps_upper, traps_middle, rhomboids,
lower_back, deltoid_anterior, deltoid_lateral, deltoid_posterior, biceps,
triceps_long_head, triceps_lateral_head, forearms, abs_upper, abs_lower, obliques,
quadriceps, hamstrings, glutes, calves, adductors.

### 1.2 Formato de Respuesta
```json
{
  "primary": "chest_upper",
  "secondaries": ["deltoid_anterior", "triceps_lateral_head"]
}

---

## 2. Dynamic Muscle Heat Map Component (`MuscleHeatMapView`)
- **Renderizado:** Componente SwiftUI basado en formas vectoriales (Shape o Paths SVG) representando vistas frontal y dorsal del cuerpo humano.
- **Mapeo de IDs:** Cada región vectorial tiene asignado un identificador único de `MuscleGroup`.
- **Cálculo de Color:**
  - Se calcula el `Score` acumulado sumando 1.0 por serie si es músculo primario y 0.4 si es secundario, sobre los `WorkoutSet` cuyo `timestamp` cae en el día natural de hoy (00:00 local hasta el instante actual) — periodo concreto acordado en Task 5.2 de `specs/implementation-plan.md`, ya que esta tarea no incluye un selector de periodo; coherente con la sección "Today" del `DashboardView`.
  - El valor resultante se proyecta directamente a los 5 niveles cromáticos definidos en `specs/01-system-spec.md`.
- **Interactividad:** Al pulsar un grupo muscular coloreado, se despliega una tarjeta flotante indicando el nombre del músculo, las series acumuladas y los ejercicios que lo activaron.
