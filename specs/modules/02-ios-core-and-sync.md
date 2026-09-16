# Module Spec 02: iOS Core, Persistence & Garmin Sync

## 1. Stack & Architecture
- **Frameworks:** SwiftUI, SwiftData, HealthKit (`HKHealthStore`), `ConnectIQ.framework`.
- **Target OS:** iOS 17.0+.
- **Pattern:** MVVM + Service Layer.
- **Root Screens:**
  1. `DashboardView`: Resumen diario (pasos, calorías, métricas de actividad y estado de sesión).
  2. `ActiveWorkoutView`: Tabla en tiempo real con las series que van entrando del reloj.
  3. `ExerciseHistoryView`: Registro y evolución de peso/reps por ejercicio con vista de calendario.

---

## 2. Garmin ConnectIQ Listener Service (`GarminSyncService`)
- **Protocolos implementados:** `IQDeviceEventDelegate`, `IQAppMessageDelegate`.
- **Flujo de Recepción:**
  1. Detecta Forerunner 165 emparejado vía Garmin Connect Mobile.
  2. Escucha mensajes entrantes vía `receivedMessage()`.
  3. Parsea payloads JSON:
     - `SET_COMPLETED`: Crea un `WorkoutSet` en SwiftData asociado a la `WorkoutSession` activa.
     - `SESSION_EVENT`: Inicia o finaliza la sesión activa.
  4. Envía respuesta inmediata `SYNC_ACK` al reloj usando `sendMessage()` con el `setId` correspondiente.

  ---

## 3. HealthKit Integration (`HealthKitService`)
- **Permisos de Lectura:**
  - `HKQuantityTypeIdentifierStepCount`
  - `HKQuantityTypeIdentifierActiveEnergyBurned`
  - `HKQuantityTypeIdentifierBasalEnergyBurned`
- **Frecuencia:**
  - Consulta al abrir la app o acceder al `DashboardView`.
  - `HKStatisticsQuery` acumulado desde las `00:00:00` hasta el instante actual del día en curso.
- **Persistencia:** Almacena snapshot en `DailySummaryMetrics` en cada sincronización.

---

## 4. UI: Tabla de Series & Replicación (`ActiveWorkoutView`)
- **Lista reactiva:** Observa los `WorkoutSet` de la sesión activa ordenados por `timestamp`.
- **Selector de ejercicio:**
  - Dropdown (`Picker` o `Menu`) filtrable con campo de búsqueda.
  - Opción directa: *"Crear nuevo ejercicio"* si la búsqueda no arroja resultados.
- **Botón de Replicación ("Copiar Hacia Abajo"):**
  - Condición de visibilidad: Solo presente en la última serie con `exercise != nil` si existe al menos una serie posterior con `exercise == nil`.
  - Acción: Asigna `currentSet.exercise` únicamente a `nextSet.exercise` (el set inmediatamente siguiente), no a toda la cadena de huérfanos posteriores. Task 4.3 había ampliado esto a una propagación en cascada hasta el primer set ya etiquetado; un post-launch fix posterior revirtió esa ampliación de vuelta a la redacción original de este párrafo, ya que el comportamiento en cascada resultó no ser el deseado en el uso real: tras la asignación, `nextSet` pasa a ser la nueva última serie etiquetada, por lo que el botón de replicación se reubica automáticamente sobre ella (o desaparece, si no queda ninguna serie huérfana después) sin lógica adicional, gracias a la condición de visibilidad de arriba.
  - Invariante: No muta ni repeticiones (`reps`) ni carga (`weightKg`).

---

## 5. Headless Project Scaffolding & CI/CD Compilation

Como el desarrollo se realiza en un host Windows 11 sin Xcode instalado:
- **Estructura iOS:** El proyecto se estructura como una carpeta estándar de fuentes Swift (`ios/App/Sources`) acompañada de un archivo de especificación declarativo de Xcode (`ios/project.yml` usando **XcodeGen** o script nativo de `swift package`).
- **Pipeline de GitHub Actions (`.github/workflows/build-ios.yml`):**
  - **Runner:** `macos-latest`.
  - **Pasos de compilación:**
    1. Checkout del repositorio.
    2. Descarga del SDK oficial `ConnectIQ.framework` de Garmin desde su repositorio/release oficial.
    3. Generación del proyecto `.xcodeproj` mediante `xcodegen` en el runner.

4. Compilación de Release headless:
       ```bash
       xcodebuild -project SunFit.xcodeproj \
         -scheme SunFit \
         -configuration Release \
         -sdk iphoneos \
         CODE_SIGN_IDENTITY="" \
         CODE_SIGNING_REQUIRED=NO \
         CODE_SIGNING_ALLOWED=NO \
         CONFIGURATION_BUILD_DIR=build/Release-iphoneos
       ```
    5. Empaquetado en `.ipa` sin firma:
       ```bash
       mkdir -p Payload
       cp -r build/Release-iphoneos/SunFit.app Payload/
       zip -r SunFit.ipa Payload
       ```
    6. Publicación del artefacto `SunFit.ipa` descargable en GitHub Actions.
- **Instalación en iPhone:** Se descarga el `.ipa` en Windows y se firma/instala en el dispositivo mediante SideStore o Sideloadly.