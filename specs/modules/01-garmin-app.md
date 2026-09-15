# Module Spec 01: Garmin Connect IQ App (Forerunner 165)

## 1. Context & Lifecycle
- **App Type:** Device App (fullscreen control, direct button handling).
- **Target Device:** Garmin Forerunner 165 (390x390 AMOLED, 5 physical buttons).
- **States (FSM):**
  1. `IDLE`: Workout not started. Single "START WORKOUT" action.
  2. `RESTING`: Rest timer running. Displays last set summary, rest elapsed time, and "START SET" prompt.
  3. `ACTIVE_SET`: Accelerometer running. Live rep count, set duration timer, "FINISH SET" action.
  4. `EDIT_SET`: Reps & weight adjustment screen before transmission.

---

## 2. Sensor & Rep Detection Algorithm
- **Sampling:** `Toybox.Sensor.registerSensorDataListener()` at 25 Hz.
- **Axes:** 3D vector magnitude:
  $$a(t) = \sqrt{x(t)^2 + y(t)^2 + z(t)^2}$$
- **Filtering:** Simple Moving Average (SMA) over a 5-sample sliding window to filter out high-frequency jitter.
- **Peak Detection Logic:**
  - Dynamic thresholding: Detect local maxima exceeding baseline threshold ($1.2g$).
  - Refractory period: Minimum lockout of 800 ms between peaks to prevent double-counting within a single repetition stroke.
  - Zero-crossing / valley confirmation: Require acceleration to drop below $0.9g$ before accepting the next peak.

  ---

## 3. Physical Button Controls (Forerunner 165)

| Screen / State | Physical Button | Action |
|---|---|---|
| `IDLE` | **START/STOP** | Inicia sesión (`SESSION_EVENT: START`) y pasa a `RESTING`. |
| `RESTING` | **START/STOP** | Inicia serie, arranca acelerómetro y pasa a `ACTIVE_SET`. |
| `ACTIVE_SET` | **START/STOP** | Detiene serie, vibra y pasa a `EDIT_SET` con reps calculadas. |
| `EDIT_SET` | **UP / DOWN** | Incrementa o decrementa repeticiones (+/- 1) o peso (+/- 1.0 kg). |
| `EDIT_SET` | **START/STOP** | Confirma serie, encola payload `SET_COMPLETED` y pasa a `RESTING`. |
| `RESTING` | **BACK (Hold)** | Diálogo de fin de sesión (`SESSION_EVENT: STOP`) y vuelve a `IDLE`. |

---

## 4. Transmission & Offline Queue
- **Módulo:** `Toybox.Communications.transmit()`.
- **Cola local (FIFO):**
  - Si el Bluetooth está desconectado o el teléfono fuera de rango, el payload `SET_COMPLETED` se almacena en memoria volátil/App Storage.
  - Al recibir `SYNC_ACK` desde el iPhone, se remueve el ítem confirmado de la cola.
  - Reintento periódico cada 10 segundos si la cola no está vacía y el estado del enlace es `true`.