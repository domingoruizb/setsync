# Module Spec 03: AI Muscle Classifier & Dynamic Heat Map

## 1. AI Muscle Classifier Service (`MuscleClassifierService`)
- **Proveedor:** Google AI Studio REST API (Gemini 1.5 Flash via Free Tier).
- **Trigger:** Únicamente al registrar un nuevo ejercicio no existente en la base de datos local.
- **Formato:** Inferencia estricta con Structured Outputs (JSON Schema).
- **Idioma de entrada:** el nombre del ejercicio introducido por el usuario será típicamente español (terminología común de gimnasio, ej. "press de banca", "sentadilla trasera"), ya que la app está localizada al español (refactor "Localización al Español y Renderizado del Muscle Map Anatómico"); el prompt lo indica explícitamente, pero sigue clasificando correctamente nombres en otros idiomas. Los identificadores de salida (`primary`/`secondary`) permanecen en inglés snake_case — es la taxonomía interna congelada de `MuscleGroup`, no texto de interfaz.

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

## 2. Dynamic Muscle Heat Map Component (`AnatomicalBodyView`)
- **Renderizado:** Componente SwiftUI basado en formas vectoriales (Shape/Path de SwiftUI, sin SVG externo) representando vistas frontal (Anterior) y dorsal (Posterior) del cuerpo humano — un contorno neutro gris claro (cabeza, torso, brazos, piernas) con regiones musculares superpuestas como formas independientes. Task 5.2 había sustituido temporalmente este componente por una rejilla modular de tiles de texto (`MuscleHeatMapView`), al no disponer de imagen de referencia ni de un entorno de preview local de SwiftUI para verificar visualmente una silueta `Path` dibujada a mano; el refactor "Localización al Español y Renderizado del Muscle Map Anatómico" revierte esa decisión y entrega la silueta anatómica originalmente especificada aquí, aceptando que su acabado visual no puede verificarse antes de verla en un dispositivo real (misma limitación de siempre) y que puede necesitar ajustes posteriores, igual que la UI del reloj Garmin necesitó varias rondas tras las pruebas en hardware real.
- **Mapeo de IDs → regiones visuales:** cada una de las 23 `MuscleGroup` (taxonomía fina, sin cambios) se asigna a exactamente una de 14 regiones visuales más gruesas (`MuscleGroup.BodyRegion`: `chest`, `frontDeltoids`, `biceps`, `forearms`, `abs`, `quads` en Anterior; `rearDeltoids`, `triceps`, `lats`, `traps`, `lowerBack`, `glutes`, `hamstrings`, `calves` en Posterior) — la agrupación visual necesaria para que la silueta sea legible sin superponer 23 formas diminutas. El color de una región usa el **máximo** de los scores de sus músculos constituyentes (no la suma ni la media), para que un único músculo muy trabajado se vea "caliente" sin diluirse por un vecino no entrenado que comparte la misma forma dibujada.
- **Cálculo de Color:**
  - Se calcula el `Score` acumulado sumando 1.0 por serie si es músculo primario y 0.4 si es secundario, sobre los `WorkoutSet` cuyo `timestamp` cae en el día natural de hoy (00:00 local hasta el instante actual) — periodo concreto acordado en Task 5.2 de `specs/implementation-plan.md`, ya que esta tarea no incluye un selector de periodo; coherente con la sección "Hoy" de `TodayView`. Sin cambios respecto a Task 5.2: solo cambió el renderizado, no el scoring.
  - El valor resultante se proyecta directamente a los 6 niveles cromáticos definidos en `specs/01-system-spec.md`.
- **Localización:** el componente no muestra texto sobre la silueta (a diferencia de la rejilla de tiles que sustituye); donde sí se muestran nombres de músculo en la app (leyenda de `SessionDetailView`, chips de selección manual, previsualización de `ExerciseCreationView`), se usa siempre `MuscleGroup.displayName` (español), nunca el `rawValue` interno (inglés, snake_case, contrato congelado con el clasificador de IA).
- **Interactividad:** Al pulsar un grupo muscular coloreado, se despliega una tarjeta flotante indicando el nombre del músculo, las series acumuladas y los ejercicios que lo activaron. **Sigue sin implementarse** (fuera del alcance de este refactor, igual que en Task 5.2).
