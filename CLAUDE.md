# Control Tiempos Eclipse — Brief para el agente de Xcode

Este archivo guía al agente de Xcode 27 durante todo el desarrollo de la app.
Léelo completo antes de escribir código. Trabaja paso a paso, confirmando con
Francisco antes de avanzar a cada fase. No des nada por terminado sin compilar.

---

## 1. Qué es la app

**Control Tiempos Eclipse** es una app nativa de iPhone para fotógrafos de
eclipses solares. Dado un lugar y una fecha, calcula (sin conexión) las
circunstancias locales del eclipse (contactos C1–C4, máximo, duración de la
totalidad) y ejecuta un **programa de avisos hablados** — una secuencia de
eventos definidos por el usuario en tiempo relativo a las fases del eclipse —
pronunciando cada aviso en el segundo exacto, para que el fotógrafo opere sus
cámaras sin mirar la pantalla.

Usuario: Francisco Cornellana, fotógrafo y programador avanzado. Primer uso
real: eclipse total del 12 de agosto de 2026 en España. La app debe estar
ensayada y congelada días antes.

---

## 2. Flujo funcional (máquina de estados)

La app es un flujo lineal de 5 pasos. Interrumpir la ejecución (paso 5)
devuelve siempre al paso 1.

### Paso 1 — Localización
Dos vías, presentadas juntas al arrancar:
- **Ubicación actual**: CoreLocation (When In Use), una lectura puntual con
  `kCLLocationAccuracyHundredMeters` es suficiente.
- **Coordenadas manuales**: campos de latitud y longitud en grados decimales
  (formato ±DD.DDDDD), validados (lat −90…90, lon −180…180). Entrada inmediata,
  sin buscador de lugares.

### Paso 2 — Fecha del evento
`DatePicker` (solo fecha, sin hora). Por defecto, la fecha del próximo eclipse
del dataset visible desde esa localización si existe; si no, la fecha de hoy.

### Paso 3 — Verificación sobre mapa
- Mapa (MapKit) centrado en las coordenadas con un marcador en el punto exacto.
  Zoom inicial: radio ~50 km (que se vea claramente dónde estamos). El mapa es
  contextual, no un selector: no cambia la localización elegida.
- El **motor de eclipse** (sección 4) evalúa lugar + fecha:
  - **Hay eclipse visible** → mostrar tarjeta de resultados: tipo (total /
    parcial / anular), C1, C2 (si aplica), máximo, C3 (si aplica), C4,
    magnitud, duración de totalidad, altura y azimut del Sol en el máximo.
    Todas las horas en la zona horaria del dispositivo, formateadas con
    `FormatStyle`.
  - **No hay eclipse** (fecha sin eclipse, o el punto queda fuera de la zona
    de visibilidad) → **modo simulación**, indicado con claridad visual
    (badge "SIMULACIÓN"): se pide la hora del eclipse supuesto (hora de
    inicio de totalidad, C2) y se generan fases ficticias con esta plantilla:
    `C1 = C2 − 60 min · Máximo = C2 + 40 s · C3 = C2 + 80 s · C4 = C2 + 60 min`.
    La duración de totalidad simulada (80 s) debe ser una constante fácil de
    localizar en el código.
- Botón «Continuar» para pasar al programa.

### Paso 4 — Programa de eventos
El programa es una lista ordenada de **eventos relativos a las fases**:

| Campo | Tipo | Ejemplo |
|---|---|---|
| Fase de referencia | C1 / C2 / MAX / C3 / C4 | C2 |
| Offset | segundos, positivo o negativo | −20 |
| Texto del aviso | localizable, lo que se pronunciará | «Quitar filtro solar» |

- Si existe un programa guardado, se muestra y se permite **editar** cada
  evento, **añadir**, **eliminar** individualmente y **borrar todo** (con
  confirmación). Si no existe, lista vacía con alta directa.
- El programa persiste entre sesiones (un único programa activo; el modelo
  debe dejar la puerta abierta a varios programas con nombre en el futuro).
- La lista se muestra ordenada por tiempo absoluto resuelto contra las fases
  vigentes, con la hora real calculada junto a cada evento.
- Eventos cuyo instante resuelto ya ha pasado al iniciar la ejecución se
  marcan como omitidos, no se pronuncian.

### Paso 5 — Ejecución
- Pantalla con el **mapa de la localización de fondo** y la **lista de
  eventos superpuesta** (material translúcido). El **próximo evento queda
  centrado verticalmente** en pantalla, con su cuenta atrás en tipografía
  muy grande y alto contraste.
- En el instante exacto de cada evento: se **pronuncia el texto** con
  `AVSpeechSynthesizer` en el idioma de los ajustes, se dispara un háptico
  (`.notification(.success)`), y la lista hace **scroll animado** para
  centrar el siguiente evento.
- Cabecera fija: fase actual del eclipse y cuenta atrás al próximo contacto.
- Durante la ejecución: `UIApplication.shared.isIdleTimerDisabled = true`
  (pantalla siempre encendida) y sesión de audio `.playback` con
  `.duckOthers` para que la voz suene por encima de música ambiente.
- **Interrupción protegida**: botón «Detener» que exige **pulsación mantenida
  de 3 segundos** con anillo de progreso visible; soltar antes cancela. Al
  detener (o al terminar el último evento) se vuelve al paso 1.
- Diseñada para uso en primer plano. No usar notificaciones locales como
  mecanismo principal de avisos.

### Ajustes (accesibles desde el paso 1)
- **Idioma de la voz**: Español (es-ES) / Català (ca-ES) / English (en-GB).
  Afecta a la voz sintetizada Y al idioma de la interfaz.
- Velocidad de la voz (rango razonable de `AVSpeechUtterance.rate`).
- Persisten en `UserDefaults`.

---

## 3. Arquitectura

- **MVVM con `@Observable`** (Observation framework). Sin Combine, sin UIKit
  salvo lo imprescindible (idle timer, háptica).
- Máquina de estados explícita del flujo:
  `enum AppStep { case location, eventDate, verification, program, execution }`
  gobernada por un `FlowViewModel` raíz.
- **Motor de tiempos sin deriva**: los eventos se programan contra `Date`
  absolutos. Un único timer de tick (0,25 s) compara `Date.now` contra el
  próximo instante; nunca acumular intervalos. La pronunciación debe ocurrir
  con error < 0,3 s respecto al instante calculado.
- Servicios sin estado como `struct` con métodos estáticos o inyectados por
  inicializador: `EclipseEngine`, `SpeechService`, `ProgramStore`.
- Persistencia: **SwiftData** para el programa (modelo `ProgramEvent`);
  `UserDefaults` para ajustes.

### Modelos de dominio (orientativos)

```swift
enum EclipsePhase: String, Codable, CaseIterable { case c1, c2, max, c3, c4 }

/// Evento del programa, relativo a una fase del eclipse.
@Model final class ProgramEvent {
    var phase: EclipsePhase.RawValue
    var offsetSeconds: Int          // negativo = antes de la fase
    var message: String             // texto que se pronunciará
    var sortIndex: Int
}

/// Circunstancias locales calculadas (o simuladas).
struct EclipseCircumstances {
    let kind: EclipseKind           // .total, .annular, .partial, .simulated
    let contacts: [EclipsePhase: Date]  // c2/c3 ausentes si es parcial
    let magnitude: Double?
    let sunAltitudeAtMax: Double?
    let sunAzimuthAtMax: Double?
}

/// Evento resuelto a hora absoluta, listo para ejecutar.
struct ScheduledCue: Identifiable {
    let id: UUID
    let fireDate: Date
    let message: String
    var state: CueState             // .pending, .spoken, .skipped
}
```

---

## 4. Motor de eclipse (EclipseEngine) — núcleo del proyecto

**Enfoque: elementos besselianos embebidos + algoritmo clásico de
circunstancias locales.** 100 % offline, sin dependencias.

1. **Dataset**: fichero `data/eclipses.json` embebido en el bundle con los
   elementos besselianos (coeficientes polinómicos x, y, d, l1, l2, μ, tanF1,
   tanF2, t0, ΔT) de **todos los eclipses solares de 2025 a 2035**. Fuente de
   los valores: publicaciones de NASA GSFC / Fred Espenak (Five Millennium
   Canon). El JSON debe incluir fecha, tipo y los coeficientes; su esquema se
   documenta en el propio fichero.
2. **Algoritmo**: implementación en Swift puro del cálculo estándar de
   circunstancias locales a partir de elementos besselianos (el mismo método
   de las calculadoras de Espenak/O'Byrne): iteración de contactos C1–C4,
   máximo, magnitud, duración, altura/azimut solar. Documentar cada función
   con `///` citando la fuente del método.
3. **Selección**: dado (lat, lon, fecha), buscar en el dataset un eclipse en
   esa fecha (±1 día por husos horarios) y comprobar visibilidad en el punto.
   Sin resultado → modo simulación.
4. **Validación obligatoria (test de aceptación)** — Swift Testing:
   - Raimat Natura, Lleida — 41.68294 N, 0.47930 E, 12/08/2026 debe dar
     (CEST): C1 ≈ 19:34:39, C2 ≈ 20:29:06, máximo ≈ 20:29:20,
     C3 ≈ 20:29:35. Tolerancia: ±10 s (efectos de limbo aparte).
   - Un punto claramente fuera de la franja (p. ej. Sevilla ese día es
     parcial: debe devolver parcial sin C2/C3; y un punto en América debe
     devolver «sin eclipse»).
   - El motor no debe dar por buena ninguna cifra sin pasar estos tests.

Este motor se construye **primero** y se valida antes de tocar la UI.

---

## 5. Voz (SpeechService)

- `AVSpeechSynthesizer` con voz según el idioma de ajustes: `es-ES`, `ca-ES`,
  `en-GB`. Si la voz del idioma no está instalada, degradar a la voz por
  defecto del sistema y avisar en Ajustes.
- Cola propia: si dos avisos coinciden, se pronuncian en orden sin solaparse.
- Configurar `AVAudioSession` categoría `.playback`, opción `.duckOthers`,
  activada al entrar en ejecución y desactivada al salir.

---

## 6. Interfaz — criterios

- Tipografía con estilos semánticos (Dynamic Type). La cuenta atrás del
  próximo evento debe ser legible a un metro: `system(size:)` grande solo ahí,
  con `minimumScaleFactor`.
- Alto contraste, fondo oscuro. Estética sobria: negro/gris con acento dorado
  (coherente con el universo visual de Francisco: #b8985a como referencia).
- Targets táctiles ≥ 44 pt. `leading`/`trailing`, nunca `left`/`right`.
- Layouts adaptativos; probar en iPhone compacto y grande. Target: iPhone
  (TARGETED_DEVICE_FAMILY 1). iPad no es objetivo en v1.

---

## 7. Estándares de código (obligatorios)

### Reglas de sesión (no negociables)

1. **Documentación exhaustiva en inglés**: todo símbolo público lleva DocC
   completo (`///` con `- Parameters:`, `- Returns:`, `- Throws:`, y una
   descripción del propósito y el método empleado). Las secciones internas
   se separan con `// MARK: -`. Los algoritmos numéricos citan la fuente
   (`// Ref: Meeus "Astronomical Algorithms" ch.54`). Sin esta documentación
   el código no se considera terminado.

2. **Cero errores de compilación antes de entregar**: tras cada cambio,
   compilar con `BuildProject`. Si hay errores, corregirlos en la misma
   sesión hasta que el build sea limpio. Francisco no prueba código que no
   compila.

3. **Push a GitHub tras confirmación de Francisco**: cuando Francisco confirme
   que algo funciona correctamente, hacer commit descriptivo y push inmediato.
   No acumular cambios sin subir.

- Swift 5.9+ moderno: `async/await`, actors donde aplique; nada de GCD/callbacks.
- SwiftUI puro; UIKit solo justificado en comentario.
- `struct` por defecto; `let` sobre `var`; sin force unwrapping (`guard let`).
- Identificadores y tipos en **inglés**; comentarios en **español**.
- **Localización total es/ca/en** con String Catalogs (`Localizable.xcstrings`).
  Ningún texto visible hardcodeado. `String(localized:comment:)` en código.
  Fechas/horas/números siempre con `FormatStyle`.
- **Sin dependencias externas** (SPM/CocoaPods) sin preguntar antes. Solo
  frameworks del sistema.
- No usar APIs deprecadas si existe alternativa moderna.
- Pruebas con **Swift Testing** (`@Test`, `#expect`) — imprescindibles para
  `EclipseEngine` y la resolución de offsets del programa.
- Compilar antes de dar por terminado cualquier cambio; si hay tests,
  ejecutarlos.

## 8. Proyecto, firma y repositorio

- Nombre del target: `ControlTiemposEclipse`.
  Bundle ID: `com.cornellana.ControlTiemposEclipse`.
- Firma automática. **DEVELOPMENT_TEAM: TJ6V4QM3GB** (Francisco Cornellana
  Castells). Deployment target: iOS 17.0 (subir solo si una API lo exige y
  Francisco lo aprueba).
- `Info.plist`: `NSLocationWhenInUseUsageDescription` con texto localizado
  explicando que la ubicación se usa para calcular el eclipse en el punto.
- El proyecto lo gestiona Xcode de forma nativa (no se usa XcodeGen en este
  proyecto; no editar el `.pbxproj` a mano fuera de las herramientas de Xcode).
- **Repositorio público en GitHub desde el primer commit**:
  `gh repo create cornellana/control-tiempos-eclipse --public --source=. --remote=origin --push`
  `.gitignore` mínimo: `.DS_Store`, `xcuserdata/`, `DerivedData/`, `.build/`,
  `*.xcworkspace/xcuserdata/`.
- Push tras cada cambio significativo y al final de cada sesión.

## 9. Icono

- Script `scripts/render_icon.swift` con **CoreGraphics puro** (no
  NSGraphicsContext) que exporta PNG **1024×1024 sin canal alfa**
  (`CGImageAlphaInfo.noneSkipLast`).
- Motivo: anillo de diamantes de un eclipse total — disco negro, corona
  fina luminosa y un destello dorado (#b8985a) sobre fondo degradado oscuro.
  Sin esquinas redondeadas (las aplica el sistema).
- Asset catalog con un único `universal` 1024×1024. Revisar el PNG
  visualmente antes de darlo por bueno.

## 10. Plan de trabajo (hitos)

El eclipse real es el **12 de agosto de 2026** — no hay segunda oportunidad.

1. **Hito 1 — Motor** · `EclipseEngine` + dataset + tests de aceptación de
   Raimat en verde. Nada de UI hasta que esto pase.
2. **Hito 2 — Flujo completo** · Pasos 1–4 (localización, fecha, mapa +
   verificación, programa con persistencia) y modo simulación funcionando.
3. **Hito 3 — Ejecución** · Pantalla de ejecución con voz, scroll, háptica,
   parada protegida. Probar una simulación completa de principio a fin.
4. **Hito 4 — Pulido y ensayo** · Icono, localización ca/en completa, ajustes,
   pruebas en el iPhone real de Francisco. **Ensayo general con cámaras la
   primera semana de agosto.** Congelación de código el 9 de agosto.

En cada hito: compilar, pasar tests, commit + push, y confirmar con Francisco
antes de continuar.

## 11. Qué NO hacer

- No usar red ni APIs online para el cálculo del eclipse: todo offline.
- No usar notificaciones locales como mecanismo de avisos.
- No introducir dependencias externas sin preguntar.
- No acumular timers relativos (deriva): siempre `Date` absolutos.
- No dar por válido el motor sin los tests de aceptación de la sección 4.
- No avanzar varios hitos sin confirmación: un paso cada vez.
