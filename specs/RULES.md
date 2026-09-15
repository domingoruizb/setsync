# Development Policy & Agent Guardrails (Spec-Driven Development)

## 1. Regla de Oro: Ejecución Monotarea
- **Una sola tarea a la vez:** El agente solo puede ejecutar UNA subtarea de `specs/implementation-plan.md` por interacción.
- **Prohibición de auto-avance:** Queda estrictamente prohibido pasar a la siguiente tarea sin la confirmación explícita del usuario en el chat.
- **Sin código no especificado:** Todo archivo, clase o función generada debe corresponderse estrictamente con lo definido en `specs/`.

---

## 2. Protocolo Obligatorio por Tarea (Workflow Loop)
Antes de dar cualquier tarea por concluida, el agente debe seguir estos 4 pasos:

1. **Lectura previa:** Confirmar que ha leído la especificación del módulo correspondiente en `specs/modules/`.
2. **Implementación atómica:** Generar exclusivamente el código necesario para la tarea activa.
3. **Validación:** Comprobar que no hay errores de sintaxis, tipos o referencias rotas.
4. **Actualización de estado:** Marcar con `[x]` la tarea completada en `specs/implementation-plan.md` y detenerse inmediatamente pidiendo validación al usuario.

---

## 3. Restricciones Técnicas Inquebrantables
- **Coste 0 €:** Prohibido añadir dependencias de pago, librerías con licencia comercial o APIs sin tier gratuito documentado en las specs.
- **Invarianza de payloads:** Los payloads JSON de Bluetooth deben coincidir carácter por carácter con las claves de `specs/01-system-spec.md`.
- **Modo Offline:** La app debe funcionar en el gimnasio sin cobertura. Las llamadas a la IA son exclusivas para ejercicios nuevos y deben persistirse localmente en caché.

---

## 4. Manejo de Ambigüedades y Cambios
- Si un detalle técnico no está cubierto en la especificación, el agente **no improvisa**.
- Debe formular una pregunta concreta al desarrollador con opciones propuestas.
- Toda decisión nueva acordada debe escribirse primero en el archivo `.md` de la spec antes de tocar el código.

---

## 5. Control de Versiones (Git) y Entorno de Compilación
- **Host sin Xcode:** El agente opera en Windows 11. No debe intentar invocar `xcodebuild`, `xcrun` ni simuladores de iOS en local. La compilación de iOS delega exclusivamente en el workflow de GitHub Actions.
- **Commits Atómicos por Tarea:** Al finalizar y verificar cada subtarea de `specs/implementation-plan.md`, el agente debe proponer o ejecutar un commit de Git siguiendo la convención Conventional Commits (ej. `feat(ios): implement SwiftData models for task 1.2`).